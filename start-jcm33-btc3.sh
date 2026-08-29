#!/usr/bin/env bash
# Production supervisor for the hardware-qualified JCM33 dual-FPGA
# BitcoinIII 650 MHz miner.

set -Eeuo pipefail
IFS=$'\n\t'

readonly APP_NAME="jcm33-btc3"
readonly VERSION="0.1.0-rc1"
readonly EXPECTED_BITSTREAM_SHA="0eacb71eb4cb5f6a43f761d1af64dfe25c8fa22177974082742dc12d6f6cdcf1"
readonly EXPECTED_ROLLBACK_SHA="2abff6fc716bdea86d7c88865e07dcd380a89564f9267654910b5931a3f2f85b"
readonly EXPECTED_BRIDGE_SHA="fd1a550af5eb5dab475071a8f08f181c0b0d308233cbca805c52e3a96f342141"
readonly EXPECTED_MINER_SHA="1d64c8e7d2650e3733a26985f271779dbf5b36fea46e5c6ea7e6c605681c3593"
readonly DEFAULT_CARRIER="192.168.1.222"
readonly DEFAULT_BASE_PORT="2000"
readonly DEFAULT_XVC_PORT="2542"
readonly DEFAULT_POOL_HOST="stratum.pythonpool.dev"
readonly DEFAULT_POOL_PORT="3357"

SCRIPT_DIR=$(CDPATH='' cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)
SCRIPT_PATH="$SCRIPT_DIR/$(basename -- "${BASH_SOURCE[0]}")"
JCM33_PACKAGE="$SCRIPT_DIR/research/jcm33_dualalign_btc3_650"

BITSTREAM="$SCRIPT_DIR/hardware/prebuilt/jcm33_bitcoiniii_dualalign_650_validated.bit"
ROLLBACK_BITSTREAM="$JCM33_PACKAGE/qualified_587p5/jcm33_dualalign_bscan_587p5.bit"
BRIDGE="$JCM33_PACKAGE/sqrl_bridge_rawjtag_coe_jcm33_xvc"
MINER="$JCM33_PACKAGE/jcm33_btc3_dual_miner.py"
TIMING_GATE="$JCM33_PACKAGE/reports/timing-gate.pass"

COMMAND="start"
CONFIG_FILE="${JCM33_BTC3_CONFIG:-$SCRIPT_DIR/config-jcm33-btc3.env}"
CONFIG_EXPLICIT=0
WALLET="${BTC3_WALLET:-}"
WORKER="${BTC3_WORKER:-$(hostname -s 2>/dev/null || printf 'jcm33')-dual}"
POOL_HOST="${BTC3_POOL_HOST:-$DEFAULT_POOL_HOST}"
POOL_PORT="${BTC3_POOL_PORT:-$DEFAULT_POOL_PORT}"
CARRIER="${JCM33_CARRIER:-$DEFAULT_CARRIER}"
BASE_PORT="${JCM33_BASE_PORT:-$DEFAULT_BASE_PORT}"
XVC_PORT="${JCM33_XVC_PORT:-$DEFAULT_XVC_PORT}"
LIB_DIR="${JCM33_LIB_DIR:-$HOME/jc33_compat_libs}"
STATE_DIR="${JCM33_STATE_DIR:-${XDG_STATE_HOME:-$HOME/.local/state}/$APP_NAME}"
WORK_ROLL_SECONDS="${BTC3_WORK_ROLL_SECONDS:-7.5}"
START_TIMEOUT="${JCM33_START_TIMEOUT:-420}"
STOP_TIMEOUT="${JCM33_STOP_TIMEOUT:-240}"
DRY_RUN=0
LOG_LINES=120
FOLLOW_LOGS=0

SUPERVISOR_PID=""
BRIDGE_PID=""
MINER_PID=""
PROGRAM_ATTEMPTED=0
ROLLBACK_RESULT="not-needed"
EXIT_REASON="not-started"
BRIDGE_LD_LIBRARY_PATH="${LD_LIBRARY_PATH:-}"
RUNTIME_FILE=""

say()  { printf '%s\n' "$*"; }
info() { printf '[INFO] %s\n' "$*"; }
warn() { printf '[WARN] %s\n' "$*" >&2; }
die()  { printf '[ERROR] %s\n' "$*" >&2; exit 1; }

usage() {
    cat <<'USAGE'
JCM33 BitcoinIII 650 MHz production launcher

Usage:
  ./start-jcm33-btc3.sh [start] [options]
  ./start-jcm33-btc3.sh run [options]       # foreground supervisor/systemd
  ./start-jcm33-btc3.sh doctor [options]    # read-only; never programs
  ./start-jcm33-btc3.sh status [options]
  ./start-jcm33-btc3.sh logs [--lines N] [--follow]
  ./start-jcm33-btc3.sh stop [options]

Start, run, and doctor options:
  --config FILE         Configuration file
  --wallet ADDRESS      Operator BitcoinIII bc1q address (required)
  --worker NAME         Base pool worker (default: HOSTNAME-dual)
  --carrier HOST        JCM33 carrier (default: 192.168.1.222)
  --base-port PORT      Carrier bridge base port (default: 2000)
  --xvc-port PORT       Local XVC port (default: 2542)
  --pool-host HOST      BitcoinIII Stratum host
  --pool-port PORT      BitcoinIII Stratum port
  --compat-libs DIR     Optional bridge compatibility libraries
  --state-dir DIR       Runtime state and logs directory
  --work-roll SECONDS   Extranonce work-roll interval (1.0-8.0)
  --dry-run             Validate files and print the plan; no network/hardware

Commands:
  start                 Launch the production supervisor in the background
  run                   Run the production supervisor in the foreground
  doctor                Validate files, carrier, pool, ports, and conflicts
  status                Show process health and share counters
  logs                  Show supervisor, bridge, and miner logs
  stop                  Stop mining and restore qualified 587.5 MHz on both FPGAs

Safety boundary:
  The launcher accepts only the published checksum-pinned 650 MHz bitstream,
  requires both JCM33 FPGAs, never changes voltage, and restores the published
  qualified 587.5 MHz image on a controlled stop or detected runtime failure.
  It refuses to start while another bridge targets the selected JCM33 carrier,
  but it does not stop or alter unrelated FK33/USB bridge processes.
USAGE
}

need_value() {
    [[ -n ${2:-} ]] || die "$1 requires a value"
}

is_uint() {
    [[ $1 =~ ^[0-9]+$ ]]
}

valid_port() {
    is_uint "$1" && ((10#$1 >= 1 && 10#$1 <= 65535))
}

discover_config() {
    local -a args=("$@")
    local index
    for ((index = 0; index < ${#args[@]}; index++)); do
        if [[ ${args[$index]} == --config ]]; then
            ((index + 1 < ${#args[@]})) || die "--config requires a value"
            CONFIG_FILE=${args[$((index + 1))]}
            CONFIG_EXPLICIT=1
        fi
    done
}

load_config() {
    if [[ ! -f $CONFIG_FILE ]]; then
        ((CONFIG_EXPLICIT == 0)) && return 0
        die "configuration file is missing: $CONFIG_FILE"
    fi

    local mode
    mode=$(stat -c '%a' "$CONFIG_FILE" 2>/dev/null || true)
    if [[ -n $mode ]] && (((8#$mode & 8#022) != 0)); then
        die "$CONFIG_FILE is group/other writable; run: chmod 600 '$CONFIG_FILE'"
    fi

    # This is an operator-owned shell environment file. Refuse unsafe modes
    # above before sourcing it.
    # shellcheck disable=SC1090
    source "$CONFIG_FILE"

    WALLET="${BTC3_WALLET:-$WALLET}"
    WORKER="${BTC3_WORKER:-$WORKER}"
    POOL_HOST="${BTC3_POOL_HOST:-$POOL_HOST}"
    POOL_PORT="${BTC3_POOL_PORT:-$POOL_PORT}"
    CARRIER="${JCM33_CARRIER:-$CARRIER}"
    BASE_PORT="${JCM33_BASE_PORT:-$BASE_PORT}"
    XVC_PORT="${JCM33_XVC_PORT:-$XVC_PORT}"
    LIB_DIR="${JCM33_LIB_DIR:-$LIB_DIR}"
    STATE_DIR="${JCM33_STATE_DIR:-$STATE_DIR}"
    WORK_ROLL_SECONDS="${BTC3_WORK_ROLL_SECONDS:-$WORK_ROLL_SECONDS}"
    START_TIMEOUT="${JCM33_START_TIMEOUT:-$START_TIMEOUT}"
    STOP_TIMEOUT="${JCM33_STOP_TIMEOUT:-$STOP_TIMEOUT}"
}

parse_args() {
    if (($#)); then
        case $1 in
            start|run|doctor|status|logs|stop) COMMAND=$1; shift ;;
            -h|--help) usage; exit 0 ;;
            -V|--version) say "$APP_NAME $VERSION"; exit 0 ;;
        esac
    fi

    while (($#)); do
        case $1 in
            --config) need_value "$1" "${2:-}"; CONFIG_FILE=$2; shift 2 ;;
            --wallet) need_value "$1" "${2:-}"; WALLET=$2; shift 2 ;;
            --worker) need_value "$1" "${2:-}"; WORKER=$2; shift 2 ;;
            --carrier) need_value "$1" "${2:-}"; CARRIER=$2; shift 2 ;;
            --base-port) need_value "$1" "${2:-}"; BASE_PORT=$2; shift 2 ;;
            --xvc-port) need_value "$1" "${2:-}"; XVC_PORT=$2; shift 2 ;;
            --pool-host) need_value "$1" "${2:-}"; POOL_HOST=$2; shift 2 ;;
            --pool-port) need_value "$1" "${2:-}"; POOL_PORT=$2; shift 2 ;;
            --compat-libs) need_value "$1" "${2:-}"; LIB_DIR=$2; shift 2 ;;
            --state-dir) need_value "$1" "${2:-}"; STATE_DIR=$2; shift 2 ;;
            --work-roll) need_value "$1" "${2:-}"; WORK_ROLL_SECONDS=$2; shift 2 ;;
            --lines) need_value "$1" "${2:-}"; LOG_LINES=$2; shift 2 ;;
            --follow) FOLLOW_LOGS=1; shift ;;
            --dry-run) DRY_RUN=1; shift ;;
            -h|--help) usage; exit 0 ;;
            -V|--version) say "$APP_NAME $VERSION"; exit 0 ;;
            *) die "unknown argument: $1 (try --help)" ;;
        esac
    done
}

validate_settings() {
    [[ $WALLET =~ ^bc1q[023456789acdefghjklmnpqrstuvwxyz]{20,86}$ ]] ||
        die "missing or invalid operator wallet; use --wallet 'bc1qYOUR_ADDRESS'"
    [[ $WORKER =~ ^[A-Za-z0-9_-]{1,64}$ ]] ||
        die "worker must contain 1-64 letters, digits, underscores, or dashes"
    [[ $POOL_HOST =~ ^[A-Za-z0-9.-]+$ ]] || die "invalid pool host"
    [[ $CARRIER =~ ^[A-Za-z0-9.-]+$ ]] || die "invalid carrier host"
    valid_port "$POOL_PORT" || die "pool port must be between 1 and 65535"
    valid_port "$BASE_PORT" || die "base port must be between 1 and 65534"
    ((10#$BASE_PORT < 65535)) || die "base port must leave room for device B"
    valid_port "$XVC_PORT" || die "XVC port must be between 1 and 65535"
    ((10#$XVC_PORT != 10#$BASE_PORT)) || die "XVC port must differ from device A"
    ((10#$XVC_PORT != 10#$BASE_PORT + 1)) || die "XVC port must differ from device B"
    [[ $WORK_ROLL_SECONDS =~ ^[0-9]+([.][0-9]+)?$ ]] ||
        die "work-roll must be numeric"
    awk -v value="$WORK_ROLL_SECONDS" \
        'BEGIN { exit !(value >= 1.0 && value <= 8.0) }' ||
        die "work-roll must be between 1.0 and 8.0 seconds"
    is_uint "$START_TIMEOUT" || die "JCM33_START_TIMEOUT must be an integer"
    is_uint "$STOP_TIMEOUT" || die "JCM33_STOP_TIMEOUT must be an integer"
    ((10#$START_TIMEOUT >= 180)) || die "start timeout must be at least 180 seconds"
    ((10#$STOP_TIMEOUT >= 180)) || die "stop timeout must be at least 180 seconds"
    [[ -n $STATE_DIR && $STATE_DIR != / ]] || die "unsafe state directory"
}

sha_of() {
    sha256sum -- "$1" | awk '{print $1}'
}

require_sha() {
    local file=$1 expected=$2 label=$3 actual
    [[ -f $file ]] || die "$label is missing: $file"
    actual=$(sha_of "$file")
    [[ $actual == "$expected" ]] ||
        die "$label checksum mismatch: expected=$expected actual=$actual"
    info "$label checksum $actual"
}

configure_library_path() {
    BRIDGE_LD_LIBRARY_PATH="${LD_LIBRARY_PATH:-}"
    if [[ -d $LIB_DIR ]]; then
        BRIDGE_LD_LIBRARY_PATH="$LIB_DIR${BRIDGE_LD_LIBRARY_PATH:+:$BRIDGE_LD_LIBRARY_PATH}"
        info "compatibility libraries enabled: $LIB_DIR"
    else
        info "compatibility directory absent; using system libraries"
    fi
}

static_preflight() {
    local command_name ldd_output ldd_status
    for command_name in awk date flock grep ldd nohup ps python3 sha256sum stat tail tr; do
        command -v "$command_name" >/dev/null || die "$command_name is required"
    done

    [[ -x $BRIDGE ]] || die "JCM33 XVC bridge is not executable: $BRIDGE"
    [[ -r $MINER ]] || die "JCM33 dual miner is unreadable: $MINER"
    [[ -f $TIMING_GATE ]] || die "650 MHz timing gate marker is missing"
    grep -qx 'TIMING GATE PASS' "$TIMING_GATE" ||
        die "650 MHz timing gate marker is invalid"

    require_sha "$BITSTREAM" "$EXPECTED_BITSTREAM_SHA" \
        "qualified 650 MHz bitstream"
    require_sha "$ROLLBACK_BITSTREAM" "$EXPECTED_ROLLBACK_SHA" \
        "qualified 587.5 MHz rollback image"
    require_sha "$BRIDGE" "$EXPECTED_BRIDGE_SHA" "JCM33 XVC bridge"
    require_sha "$MINER" "$EXPECTED_MINER_SHA" "JCM33 dual miner"

    configure_library_path
    set +e
    ldd_output=$(env LD_LIBRARY_PATH="$BRIDGE_LD_LIBRARY_PATH" \
        ldd "$BRIDGE" 2>&1)
    ldd_status=$?
    set -e
    if grep -q 'not found' <<<"$ldd_output"; then
        die "JCM33 XVC bridge has unresolved shared libraries"
    fi
    ((ldd_status == 0)) || die "could not inspect JCM33 XVC bridge libraries"
    info "JCM33 XVC bridge libraries resolved"

    JCM33_SELF_TEST=1 PYTHONDONTWRITEBYTECODE=1 python3 "$MINER"
}

print_plan() {
    say "===== JCM33 BITCOINIII 650 MHz PRODUCTION PLAN ====="
    say "version:          $VERSION"
    say "command:          $COMMAND"
    say "carrier:          $CARRIER"
    say "device ports:     $BASE_PORT/$((10#$BASE_PORT + 1))"
    say "local XVC:        127.0.0.1:$XVC_PORT"
    say "pool:             $POOL_HOST:$POOL_PORT"
    say "operator wallet:  $WALLET"
    say "worker:           $WORKER"
    say "developer worker: ${WORKER:0:$((64 - 7))}-DEVFEE"
    say "work roll:        ${WORK_ROLL_SECONDS}s"
    say "bitstream:        $BITSTREAM"
    say "rollback:         $ROLLBACK_BITSTREAM"
    say "state:            $STATE_DIR"
    say "voltage:          unchanged; no voltage option is used"
    say "stop/fault:       restore qualified 587.5 MHz on both devices"
}

targeting_bridge_processes() {
    pgrep -af '[s]qrl_bridge' 2>/dev/null |
        grep -F -- "-c $CARRIER" || true
}

port_is_listening() {
    local port=$1 sockets
    sockets=$(ss -ltnH 2>/dev/null) || return 1
    awk -v expected="$port" '
        {
            endpoint = $4
            sub(/^.*:/, "", endpoint)
            if (endpoint == expected)
                found = 1
        }
        END { exit !found }
    ' <<<"$sockets"
}

wait_for_carrier() {
    local attempt
    for attempt in {1..12}; do
        if ping -c 1 -W 1 "$CARRIER" >/dev/null 2>&1; then
            info "carrier reachable on attempt $attempt"
            return 0
        fi
        sleep 5
    done
    return 1
}

check_pool() {
    python3 - "$POOL_HOST" "$POOL_PORT" <<'PY'
import socket
import sys

with socket.create_connection((sys.argv[1], int(sys.argv[2])), timeout=5):
    pass
PY
}

network_preflight() {
    local command_name existing port
    for command_name in pgrep ping ss; do
        command -v "$command_name" >/dev/null || die "$command_name is required"
    done
    existing=$(targeting_bridge_processes)
    if [[ -n $existing ]]; then
        printf '%s\n' "$existing" >&2
        die "a bridge targeting JCM33 carrier $CARRIER is already running"
    fi
    info "no bridge currently targets JCM33 carrier $CARRIER"
    info "unrelated USB/FK bridge processes are preserved"

    wait_for_carrier || die "carrier $CARRIER remained unreachable for 60 seconds"
    check_pool || die "BitcoinIII pool $POOL_HOST:$POOL_PORT is unreachable"
    info "BitcoinIII pool is reachable"

    for port in "$BASE_PORT" "$((10#$BASE_PORT + 1))" "$XVC_PORT"; do
        port_is_listening "$port" && die "local TCP port $port is already listening"
    done
    info "required local ports are free"
}

ensure_state_dir() {
    mkdir -p -- "$STATE_DIR" "$STATE_DIR/history"
    chmod 700 -- "$STATE_DIR" "$STATE_DIR/history"
}

pid_from_file() {
    local file=$1 pid
    [[ -r $file ]] || return 1
    read -r pid <"$file"
    [[ $pid =~ ^[0-9]+$ ]] || return 1
    printf '%s\n' "$pid"
}

pid_command_line() {
    local pid=$1 command_line
    if [[ -r /proc/$pid/cmdline ]]; then
        command_line=$(tr '\0' ' ' <"/proc/$pid/cmdline")
    else
        command_line=$(ps -o args= -p "$pid" 2>/dev/null || true)
    fi
    [[ -n $command_line ]] || return 1
    printf '%s\n' "$command_line"
}

pid_cmdline_contains() {
    local pid=$1 token=$2 command_line
    command_line=$(pid_command_line "$pid") || return 1
    [[ $command_line == *"$token"* ]]
}

supervisor_running() {
    local pid
    pid=$(pid_from_file "$STATE_DIR/supervisor.pid") || return 1
    kill -0 "$pid" 2>/dev/null || return 1
    if ! pid_cmdline_contains "$pid" "$SCRIPT_PATH"; then
        # Some containers expose a host /proc while kill(2) uses a nested PID
        # namespace. In that case command-line verification is impossible.
        # Accept the PID only while the private runtime lock is still held.
        if flock -n "$STATE_DIR/runtime.lock" -c true 2>/dev/null; then
            return 1
        fi
    fi
    printf '%s\n' "$pid"
}

archive_previous_logs() {
    local stamp archive file moved=0
    stamp=$(date -u +%Y%m%dT%H%M%SZ)
    archive="$STATE_DIR/history/$stamp"
    for file in \
        supervisor.log bridge.log bridge-stdout.log miner.log \
        program-650.log program-650-stdout.log \
        restore-587p5.log restore-587p5-stdout.log \
        ready failed stopped rollback.ok rollback.failed exit-reason; do
        if [[ -e $STATE_DIR/$file ]]; then
            ((moved == 1)) || mkdir -p -- "$archive"
            moved=1
            mv -- "$STATE_DIR/$file" "$archive/$file"
        fi
    done
    ((moved == 0)) || info "previous runtime evidence archived at $archive"
    rm -f -- "$STATE_DIR/supervisor.pid" "$STATE_DIR/bridge.pid" "$STATE_DIR/miner.pid"
}

write_runtime_config() {
    local runtime_file="$STATE_DIR/runtime.env"
    umask 077
    {
        printf 'WALLET=%q\n' "$WALLET"
        printf 'WORKER=%q\n' "$WORKER"
        printf 'POOL_HOST=%q\n' "$POOL_HOST"
        printf 'POOL_PORT=%q\n' "$POOL_PORT"
        printf 'CARRIER=%q\n' "$CARRIER"
        printf 'BASE_PORT=%q\n' "$BASE_PORT"
        printf 'XVC_PORT=%q\n' "$XVC_PORT"
        printf 'LIB_DIR=%q\n' "$LIB_DIR"
        printf 'STATE_DIR=%q\n' "$STATE_DIR"
        printf 'WORK_ROLL_SECONDS=%q\n' "$WORK_ROLL_SECONDS"
        printf 'START_TIMEOUT=%q\n' "$START_TIMEOUT"
        printf 'STOP_TIMEOUT=%q\n' "$STOP_TIMEOUT"
    } >"$runtime_file"
    chmod 600 -- "$runtime_file"
    printf '%s\n' "$runtime_file"
}

wait_for_loads() {
    local log=$1 pid=$2 label=$3 deadline
    deadline=$((SECONDS + 120))
    while ((SECONDS < deadline)); do
        if [[ -f $log ]] &&
           grep -q 'SQRL JTAG Board 0 Device 0 Bitstream Loaded' "$log" &&
           grep -q 'SQRL JTAG Board 0 Device 1 Bitstream Loaded' "$log"; then
            info "$label loaded on both JCM33 devices"
            return 0
        fi
        if ! kill -0 "$pid" 2>/dev/null; then
            warn "programming bridge exited before both devices loaded"
            tail -120 "$log" 2>/dev/null || true
            return 1
        fi
        sleep 1
    done
    warn "timed out loading $label"
    tail -120 "$log" 2>/dev/null || true
    return 1
}

stop_child() {
    local pid=${1:-} token=${2:-} attempt running_job_pids
    [[ $pid =~ ^[0-9]+$ ]] || return 0
    kill -0 "$pid" 2>/dev/null || return 0

    # Bash's running-job table is authoritative for children created with $!.
    # It remains correct even when a container's /proc exposes host PIDs.
    running_job_pids=$(jobs -pr)
    if [[ $'\n'$running_job_pids$'\n' != *$'\n'$pid$'\n'* ]]; then
        wait "$pid" 2>/dev/null || true
        return 0
    fi
    kill -TERM "$pid" 2>/dev/null || true
    for attempt in {1..100}; do
        kill -0 "$pid" 2>/dev/null || break
        sleep 0.1
    done
    if kill -0 "$pid" 2>/dev/null; then
        kill -KILL "$pid" 2>/dev/null || true
    fi
    wait "$pid" 2>/dev/null || true
}

launch_program_bridge() {
    local image=$1 name=$2
    env LD_LIBRARY_PATH="$BRIDGE_LD_LIBRARY_PATH" \
        "$BRIDGE" -c "$CARRIER" -b "$image" -p "$BASE_PORT" -t \
        -f "$STATE_DIR/$name.log" \
        >>"$STATE_DIR/$name-stdout.log" 2>&1 &
    BRIDGE_PID=$!
}

restore_qualified_587p5() {
    info "restoring qualified 587.5 MHz image on both JCM33 devices"
    wait_for_carrier || {
        warn "carrier is unreachable; automatic rollback could not start"
        return 1
    }
    launch_program_bridge "$ROLLBACK_BITSTREAM" restore-587p5
    if wait_for_loads "$STATE_DIR/restore-587p5.log" "$BRIDGE_PID" \
        "qualified 587.5 MHz rollback image"; then
        stop_child "$BRIDGE_PID" "$BRIDGE" || true
        BRIDGE_PID=""
        : >"$STATE_DIR/rollback.ok"
        rm -f -- "$STATE_DIR/rollback.failed"
        info "rollback passed; both JCM33 FPGAs are at qualified 587.5 MHz"
        return 0
    fi
    stop_child "$BRIDGE_PID" "$BRIDGE" || true
    BRIDGE_PID=""
    : >"$STATE_DIR/rollback.failed"
    warn "rollback failed; verify both FPGA images before mining"
    return 1
}

program_650() {
    info "programming the qualified 650 MHz production image"
    PROGRAM_ATTEMPTED=1
    launch_program_bridge "$BITSTREAM" program-650
    wait_for_loads "$STATE_DIR/program-650.log" "$BRIDGE_PID" \
        "qualified 650 MHz production image"
    stop_child "$BRIDGE_PID" "$BRIDGE"
    BRIDGE_PID=""
    sleep 2
}

launch_xvc_bridge() {
    local deadline
    env LD_LIBRARY_PATH="$BRIDGE_LD_LIBRARY_PATH" \
        "$BRIDGE" -c "$CARRIER" -p "$BASE_PORT" -j "$XVC_PORT" -t \
        -f "$STATE_DIR/bridge.log" \
        >>"$STATE_DIR/bridge-stdout.log" 2>&1 &
    BRIDGE_PID=$!
    printf '%s\n' "$BRIDGE_PID" >"$STATE_DIR/bridge.pid"

    deadline=$((SECONDS + 30))
    while ((SECONDS < deadline)); do
        if port_is_listening "$XVC_PORT"; then
            info "XVC transport listening on 127.0.0.1:$XVC_PORT"
            return 0
        fi
        kill -0 "$BRIDGE_PID" 2>/dev/null || {
            tail -120 "$STATE_DIR/bridge.log" 2>/dev/null || true
            return 1
        }
        sleep 1
    done
    return 1
}

launch_miner() {
    env \
        BTC3_WALLET="$WALLET" \
        BTC3_POOL_HOST="$POOL_HOST" \
        BTC3_POOL_PORT="$POOL_PORT" \
        BTC3_WORKER="$WORKER" \
        BTC3_SERIAL="JCM33-DUAL" \
        BTC3_WORK_ROLL_SECONDS="$WORK_ROLL_SECONDS" \
        JCM33_XVC_HOST=127.0.0.1 \
        JCM33_XVC_PORT="$XVC_PORT" \
        PYTHONDONTWRITEBYTECODE=1 \
        python3 -u "$MINER" >>"$STATE_DIR/miner.log" 2>&1 &
    MINER_PID=$!
    printf '%s\n' "$MINER_PID" >"$STATE_DIR/miner.pid"
}

wait_for_miner_ready() {
    local deadline=$((SECONDS + 120))
    while ((SECONDS < deadline)); do
        kill -0 "$BRIDGE_PID" 2>/dev/null || return 1
        kill -0 "$MINER_PID" 2>/dev/null || return 1
        if grep -Fq '[*] XVC connected' "$STATE_DIR/miner.log" 2>/dev/null; then
            info "dual miner connected to both-device XVC transport"
            return 0
        fi
        sleep 1
    done
    return 1
}

cleanup_supervisor() {
    local status=$?
    trap - EXIT
    # A second stop request must not interrupt the rollback already in flight.
    trap '' INT TERM
    rm -f -- "$STATE_DIR/ready"
    stop_child "$MINER_PID" "$MINER" || true
    MINER_PID=""
    stop_child "$BRIDGE_PID" "$BRIDGE" || true
    BRIDGE_PID=""
    rm -f -- "$STATE_DIR/miner.pid" "$STATE_DIR/bridge.pid"

    if ((PROGRAM_ATTEMPTED)); then
        if restore_qualified_587p5; then
            ROLLBACK_RESULT="pass"
        else
            ROLLBACK_RESULT="fail"
            ((status == 0)) && status=1
        fi
    fi

    printf '%s\n' "$EXIT_REASON" >"$STATE_DIR/exit-reason"
    if ((status == 0)); then
        : >"$STATE_DIR/stopped"
    else
        : >"$STATE_DIR/failed"
    fi
    rm -f -- "$STATE_DIR/supervisor.pid"
    info "supervisor exit reason=$EXIT_REASON rollback=$ROLLBACK_RESULT status=$status"
    exit "$status"
}

handle_supervisor_stop() {
    EXIT_REASON="requested-stop"
    exit 0
}

supervisor_main() {
    local runtime_file=$1 runtime_lock
    [[ -r $runtime_file ]] || die "runtime configuration is missing: $runtime_file"
    # shellcheck disable=SC1090
    source "$runtime_file"
    validate_settings
    configure_library_path

    runtime_lock="$STATE_DIR/runtime.lock"
    exec 8>"$runtime_lock"
    flock -n 8 || die "another JCM33 production supervisor holds $runtime_lock"

    SUPERVISOR_PID=$$
    printf '%s\n' "$SUPERVISOR_PID" >"$STATE_DIR/supervisor.pid"
    trap cleanup_supervisor EXIT
    trap handle_supervisor_stop INT TERM

    EXIT_REASON="preflight-failure"
    static_preflight
    network_preflight

    EXIT_REASON="programming-failure"
    program_650

    EXIT_REASON="xvc-start-failure"
    launch_xvc_bridge || die "XVC bridge did not become ready"

    EXIT_REASON="miner-start-failure"
    launch_miner
    wait_for_miner_ready || {
        tail -160 "$STATE_DIR/miner.log" 2>/dev/null || true
        die "dual miner did not connect to the two-device XVC transport"
    }

    date -u +%Y-%m-%dT%H:%M:%SZ >"$STATE_DIR/ready"
    rm -f -- "$STATE_DIR/failed" "$STATE_DIR/stopped"
    EXIT_REASON="runtime-failure"
    info "JCM33 650 MHz production supervisor is ready"

    while true; do
        kill -0 "$BRIDGE_PID" 2>/dev/null || die "XVC bridge exited unexpectedly"
        kill -0 "$MINER_PID" 2>/dev/null || die "dual miner exited unexpectedly"
        if grep -Fq 'SHARE mismatch' "$STATE_DIR/miner.log" 2>/dev/null; then
            die "hardware/software digest mismatch detected"
        fi
        sleep 2
    done
}

prepare_runtime() {
    ensure_state_dir
    if local running_pid; running_pid=$(supervisor_running); then
        die "JCM33 production supervisor is already running as PID $running_pid"
    fi
    archive_previous_logs
    RUNTIME_FILE=$(write_runtime_config)
}

command_doctor() {
    validate_settings
    print_plan
    static_preflight
    if ((DRY_RUN)); then
        say "DRY RUN PASS: files and configuration are valid; no network or hardware was accessed"
        return 0
    fi
    network_preflight
    say "DOCTOR PASS: JCM33 production preflight passed; no FPGA was programmed"
}

command_start() {
    local runtime_file launcher_pid deadline safe_deadline
    validate_settings
    print_plan
    static_preflight
    if ((DRY_RUN)); then
        say "DRY RUN PASS: no network, FPGA, bridge, miner, or voltage was accessed"
        return 0
    fi

    prepare_runtime
    runtime_file=$RUNTIME_FILE
    nohup "$SCRIPT_PATH" __supervise "$runtime_file" \
        >>"$STATE_DIR/supervisor.log" 2>&1 9>&- &
    launcher_pid=$!
    deadline=$((SECONDS + 10#$START_TIMEOUT))

    while ((SECONDS < deadline)); do
        if [[ -f $STATE_DIR/ready ]]; then
            say "START PASS: JCM33 650 MHz production mining is active"
            command_status
            return 0
        fi
        if ! kill -0 "$launcher_pid" 2>/dev/null; then
            warn "production supervisor exited during startup"
            tail -200 "$STATE_DIR/supervisor.log" 2>/dev/null || true
            return 1
        fi
        sleep 1
    done

    warn "startup timed out after $START_TIMEOUT seconds; requesting safe stop"
    kill -TERM "$launcher_pid" 2>/dev/null || true
    safe_deadline=$((SECONDS + 10#$STOP_TIMEOUT))
    while ((SECONDS < safe_deadline)); do
        kill -0 "$launcher_pid" 2>/dev/null || break
        sleep 1
    done
    if kill -0 "$launcher_pid" 2>/dev/null; then
        warn "supervisor did not finish rollback before the safe-stop timeout"
    elif [[ -e $STATE_DIR/rollback.ok ]]; then
        info "startup timeout cleanup restored both FPGAs to qualified 587.5 MHz"
    fi
    return 1
}

command_run() {
    local runtime_file
    validate_settings
    print_plan
    static_preflight
    ((DRY_RUN == 0)) || {
        say "DRY RUN PASS: foreground supervisor was not started"
        return 0
    }
    prepare_runtime
    runtime_file=$RUNTIME_FILE
    supervisor_main "$runtime_file"
}

load_runtime_state() {
    local runtime_file="$STATE_DIR/runtime.env"
    [[ -r $runtime_file ]] || return 0
    # Generated by this launcher with mode 0600.
    # shellcheck disable=SC1090
    source "$runtime_file"
}

share_count() {
    local pattern=$1
    if [[ -f $STATE_DIR/miner.log ]]; then
        grep -c -- "$pattern" "$STATE_DIR/miner.log" 2>/dev/null || true
    else
        printf '0\n'
    fi
}

command_status() {
    local running_pid accepted_a accepted_b rejected mismatches devfee
    load_runtime_state
    if running_pid=$(supervisor_running); then
        say "STATUS: RUNNING"
        say "supervisor_pid=$running_pid"
        [[ -r $STATE_DIR/bridge.pid ]] && say "bridge_pid=$(<"$STATE_DIR/bridge.pid")"
        [[ -r $STATE_DIR/miner.pid ]] && say "miner_pid=$(<"$STATE_DIR/miner.pid")"
        [[ -r $STATE_DIR/ready ]] && say "ready_at=$(<"$STATE_DIR/ready")"
        if port_is_listening "$XVC_PORT"; then
            say "xvc=LISTENING 127.0.0.1:$XVC_PORT"
        else
            say "xvc=NOT_LISTENING 127.0.0.1:$XVC_PORT"
        fi
    else
        say "STATUS: STOPPED"
        [[ -r $STATE_DIR/exit-reason ]] && say "exit_reason=$(<"$STATE_DIR/exit-reason")"
        [[ -e $STATE_DIR/rollback.ok ]] && say "rollback_587p5=PASS"
        [[ -e $STATE_DIR/rollback.failed ]] && say "rollback_587p5=FAIL"
    fi

    accepted_a=$(share_count 'ACCEPTED.*device=A')
    accepted_b=$(share_count 'ACCEPTED.*device=B')
    rejected=$(share_count 'REJECTED')
    mismatches=$(share_count 'SHARE mismatch')
    devfee=$(share_count '\[DEVFEE\]')
    say "accepted_A=$accepted_a"
    say "accepted_B=$accepted_b"
    say "rejected=$rejected"
    say "hardware_software_mismatches=$mismatches"
    say "devfee_log_events=$devfee"

    supervisor_running >/dev/null
}

command_logs() {
    is_uint "$LOG_LINES" || die "--lines must be a non-negative integer"
    ensure_state_dir
    local -a files=()
    local file
    for file in supervisor.log bridge.log bridge-stdout.log miner.log; do
        [[ -f $STATE_DIR/$file ]] && files+=("$STATE_DIR/$file")
    done
    ((${#files[@]})) || die "no JCM33 production logs exist in $STATE_DIR"
    if ((FOLLOW_LOGS)); then
        tail -n "$LOG_LINES" -F "${files[@]}"
    else
        tail -n "$LOG_LINES" "${files[@]}"
    fi
}

command_stop() {
    local running_pid deadline existing
    ensure_state_dir
    load_runtime_state
    command -v pgrep >/dev/null || die "pgrep is required for a safe stop"
    if ! running_pid=$(supervisor_running); then
        existing=$(targeting_bridge_processes)
        if [[ -n $existing ]]; then
            printf '%s\n' "$existing" >&2
            warn "a bridge still targets JCM33 carrier $CARRIER; refusing to claim a safe stop"
            return 1
        fi
        say "STOP: JCM33 production supervisor is not running"
        [[ -e $STATE_DIR/rollback.ok ]] && say "rollback_587p5=PASS"
        return 0
    fi

    info "requesting supervisor PID $running_pid to stop and restore 587.5 MHz"
    kill -TERM "$running_pid"
    deadline=$((SECONDS + 10#$STOP_TIMEOUT))
    while ((SECONDS < deadline)); do
        if ! kill -0 "$running_pid" 2>/dev/null; then
            if [[ -e $STATE_DIR/rollback.ok ]]; then
                say "STOP PASS: mining stopped and both JCM33 FPGAs restored to qualified 587.5 MHz"
                return 0
            fi
            warn "supervisor stopped without a confirmed rollback"
            command_status || true
            return 1
        fi
        sleep 1
    done
    warn "safe stop timed out; the supervisor was not force-killed because rollback may be active"
    return 1
}

internal_supervise() {
    (($# == 1)) || die "internal supervisor requires one runtime file"
    supervisor_main "$1"
}

if [[ ${1:-} == __supervise ]]; then
    shift
    internal_supervise "$@"
    exit 0
fi

discover_config "$@"
load_config
parse_args "$@"

case $COMMAND in
    start) command_start ;;
    run) command_run ;;
    doctor) command_doctor ;;
    status)
        ensure_state_dir
        command_status
        ;;
    logs) command_logs ;;
    stop) command_stop ;;
    *) die "unsupported command: $COMMAND" ;;
esac

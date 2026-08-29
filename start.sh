#!/usr/bin/env bash
# FK33 FJAR portable launcher
#
# This launcher never changes voltage.  The default accepted bitstream is the
# six-card fleet-tested 525 MHz image whose SHA-256 is pinned below. The
# one-card hardware-qualified native 650 MHz image and the unqualified 550 MHz
# candidate both require explicit selection.

set -Eeuo pipefail
IFS=$'\n\t'

readonly APP_NAME="fk33-fjar"
readonly VERSION="0.2.0-rc1"
readonly STABLE_BIT_SHA256="64e0a7d21a10b4aa04b340c826af7d75363b5d5ba5e39330fe28c42ff103821c"
readonly QUALIFIED_650_BIT_SHA256="bd494ba2ea697a5e916b51caf4bdab8e5c620cd121bfd4b2e9a806deb5596c39"
readonly EXPERIMENTAL_550_BIT_SHA256="de9621edb8fdb1df35270ac601668b0b30ada110c5ed446114755c7093a2e8db"
readonly DEFAULT_POOL_HOST="stratum.pythonpool.dev"
readonly DEFAULT_POOL_PORT="3358"
readonly DEFAULT_BASE_PORT="22000"

SCRIPT_DIR="$(CDPATH='' cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
BIN_DIR="${FK33_BIN_DIR:-$SCRIPT_DIR/third_party/sqrl}"
RUNTIME_DIR="${FK33_RUNTIME_DIR:-$SCRIPT_DIR/runtime}"
BITSTREAM_DIR="${FK33_BITSTREAM_DIR:-$SCRIPT_DIR/hardware/prebuilt}"
LIB_DIR="${FK33_LIB_DIR:-$SCRIPT_DIR/compat_libs}"
BRIDGE="${FK33_BRIDGE:-$BIN_DIR/sqrl_bridge_rawjtag_coe}"
MINER="${FK33_MINER:-$RUNTIME_DIR/fjar_bridge.py}"
STABLE_BITSTREAM="$BITSTREAM_DIR/fk33_fjar_bscan_525.bit"
QUALIFIED_650_BITSTREAM="$BITSTREAM_DIR/fk33_native_bscan_650_validated.bit"
EXPERIMENTAL_550_BITSTREAM="$BITSTREAM_DIR/fk33_fjar_bscan_550_experimental.bit"
BITSTREAM="${FK33_BITSTREAM:-$STABLE_BITSTREAM}"
CONFIG_FILE="${FK33_CONFIG:-$SCRIPT_DIR/config.env}"
STATE_DIR="${FK33_STATE_DIR:-${XDG_STATE_HOME:-$HOME/.local/state}/$APP_NAME}"

COMMAND="start"
WALLET="${FJAR_WALLET:-}"
POOL_HOST="${FJAR_POOL_HOST:-$DEFAULT_POOL_HOST}"
POOL_PORT="${FJAR_POOL_PORT:-$DEFAULT_POOL_PORT}"
BASE_PORT="${FJAR_BASE_PORT:-$DEFAULT_BASE_PORT}"
WORKER_PREFIX="${FJAR_WORKER_PREFIX:-$(hostname -s 2>/dev/null || printf 'fk33')}"
SERIAL_INPUT="${FJAR_SERIALS:-}"
ALLOW_MISMATCH="${FK33_ALLOW_CARD_COUNT_MISMATCH:-0}"
ALLOW_QUALIFIED_650="${FK33_ALLOW_QUALIFIED_650:-0}"
ALLOW_EXPERIMENTAL_550="${FK33_ALLOW_EXPERIMENTAL_550:-0}"
ALLOW_UNVERIFIED="${FK33_ALLOW_UNVERIFIED_BITSTREAM:-0}"
BITSTREAM_MODE="not checked"
DRY_RUN=0
FORCE_STOP=0
STARTED_BRIDGE_PID=""
declare -a SERIALS=()
declare -a STARTED_WORKER_PIDS=()

say()  { printf '%s\n' "$*"; }
info() { printf '[INFO] %s\n' "$*"; }
warn() { printf '[WARN] %s\n' "$*" >&2; }
die()  { printf '[ERROR] %s\n' "$*" >&2; exit 1; }

usage() {
  cat <<'USAGE'
FK33 FJAR portable launcher

Usage:
  ./start.sh [start] [options]
  ./start.sh doctor [options]   # read-only checks; does not program cards
  ./start.sh status
  ./start.sh logs [--lines N]
  ./start.sh stop [--force]

Start options:
  --wallet ADDRESS       Your FJAR wallet address (required)
  --serials LIST         Comma/space-separated FK33 USB serials
                         (otherwise auto-detected from Linux sysfs)
  --worker-prefix NAME   Pool worker prefix (default: hostname)
  --pool-host HOST       Stratum host (default: stratum.pythonpool.dev)
  --pool-port PORT       Stratum port (default: 3358)
  --base-port PORT       First local hardware port (default: 22000)
  --qualified-650        Select the pinned native 650 MHz image; qualified on
                         one FK33 for 60 minutes, not yet fleet-qualified
  --experimental-550     Select and explicitly acknowledge the unqualified,
                         hardware-unvalidated 550 MHz candidate
  --bitstream FILE       Bitstream path; nonstandard images require the
                         explicit --allow-unverified-bitstream flag
  --allow-card-count-mismatch
                         Continue if PCIe and USB/JTAG counts differ
  --allow-unverified-bitstream
                         Permit an image other than the pinned 525/550/650 builds
  --dry-run              Print the resolved plan without programming cards
  -h, --help             Show this help
  -V, --version          Show version

Optional config.env entries:
  FJAR_WALLET, FJAR_SERIALS, FJAR_WORKER_PREFIX, FJAR_POOL_HOST,
  FJAR_POOL_PORT, FJAR_BASE_PORT, FK33_BITSTREAM,
  FK33_ALLOW_QUALIFIED_650, FK33_ALLOW_EXPERIMENTAL_550

Package layout:
  start.sh
  third_party/sqrl/sqrl_bridge_rawjtag_coe
  runtime/fjar_bridge.py
  hardware/prebuilt/fk33_fjar_bscan_525.bit
  hardware/prebuilt/fk33_native_bscan_650_validated.bit
  hardware/prebuilt/fk33_fjar_bscan_550_experimental.bit
  compat_libs/                         (only when compatibility libraries are needed)

An actual start may use non-interactive sudo to release only the selected
0403:6010 FK33 interfaces from ftdi_sio. Run `sudo -v` first when required.
USAGE
}

is_uint() {
  [[ "$1" =~ ^[0-9]+$ ]]
}

require_value() {
  local option="$1"
  local value="${2:-}"
  [[ -n "$value" ]] || die "$option requires a value"
}

load_config() {
  [[ -f "$CONFIG_FILE" ]] || return 0

  # config.env is shell syntax by design. Refuse files writable by group/other.
  local mode
  mode="$(stat -c '%a' "$CONFIG_FILE" 2>/dev/null || true)"
  if [[ -n "$mode" ]] && (( (8#$mode & 8#022) != 0 )); then
    die "$CONFIG_FILE is group/other writable; run: chmod 600 '$CONFIG_FILE'"
  fi

  # shellcheck disable=SC1090
  source "$CONFIG_FILE"
  WALLET="${FJAR_WALLET:-$WALLET}"
  POOL_HOST="${FJAR_POOL_HOST:-$POOL_HOST}"
  POOL_PORT="${FJAR_POOL_PORT:-$POOL_PORT}"
  BASE_PORT="${FJAR_BASE_PORT:-$BASE_PORT}"
  WORKER_PREFIX="${FJAR_WORKER_PREFIX:-$WORKER_PREFIX}"
  SERIAL_INPUT="${FJAR_SERIALS:-$SERIAL_INPUT}"
  BITSTREAM="${FK33_BITSTREAM:-$BITSTREAM}"
  ALLOW_MISMATCH="${FK33_ALLOW_CARD_COUNT_MISMATCH:-$ALLOW_MISMATCH}"
  ALLOW_QUALIFIED_650="${FK33_ALLOW_QUALIFIED_650:-$ALLOW_QUALIFIED_650}"
  ALLOW_EXPERIMENTAL_550="${FK33_ALLOW_EXPERIMENTAL_550:-$ALLOW_EXPERIMENTAL_550}"
  ALLOW_UNVERIFIED="${FK33_ALLOW_UNVERIFIED_BITSTREAM:-$ALLOW_UNVERIFIED}"
}

parse_args() {
  if [[ $# -gt 0 ]]; then
    case "$1" in
      start|doctor|status|logs|stop) COMMAND="$1"; shift ;;
      -h|--help) usage; exit 0 ;;
      -V|--version) say "$APP_NAME $VERSION"; exit 0 ;;
    esac
  fi

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --wallet) require_value "$1" "${2:-}"; WALLET="$2"; shift 2 ;;
      --serials) require_value "$1" "${2:-}"; SERIAL_INPUT="$2"; shift 2 ;;
      --worker-prefix) require_value "$1" "${2:-}"; WORKER_PREFIX="$2"; shift 2 ;;
      --pool-host) require_value "$1" "${2:-}"; POOL_HOST="$2"; shift 2 ;;
      --pool-port) require_value "$1" "${2:-}"; POOL_PORT="$2"; shift 2 ;;
      --base-port) require_value "$1" "${2:-}"; BASE_PORT="$2"; shift 2 ;;
      --qualified-650)
        BITSTREAM="$QUALIFIED_650_BITSTREAM"
        ALLOW_QUALIFIED_650=1
        shift
        ;;
      --experimental-550)
        BITSTREAM="$EXPERIMENTAL_550_BITSTREAM"
        ALLOW_EXPERIMENTAL_550=1
        shift
        ;;
      --bitstream) require_value "$1" "${2:-}"; BITSTREAM="$2"; shift 2 ;;
      --lines) require_value "$1" "${2:-}"; FK33_LOG_LINES="$2"; shift 2 ;;
      --allow-card-count-mismatch) ALLOW_MISMATCH=1; shift ;;
      --allow-unverified-bitstream) ALLOW_UNVERIFIED=1; shift ;;
      --dry-run) DRY_RUN=1; shift ;;
      --force) FORCE_STOP=1; shift ;;
      -h|--help) usage; exit 0 ;;
      -V|--version) say "$APP_NAME $VERSION"; exit 0 ;;
      *) die "unknown argument: $1 (try --help)" ;;
    esac
  done
}

normalize_serials() {
  local raw="$1"
  local item
  local -A seen=()
  SERIALS=()

  raw="${raw//,/ }"
  while read -r item; do
    [[ -n "$item" ]] || continue
    [[ "$item" =~ ^[[:alnum:]_.:-]+$ ]] || die "invalid FK33 serial: $item"
    if [[ -z "${seen[$item]:-}" ]]; then
      SERIALS+=("$item")
      seen[$item]=1
    fi
  done < <(printf '%s\n' "$raw" | tr '[:space:]' '\n')
}

detect_serials() {
  local path value
  local detected=""

  while IFS= read -r -d '' path; do
    value="$(tr -d '[:space:]' <"$path" 2>/dev/null || true)"
    # Known FK33/SQRL JTAG serials are 12 decimal digits beginning with 1533.
    if [[ "$value" =~ ^1533[0-9]{8}$ ]]; then
      detected+="${detected:+ }$value"
    fi
  # Entries below /sys/bus/usb/devices are symlinks into the sysfs device tree.
  # Follow them or find(1) will report no serial files on normal Linux systems.
  done < <(find -L /sys/bus/usb/devices -maxdepth 3 -type f -name serial -print0 2>/dev/null)

  normalize_serials "$detected"
}

pci_card_count() {
  command -v lspci >/dev/null 2>&1 || { printf 'unknown'; return; }
  lspci -Dnnd 1e24:1533 2>/dev/null | awk 'END { print NR + 0 }'
}

validate_wallet() {
  [[ "$WALLET" =~ ^fjarcode:[[:alnum:]]{20,}$ ]] ||
    die "missing or invalid wallet; use --wallet 'fjarcode:YOUR_ADDRESS'"
}

validate_port() {
  local label="$1" port="$2"
  is_uint "$port" || die "$label must be a number"
  (( port >= 1 && port <= 65535 )) || die "$label must be between 1 and 65535"
}

validate_files() {
  [[ -x "$BRIDGE" ]] || die "missing executable bridge: $BRIDGE"
  [[ -r "$MINER" ]] || die "missing miner runtime: $MINER"
  [[ -r "$BITSTREAM" ]] || die "missing bitstream: $BITSTREAM"
  command -v python3 >/dev/null 2>&1 || die "python3 is required"
  command -v sha256sum >/dev/null 2>&1 || die "sha256sum is required"
  command -v flock >/dev/null 2>&1 || die "flock (util-linux) is required"
  command -v nohup >/dev/null 2>&1 || die "nohup (coreutils) is required"
  command -v ldd >/dev/null 2>&1 || die "ldd is required"

  local actual_sha
  actual_sha="$(sha256sum "$BITSTREAM" | awk '{print $1}')"
  case "$actual_sha" in
    "$STABLE_BIT_SHA256")
      BITSTREAM_MODE="pinned 525 MHz fleet-tested image"
      ;;
    "$QUALIFIED_650_BIT_SHA256")
      if [[ "$ALLOW_QUALIFIED_650" != 1 ]]; then
        die "the pinned 650 MHz image is one-card qualified; select it with --qualified-650"
      fi
      BITSTREAM_MODE="pinned native 650 MHz one-card-qualified image"
      warn "650 MHz passed a 60-minute one-card soak; this host remains a staged fleet deployment"
      ;;
    "$EXPERIMENTAL_550_BIT_SHA256")
      if [[ "$ALLOW_EXPERIMENTAL_550" != 1 ]]; then
        die "the pinned 550 MHz image is hardware-unvalidated; select it with --experimental-550"
      fi
      BITSTREAM_MODE="pinned 550 MHz experimental image"
      warn "550 MHz has no included positive timing signoff or physical FK33 validation"
      ;;
    *)
      if [[ "$ALLOW_UNVERIFIED" == 1 ]]; then
        BITSTREAM_MODE="unverified image override ($actual_sha)"
        warn "unverified bitstream explicitly allowed: $actual_sha"
      else
        die "bitstream SHA-256 is not a pinned FK33 FJAR image: $actual_sha"
      fi
      ;;
  esac

  if [[ -f "$SCRIPT_DIR/SHA256SUMS" ]]; then
    (cd "$SCRIPT_DIR" && sha256sum --quiet -c SHA256SUMS) ||
      die "package checksum verification failed"
  fi

  local missing_libs
  missing_libs="$(LD_LIBRARY_PATH="$LIB_DIR${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}" ldd "$BRIDGE" 2>/dev/null | awk '/not found/ {print $1}' | paste -sd, -)"
  [[ -z "$missing_libs" ]] || die "bridge libraries missing: $missing_libs"
}

check_ports_free() {
  local count="$1"
  python3 - "$BASE_PORT" "$count" <<'PY'
import socket
import sys

base = int(sys.argv[1])
count = int(sys.argv[2])
busy = []
for port in range(base, base + count):
    sock = socket.socket()
    try:
        sock.bind(("127.0.0.1", port))
    except OSError:
        busy.append(str(port))
    finally:
        sock.close()
if busy:
    print("busy local port(s): " + ", ".join(busy), file=sys.stderr)
    raise SystemExit(1)
PY
}

check_card_count() {
  local pci_count
  pci_count="$(pci_card_count)"
  if [[ "$pci_count" == unknown ]]; then
    warn "lspci is unavailable; PCIe card-count cross-check skipped"
    return 0
  fi
  if (( pci_count != ${#SERIALS[@]} )); then
    if [[ "$ALLOW_MISMATCH" == 1 ]]; then
      warn "PCIe FK33 count ($pci_count) differs from USB/JTAG serial count (${#SERIALS[@]})"
    else
      die "PCIe FK33 count ($pci_count) differs from USB/JTAG serial count (${#SERIALS[@]}); inspect cabling or use --allow-card-count-mismatch after verifying the list"
    fi
  fi
}

resolve_serials() {
  if [[ -n "$SERIAL_INPUT" ]]; then
    normalize_serials "$SERIAL_INPUT"
  else
    detect_serials
  fi
  (( ${#SERIALS[@]} > 0 )) ||
    die "no FK33 USB/JTAG serials found; use --serials SERIAL1,SERIAL2,..."
}

usb_device_for_serial() {
  local serial="$1"
  local -a matches=()
  mapfile -t matches < <(
    grep -l -x -- "$serial" /sys/bus/usb/devices/*/serial 2>/dev/null || true
  )
  ((${#matches[@]} == 1)) ||
    die "FK33 serial $serial has ${#matches[@]} matching USB devices"
  printf '%s\n' "${matches[0]%/serial}"
}

check_usb_devices() {
  local serial usb_dev usb_node interface driver
  local busnum devnum bound=0

  for serial in "${SERIALS[@]}"; do
    usb_dev="$(usb_device_for_serial "$serial")"
    [[ "$(<"$usb_dev/idVendor")" == 0403 &&
       "$(<"$usb_dev/idProduct")" == 6010 ]] ||
      die "serial $serial is not an FK33-compatible 0403:6010 USB/JTAG device"

    busnum="$(<"$usb_dev/busnum")"
    devnum="$(<"$usb_dev/devnum")"
    printf -v usb_node '/dev/bus/usb/%03d/%03d' "$busnum" "$devnum"
    [[ -r "$usb_node" && -w "$usb_node" ]] ||
      die "no user read/write access to $usb_node for FK33 serial $serial; install the repository's serial-specific udev rule"

    for interface in "$usb_dev":1.*; do
      [[ -d "$interface" ]] || continue
      driver=unbound
      if [[ -L "$interface/driver" ]]; then
        driver="$(basename "$(readlink -f "$interface/driver")")"
      fi
      case "$driver" in
        unbound) ;;
        ftdi_sio) bound=$((bound + 1)) ;;
        *) die "$(basename "$interface") uses unexpected driver $driver" ;;
      esac
    done
  done

  if ((bound > 0)); then
    warn "$bound selected FK33 interface(s) are bound to ftdi_sio; start will release them with sudo -n"
  fi
}

prepare_usb_devices() {
  local serial usb_dev interface driver interface_name

  for serial in "${SERIALS[@]}"; do
    usb_dev="$(usb_device_for_serial "$serial")"
    for interface in "$usb_dev":1.*; do
      [[ -d "$interface" ]] || continue
      driver=unbound
      if [[ -L "$interface/driver" ]]; then
        driver="$(basename "$(readlink -f "$interface/driver")")"
      fi
      case "$driver" in
        unbound)
          ;;
        ftdi_sio)
          command -v sudo >/dev/null 2>&1 ||
            die "sudo is required to release ftdi_sio for serial $serial"
          interface_name="$(basename "$interface")"
          printf '%s\n' "$interface_name" |
            sudo -n tee /sys/bus/usb/drivers/ftdi_sio/unbind >/dev/null ||
            die "could not release $interface_name; run sudo -v and retry"
          ;;
        *)
          die "$(basename "$interface") uses unexpected driver $driver"
          ;;
      esac
    done
  done

  sleep 1
  for serial in "${SERIALS[@]}"; do
    usb_dev="$(usb_device_for_serial "$serial")"
    for interface in "$usb_dev":1.*; do
      [[ -d "$interface" ]] || continue
      [[ ! -L "$interface/driver" ]] ||
        die "$(basename "$interface") remains bound to $(basename "$(readlink -f "$interface/driver")")"
    done
  done
}

ensure_not_root() {
  if (( EUID == 0 )); then
    if [[ "$COMMAND" == doctor || "$DRY_RUN" == 1 ]]; then
      warn "running a read-only check as root; an actual start will require an unprivileged user"
      return 0
    fi
    die "do not run this launcher as root; grant your user access to the FK33 USB/JTAG devices instead"
  fi
}

show_plan() {
  local i port
  say "===== FK33 FJAR START PLAN ====="
  say "launcher:       $VERSION"
  say "cards:          ${#SERIALS[@]}"
  say "pool:           $POOL_HOST:$POOL_PORT"
  say "worker prefix:  $WORKER_PREFIX"
  say "bitstream:      $BITSTREAM"
  say "bitstream mode: $BITSTREAM_MODE"
  say "state/logs:     $STATE_DIR"
  say "bridge cwd:     $STATE_DIR"
  say "USB/JTAG:       selected 0403:6010 devices only"
  say "voltage:        unchanged"
  say
  for i in "${!SERIALS[@]}"; do
    port=$((BASE_PORT + i))
    printf '  card %02d  serial=%s  local_port=%d  worker=%s-%s\n' \
      "$((i + 1))" "${SERIALS[$i]}" "$port" "$WORKER_PREFIX" "${SERIALS[$i]: -4}"
  done
}

pid_matches() {
  local pid="$1" needle="$2"
  is_uint "$pid" || return 1
  kill -0 "$pid" 2>/dev/null || return 1
  ps -p "$pid" -o args= 2>/dev/null | grep -F -- "$needle" >/dev/null
}

read_pid() {
  local file="$1"
  if [[ -r "$file" ]]; then
    tr -dc '0-9' <"$file"
  fi
  return 0
}

already_running() {
  local pid
  pid="$(read_pid "$STATE_DIR/pids/bridge.pid")"
  [[ -n "$pid" ]] && pid_matches "$pid" "$BRIDGE"
}

wait_for_ports() {
  local count="$1"
  python3 - "$BASE_PORT" "$count" <<'PY'
import socket
import sys
import time

base = int(sys.argv[1])
count = int(sys.argv[2])
deadline = time.monotonic() + 45
pending = set(range(base, base + count))
while pending and time.monotonic() < deadline:
    for port in tuple(pending):
        sock = socket.socket()
        try:
            # The ports were confirmed free immediately before launch.  Once a
            # bind fails, the bridge owns the port; no probe connection is made.
            sock.bind(("127.0.0.1", port))
        except OSError:
            pending.remove(port)
        finally:
            sock.close()
    if pending:
        time.sleep(0.5)
if pending:
    print("bridge did not open port(s): " + ", ".join(map(str, sorted(pending))), file=sys.stderr)
    raise SystemExit(1)
PY
}

rollback_start() {
  local pid
  warn "start failed; stopping only the processes launched by this attempt"
  for pid in "${STARTED_WORKER_PIDS[@]:-}"; do
    [[ -n "$pid" ]] && kill -TERM "$pid" 2>/dev/null || true
  done
  [[ -n "$STARTED_BRIDGE_PID" ]] && kill -TERM "$STARTED_BRIDGE_PID" 2>/dev/null || true
}

start_fleet() {
  ensure_not_root
  validate_wallet
  validate_port "pool port" "$POOL_PORT"
  validate_port "base port" "$BASE_PORT"
  resolve_serials
  (( BASE_PORT + ${#SERIALS[@]} - 1 <= 65535 )) || die "card ports exceed 65535"
  validate_files
  check_card_count
  check_usb_devices
  show_plan

  if (( DRY_RUN == 1 )); then
    say
    say "DRY RUN: no FPGA, process, pool connection, or voltage state was changed."
    return 0
  fi

  mkdir -p "$STATE_DIR/pids" "$STATE_DIR/logs"
  exec 9>"$STATE_DIR/launcher.lock"
  flock -n 9 || die "another launcher operation is in progress"
  already_running && die "fleet bridge is already running; use './start.sh status'"
  check_ports_free "${#SERIALS[@]}"
  prepare_usb_devices

  local serial_csv serial port worker pid
  serial_csv="$(IFS=,; printf '%s' "${SERIALS[*]}")"
  trap rollback_start ERR INT TERM

  info "programming ${#SERIALS[@]} card(s) and starting the local bridge"
  (
    # The legacy bridge creates ./virtual_ports without checking fopen().
    # Run it from writable state storage, never from a read-only release tree.
    cd "$STATE_DIR"
    exec env LD_LIBRARY_PATH="$LIB_DIR${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}" \
      nohup "$BRIDGE" \
        -s ",$serial_csv" \
        -b "$BITSTREAM" \
        -p "$BASE_PORT" \
        -t \
        -f "$STATE_DIR/logs/sqrl.log"
  ) 9>&- >>"$STATE_DIR/logs/sqrl-console.log" 2>&1 &
  STARTED_BRIDGE_PID=$!
  printf '%s\n' "$STARTED_BRIDGE_PID" >"$STATE_DIR/pids/bridge.pid"

  wait_for_ports "${#SERIALS[@]}"
  pid_matches "$STARTED_BRIDGE_PID" "$BRIDGE" || die "bridge exited during startup; inspect $STATE_DIR/logs/sqrl-console.log"

  : >"$STATE_DIR/fleet.tsv"
  for serial in "${SERIALS[@]}"; do
    port=$((BASE_PORT + ${#STARTED_WORKER_PIDS[@]}))
    worker="$WORKER_PREFIX-${serial: -4}"
    info "starting worker $worker on local port $port"
    FJAR_SERIAL="$serial" \
    FJAR_WORKER="$worker" \
    FJAR_WALLET="$WALLET" \
    FJAR_POOL_HOST="$POOL_HOST" \
    FJAR_POOL_PORT="$POOL_PORT" \
    FJAR_HW_HOST="127.0.0.1" \
    FJAR_HW_PORT="$port" \
      nohup python3 -u "$MINER" 9>&- \
        >>"$STATE_DIR/logs/worker-$serial.log" 2>&1 &
    pid=$!
    STARTED_WORKER_PIDS+=("$pid")
    printf '%s\n' "$pid" >"$STATE_DIR/pids/worker-$serial.pid"
    printf '%s\t%s\t%s\n' "$serial" "$port" "$worker" >>"$STATE_DIR/fleet.tsv"
  done

  sleep 2
  pid_matches "$STARTED_BRIDGE_PID" "$BRIDGE" ||
    die "bridge exited after worker launch; inspect $STATE_DIR/logs/sqrl-console.log"
  for pid in "${STARTED_WORKER_PIDS[@]}"; do
    pid_matches "$pid" "$MINER" || die "a worker exited during startup; inspect $STATE_DIR/logs"
  done

  trap - ERR INT TERM
  STARTED_BRIDGE_PID=""
  STARTED_WORKER_PIDS=()
  say
  say "PASS: ${#SERIALS[@]} FK33 worker(s) started."
  say "Run: ./start.sh status"
  say "Logs: ./start.sh logs"
}

doctor() {
  ensure_not_root
  validate_port "pool port" "$POOL_PORT"
  validate_port "base port" "$BASE_PORT"
  resolve_serials
  validate_files
  check_card_count
  check_usb_devices
  show_plan
  say
  say "PASS: read-only preflight completed. No FPGA, process, pool, or voltage state was changed."
}

status_fleet() {
  local bridge_pid serial port worker pid state="stopped" active=0 total=0
  bridge_pid="$(read_pid "$STATE_DIR/pids/bridge.pid")"
  if [[ -n "$bridge_pid" ]] && pid_matches "$bridge_pid" "$BRIDGE"; then
    state="running (pid $bridge_pid)"
  elif [[ -n "$bridge_pid" ]]; then
    state="stale pid file ($bridge_pid)"
  fi

  say "bridge: $state"
  if [[ -r "$STATE_DIR/fleet.tsv" ]]; then
    while IFS=$'\t' read -r serial port worker; do
      [[ -n "$serial" ]] || continue
      total=$((total + 1))
      pid="$(read_pid "$STATE_DIR/pids/worker-$serial.pid")"
      if [[ -n "$pid" ]] && pid_matches "$pid" "$MINER"; then
        active=$((active + 1))
        printf 'worker: running  serial=%s port=%s name=%s pid=%s\n' "$serial" "$port" "$worker" "$pid"
      else
        printf 'worker: stopped  serial=%s port=%s name=%s\n' "$serial" "$port" "$worker"
      fi
    done <"$STATE_DIR/fleet.tsv"
  fi
  say "workers: $active/$total running"
  [[ "$state" == running* && "$active" -eq "$total" && "$total" -gt 0 ]]
}

stop_pid() {
  local pid="$1" needle="$2" label="$3"
  if ! pid_matches "$pid" "$needle"; then
    warn "$label pid $pid is not a matching live process; it will not be signaled"
    return 0
  fi
  kill -TERM "$pid"
  local i
  for ((i=0; i<30; i++)); do
    kill -0 "$pid" 2>/dev/null || return 0
    sleep 0.5
  done
  if (( FORCE_STOP == 1 )); then
    warn "$label did not stop after 15 seconds; sending KILL because --force was supplied"
    kill -KILL "$pid" 2>/dev/null || true
  else
    warn "$label is still running; rerun './start.sh stop --force' only after checking it"
    return 1
  fi
}

stop_fleet() {
  local file pid serial failed=0
  [[ -d "$STATE_DIR/pids" ]] || { say "nothing to stop"; return 0; }
  exec 9>"$STATE_DIR/launcher.lock"
  flock -n 9 || die "another launcher operation is in progress"

  while IFS= read -r -d '' file; do
    serial="${file##*/worker-}"
    serial="${serial%.pid}"
    pid="$(read_pid "$file")"
    if [[ -n "$pid" ]] && ! stop_pid "$pid" "$MINER" "worker $serial"; then
      failed=1
    fi
  done < <(find "$STATE_DIR/pids" -maxdepth 1 -type f -name 'worker-*.pid' -print0 2>/dev/null)

  pid="$(read_pid "$STATE_DIR/pids/bridge.pid")"
  if [[ -n "$pid" ]] && ! stop_pid "$pid" "$BRIDGE" "fleet bridge"; then
    failed=1
  fi

  if (( failed == 0 )); then
    find "$STATE_DIR/pids" -maxdepth 1 -type f -name '*.pid' -delete 2>/dev/null || true
    say "PASS: FK33 FJAR processes stopped. FPGA voltage was not changed."
  else
    die "one or more processes did not stop cleanly"
  fi
}

show_logs() {
  local lines="${FK33_LOG_LINES:-80}"
  is_uint "$lines" || die "--lines must be a number"
  [[ -d "$STATE_DIR/logs" ]] || die "no logs found in $STATE_DIR/logs"
  local file
  while IFS= read -r -d '' file; do
    say
    say "===== ${file##*/} ====="
    tail -n "$lines" "$file"
  done < <(find "$STATE_DIR/logs" -maxdepth 1 -type f -name '*.log' -print0 | sort -z)
}

main() {
  load_config
  parse_args "$@"
  case "$COMMAND" in
    start) start_fleet ;;
    doctor) doctor ;;
    status) status_fleet ;;
    logs) show_logs ;;
    stop) stop_fleet ;;
    *) die "internal error: unsupported command $COMMAND" ;;
  esac
}

main "$@"

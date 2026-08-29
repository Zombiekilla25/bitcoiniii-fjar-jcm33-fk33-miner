#!/usr/bin/env bash
set -Eeuo pipefail

CANARY_VERSION=0.35.0-650-canary1
SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)
CARRIER=${JCM33_CARRIER:-192.168.1.222}
BASE_PORT=${JCM33_BASE_PORT:-2000}
XVC_PORT=${JCM33_XVC_PORT:-2542}
LIB_DIR=${JCM33_LIB_DIR:-"$HOME/jc33_compat_libs"}
BRIDGE_LD_LIBRARY_PATH="${LD_LIBRARY_PATH:-}"
POOL_HOST=${BTC3_POOL_HOST:-stratum.pythonpool.dev}
POOL_PORT=${BTC3_POOL_PORT:-3357}
WORKER=${BTC3_WORKER:-"$(hostname -s 2>/dev/null || echo jcm33)-dual"}
MINUTES=15
WALLET=""
BUILD_ONLY=0

BRIDGE="$SCRIPT_DIR/sqrl_bridge_rawjtag_coe_jcm33_xvc"
BUILD_TCL="$SCRIPT_DIR/build_jcm33_dualalign_bscan_650.tcl"
BUILD_LOG="$SCRIPT_DIR/build-jcm33-dualalign-650.log"
BITSTREAM="$SCRIPT_DIR/../../hardware/prebuilt/jcm33_bitcoiniii_dualalign_650_validated.bit"
RESTORE_BITSTREAM="$SCRIPT_DIR/qualified_587p5/jcm33_dualalign_bscan_587p5.bit"
MINER="$SCRIPT_DIR/jcm33_btc3_dual_miner.py"
TESTS="$SCRIPT_DIR/test_jcm33_dualalign_btc3_650_canary.py"

EXPECTED_BRIDGE_SHA=fd1a550af5eb5dab475071a8f08f181c0b0d308233cbca805c52e3a96f342141
EXPECTED_RESTORE_SHA=2abff6fc716bdea86d7c88865e07dcd380a89564f9267654910b5931a3f2f85b
EXPECTED_BITSTREAM_SHA=0eacb71eb4cb5f6a43f761d1af64dfe25c8fa22177974082742dc12d6f6cdcf1
EXPECTED_DCP_SHA=31a1b1888f50c3f03b229955b7d2575cfb5c621a942eeddb77739970dcb55c73

RUN_DIR="${TMPDIR:-/tmp}/jcm33-btc3-dual-650-canary-$(date -u +%Y%m%dT%H%M%SZ)-$$"
EVIDENCE_ARCHIVE="$SCRIPT_DIR/$(basename "$RUN_DIR").tar.gz"
ACTIVE_PID=""
IMAGE_PROGRAMMED=0
CANDIDATE_PROGRAM_ATTEMPTED=0
ROLLBACK_RESULT=not-needed
PHASE=preflight

usage() {
    cat <<'USAGE'
JCM33 chain-alignment-fixed dual-FPGA BitcoinIII canary

Usage:
  ./run_jcm33_dualalign_btc3_650_canary.sh --wallet bc1q... [options]

Options:
  --wallet ADDRESS       BitcoinIII bc1q address (required)
  --minutes N            Canary duration, 1-60 minutes (default: 15)
  --worker NAME          Pool worker name
  --pool-host HOST       Default: stratum.pythonpool.dev
  --pool-port PORT       Default: 3357
  --build-only           Verify the audited image and exit without hardware
  -h, --help             Show this help

The canary uses the checksum-pinned 650 MHz image from the completed exhaustive
route search. It programs both chain-aligned FPGAs only after setup and hold
timing pass, then requires accepted pool shares from A and B with no digest
mismatch. It never changes voltage. A failed or interrupted hardware canary
automatically restores the included hardware-qualified 587.5 MHz image.
USAGE
}

die() {
    echo "[ERROR] $*" >&2
    exit 1
}

require_value() {
    [ -n "${2:-}" ] || die "$1 requires a value"
}

while [ "$#" -gt 0 ]; do
    case "$1" in
        --wallet) require_value "$1" "${2:-}"; WALLET=$2; shift 2 ;;
        --minutes) require_value "$1" "${2:-}"; MINUTES=$2; shift 2 ;;
        --worker) require_value "$1" "${2:-}"; WORKER=$2; shift 2 ;;
        --pool-host) require_value "$1" "${2:-}"; POOL_HOST=$2; shift 2 ;;
        --pool-port) require_value "$1" "${2:-}"; POOL_PORT=$2; shift 2 ;;
        --vivado|--rebuild) die "$1 is disabled for this checksum-pinned audited image" ;;
        --build-only) BUILD_ONLY=1; shift ;;
        -h|--help) usage; exit 0 ;;
        *) die "unknown argument: $1" ;;
    esac
done

sha_of() {
    sha256sum -- "$1" | awk '{print $1}'
}

require_sha() {
    local file=$1 expected=$2 label=$3 actual
    [ -f "$file" ] || die "$label is missing: $file"
    actual=$(sha_of "$file")
    [ "$actual" = "$expected" ] ||
        die "$label checksum mismatch: expected=$expected actual=$actual"
    echo "PASS: $label checksum $actual"
}

build_image() {
    local bitstream_size bitstream_sha
    local timing_stamp="$SCRIPT_DIR/reports/timing-gate.pass"

    [ -f "$BITSTREAM" ] || die "published bitstream is missing: $BITSTREAM"
    [ -f "$timing_stamp" ] || die "timing-gate marker is missing; do not program this image"
    grep -qx 'TIMING GATE PASS' "$timing_stamp" ||
        die "timing-gate marker is invalid; do not program this image"
    echo "INFO: using the completed, independently audited 650 MHz build"

    [ -f "$BITSTREAM" ] || die "built bitstream is missing: $BITSTREAM"
    require_sha "$BITSTREAM" "$EXPECTED_BITSTREAM_SHA" \
        "timing-audited 650 MHz bitstream"
    grep -Fq "$EXPECTED_DCP_SHA" "$SCRIPT_DIR/VALIDATION.md" ||
        die "published routed-checkpoint identity is missing"
    bitstream_size=$(stat -c '%s' "$BITSTREAM")
    (( bitstream_size > 28000000 )) ||
        die "built bitstream is unexpectedly small: $bitstream_size bytes"
    bitstream_sha=$(sha_of "$BITSTREAM")
    echo "PASS: dual-alignment bitstream size=$bitstream_size sha256=$bitstream_sha"
    if [ -f "$BUILD_LOG" ]; then
        grep -E '^FINAL (SETUP WNS|HOLD  WHS):' "$BUILD_LOG" || true
    fi
    {
        echo "bitstream_size=$bitstream_size"
        echo "bitstream_sha256=$bitstream_sha"
    } >"$RUN_DIR/bitstream-identity.txt"
    [ ! -f "$BUILD_LOG" ] || cp -- "$BUILD_LOG" "$RUN_DIR/vivado-build.log"
}

wait_for_carrier() {
    local attempt
    for attempt in {1..12}; do
        if ping -c 1 -W 1 "$CARRIER" >/dev/null 2>&1; then
            echo "PASS: carrier reachable on attempt $attempt"
            return 0
        fi
        echo "Waiting for carrier: attempt $attempt/12"
        sleep 5
    done
    return 1
}

stop_pid() {
    local pid=${1:-}
    [ -n "$pid" ] || return 0
    if kill -0 "$pid" 2>/dev/null; then
        kill -TERM "$pid" 2>/dev/null || true
        for _ in {1..50}; do
            kill -0 "$pid" 2>/dev/null || break
            sleep 0.1
        done
        kill -0 "$pid" 2>/dev/null && kill -KILL "$pid" 2>/dev/null || true
    fi
    wait "$pid" 2>/dev/null || true
}

wait_for_loads() {
    local log=$1 pid=$2 label=$3 deadline
    deadline=$((SECONDS + 120))
    while (( SECONDS < deadline )); do
        if [ -f "$log" ] &&
           grep -q 'SQRL JTAG Board 0 Device 0 Bitstream Loaded' "$log" &&
           grep -q 'SQRL JTAG Board 0 Device 1 Bitstream Loaded' "$log"; then
            echo "PASS: $label loaded on both JCM33 devices"
            return 0
        fi
        if ! kill -0 "$pid" 2>/dev/null; then
            echo "[ERROR] programming bridge exited before both devices loaded" >&2
            tail -180 "$log" 2>/dev/null || true
            return 1
        fi
        sleep 1
    done
    echo "[ERROR] timed out loading the production image" >&2
    tail -180 "$log" 2>/dev/null || true
    return 1
}

launch_program_bridge() {
    local image=$1 log_prefix=$2
    LD_LIBRARY_PATH="$BRIDGE_LD_LIBRARY_PATH" \
        "$BRIDGE" -c "$CARRIER" -b "$image" -p "$BASE_PORT" -t \
        -f "$RUN_DIR/$log_prefix-bridge.log" \
        >"$RUN_DIR/$log_prefix-stdout.log" 2>&1 &
    ACTIVE_PID=$!
}

restore_qualified_587p5() {
    PHASE=rollback-qualified-587p5
    echo
    echo "===== RESTORING HARDWARE-QUALIFIED 587.5 MHz IMAGE ====="
    if ! wait_for_carrier; then
        echo "[ERROR] carrier is unreachable; automatic 587.5 MHz rollback could not start" >&2
        return 1
    fi
    launch_program_bridge "$RESTORE_BITSTREAM" restore-587p5
    if wait_for_loads \
        "$RUN_DIR/restore-587p5-bridge.log" \
        "$ACTIVE_PID" \
        "qualified 587.5 MHz rollback image"; then
        stop_pid "$ACTIVE_PID"
        ACTIVE_PID=""
        IMAGE_PROGRAMMED=0
        echo "ROLLBACK PASS: both JCM33 FPGAs restored to qualified 587.5 MHz"
        return 0
    fi
    stop_pid "$ACTIVE_PID"
    ACTIVE_PID=""
    echo "ROLLBACK FAIL: verify both JCM33 FPGA images before mining" >&2
    return 1
}

launch_xvc_bridge() {
    local deadline
    LD_LIBRARY_PATH="$BRIDGE_LD_LIBRARY_PATH" \
        "$BRIDGE" -c "$CARRIER" -p "$BASE_PORT" -j "$XVC_PORT" -t \
        -f "$RUN_DIR/xvc-bridge.log" >"$RUN_DIR/xvc-stdout.log" 2>&1 &
    ACTIVE_PID=$!
    deadline=$((SECONDS + 30))
    while (( SECONDS < deadline )); do
        if ss -ltnH | awk '{print $4}' | grep -Eq "(^|:)$XVC_PORT$"; then
            echo "PASS: XVC endpoint is listening on 127.0.0.1:$XVC_PORT"
            return 0
        fi
        kill -0 "$ACTIVE_PID" 2>/dev/null || {
            tail -180 "$RUN_DIR/xvc-bridge.log" 2>/dev/null || true
            return 1
        }
        sleep 1
    done
    return 1
}

cleanup() {
    local status=$1
    trap - EXIT
    trap '' INT TERM
    stop_pid "$ACTIVE_PID"
    ACTIVE_PID=""

    if [ "$status" -ne 0 ] && [ "$CANDIDATE_PROGRAM_ATTEMPTED" -eq 1 ]; then
        if restore_qualified_587p5; then
            ROLLBACK_RESULT=pass
        else
            ROLLBACK_RESULT=fail
        fi
    fi

    if [ -f "$RUN_DIR/miner.log" ]; then
        local accepted_a accepted_b rejected mismatches
        accepted_a=$(grep -c 'ACCEPTED.*device=A' "$RUN_DIR/miner.log" || true)
        accepted_b=$(grep -c 'ACCEPTED.*device=B' "$RUN_DIR/miner.log" || true)
        rejected=$(grep -c 'REJECTED' "$RUN_DIR/miner.log" || true)
        mismatches=$(grep -c 'SHARE mismatch' "$RUN_DIR/miner.log" || true)
        {
            echo "accepted_A=$accepted_a"
            echo "accepted_B=$accepted_b"
            echo "rejected=$rejected"
            echo "hardware_software_mismatches=$mismatches"
            echo "rollback_587p5=$ROLLBACK_RESULT"
        } | tee "$RUN_DIR/canary-summary.txt"
    fi
    if [ -f "$RUN_DIR/xvc-bridge.log" ]; then
        echo "===== 650 MHz TELEMETRY EXCERPT ====="
        grep -E 'Telemetry:|Temp:|VCCINT|VCCAUX|VCCBRAM' \
            "$RUN_DIR/xvc-bridge.log" | tail -40 || true
    fi
    [ ! -f "$BUILD_LOG" ] || cp -- "$BUILD_LOG" "$RUN_DIR/vivado-build.log"
    [ ! -f "$SCRIPT_DIR/output/route-sweep-summary.tsv" ] || \
        cp -- "$SCRIPT_DIR/output/route-sweep-summary.tsv" \
            "$RUN_DIR/route-sweep-summary.tsv"
    if tar -C "$(dirname "$RUN_DIR")" -czf "$EVIDENCE_ARCHIVE" \
        "$(basename "$RUN_DIR")"; then
        echo "Evidence archive:   $EVIDENCE_ARCHIVE"
    else
        echo "[WARN] could not create evidence archive" >&2
    fi
    echo "Evidence directory: $RUN_DIR"
    if [ "$ROLLBACK_RESULT" = pass ]; then
        echo "INFO: both JCM33 FPGAs are restored to hardware-qualified 587.5 MHz"
    elif [ "$ROLLBACK_RESULT" = fail ]; then
        echo "[ERROR] automatic 587.5 MHz rollback failed; do not resume mining until image state is verified" >&2
    elif [ "$IMAGE_PROGRAMMED" -eq 1 ]; then
        echo "INFO: dual-alignment 650 MHz production image left resident"
    else
        echo "INFO: resident FPGA images were unchanged"
    fi
    echo "INFO: no voltage command or 350 MHz image is used by this package"
    if [ "$status" -eq 0 ] && [ "$BUILD_ONLY" -eq 1 ]; then
        echo "650 IMAGE VERIFY PASS: audited image is intact; no FPGA was programmed"
    elif [ "$status" -eq 0 ]; then
        echo "650 CANARY PASS: both JCM33 FPGAs produced accepted BitcoinIII shares without digest mismatches"
    else
        echo "CANARY FAIL during phase=$PHASE; send back the evidence archive" >&2
    fi
    exit "$status"
}

trap 'cleanup $?' EXIT
trap 'exit 130' INT TERM

if [ "$BUILD_ONLY" -eq 0 ]; then
    [[ "$WALLET" =~ ^bc1q[023456789acdefghjklmnpqrstuvwxyz]{20,86}$ ]] ||
        die "--wallet must be a lowercase BitcoinIII bc1q address"
fi
[[ "$MINUTES" =~ ^[0-9]+$ ]] || die "--minutes must be an integer"
(( MINUTES >= 1 && MINUTES <= 60 )) || die "--minutes must be between 1 and 60"
[[ "$POOL_PORT" =~ ^[0-9]+$ ]] || die "--pool-port must be an integer"
(( POOL_PORT >= 1 && POOL_PORT <= 65535 )) || die "--pool-port is out of range"
[[ "$WORKER" =~ ^[A-Za-z0-9_-]{1,64}$ ]] || die "invalid worker name"

mkdir -p -- "$RUN_DIR"
chmod +x -- "$BRIDGE" "$MINER" "$TESTS"

echo "===== JCM33 DUAL-ALIGNMENT 650 MHz BITCOINIII CANARY ====="
echo "version:          $CANARY_VERSION"
echo "carrier:          $CARRIER"
echo "XVC port:         $XVC_PORT"
echo "pool:             $POOL_HOST:$POOL_PORT"
echo "wallet:           $WALLET"
echo "worker:           $WORKER"
echo "duration:         $MINUTES minute(s)"
echo "bitstream:        $BITSTREAM"
echo "rollback image:   $RESTORE_BITSTREAM"
echo "transport fix:    auto-select low/high byte from each nine-bit USER2 word"
echo "expected gain:    10.64% over 587.5 MHz; 18.18% over 550 MHz"
echo "build strategy:   exhaustive supported performance-route sweep"
echo "dispatch:         independent A-tailpad then B-tailpad in one XVC request"
echo "share reads:      independent USER1 lanes A and B"
echo "external fee:     0%"
echo "restore action:   qualified 587.5 MHz on failed/interrupted hardware canary"
echo "voltage:          unchanged (no -v/-V option is used)"
echo "build only:       $BUILD_ONLY"
echo "evidence:         $RUN_DIR"
echo

for command in python3 sha256sum tar ping pgrep ss grep tail timeout ldd stat cp tr; do
    command -v "$command" >/dev/null || die "$command is required"
done
if [ -d "$LIB_DIR" ]; then
    BRIDGE_LD_LIBRARY_PATH="$LIB_DIR${BRIDGE_LD_LIBRARY_PATH:+:$BRIDGE_LD_LIBRARY_PATH}"
    echo "INFO: optional compatibility directory enabled: $LIB_DIR"
else
    echo "INFO: optional compatibility directory absent; checking system libraries"
fi
require_sha "$BRIDGE" "$EXPECTED_BRIDGE_SHA" "XVC bridge"
require_sha "$RESTORE_BITSTREAM" "$EXPECTED_RESTORE_SHA" "qualified 587.5 MHz rollback image"
(cd "$SCRIPT_DIR" && sha256sum -c SHA256SUMS)
if LD_LIBRARY_PATH="$BRIDGE_LD_LIBRARY_PATH" \
    ldd "$BRIDGE" | tee "$RUN_DIR/bridge-ldd.txt" | grep -q 'not found'; then
    die "XVC bridge still has unresolved libraries"
fi
echo "PASS: XVC bridge libraries resolved"
JCM33_SELF_TEST=1 python3 "$MINER"
(cd "$SCRIPT_DIR" && python3 -m unittest -v "$(basename "$TESTS")")

build_image

if [ "$BUILD_ONLY" -eq 1 ]; then
    PHASE=complete
    exit 0
fi

if existing=$(
    pgrep -af '[s]qrl_bridge' 2>/dev/null |
    grep -F -- "-c $CARRIER" || true
); [ -n "$existing" ]; then
    echo "$existing" >&2
    die "a bridge targeting JCM33 carrier $CARRIER is already running"
fi
echo "PASS: no bridge currently targets JCM33 carrier $CARRIER"
echo "INFO: unrelated USB/FK bridge processes are allowed when JCM33 ports are free"

wait_for_carrier || die "carrier $CARRIER remained unreachable for 60 seconds"

python3 - "$POOL_HOST" "$POOL_PORT" <<'PY' || die "pool is not reachable"
import socket
import sys
with socket.create_connection((sys.argv[1], int(sys.argv[2])), timeout=5):
    pass
PY
echo "PASS: BitcoinIII pool is reachable"

for port in "$BASE_PORT" "$((BASE_PORT + 1))" "$XVC_PORT"; do
    if ss -ltnH | awk '{print $4}' | grep -Eq "(^|:)$port$"; then
        die "local TCP port $port is already listening"
    fi
done

# The build can take several hours; require the carrier immediately
# before programming in case it rebooted or briefly dropped off the network.
wait_for_carrier || die "carrier $CARRIER remained unreachable after the build"

PHASE=program-production
echo
echo "===== PROGRAMMING PRODUCTION 650 MHz IMAGE ====="
CANDIDATE_PROGRAM_ATTEMPTED=1
launch_program_bridge "$BITSTREAM" program-650
wait_for_loads \
    "$RUN_DIR/program-650-bridge.log" \
    "$ACTIVE_PID" \
    "production 650 MHz image"
IMAGE_PROGRAMMED=1
stop_pid "$ACTIVE_PID"
ACTIVE_PID=""
sleep 2

PHASE=start-xvc
echo
echo "===== STARTING XVC TRANSPORT ====="
launch_xvc_bridge || die "XVC bridge did not become ready"

PHASE=live-mining
echo
echo "===== LIVE BITCOINIII DUAL-FPGA CANARY ====="
set +e
timeout --foreground --signal=INT --kill-after=10s "${MINUTES}m" \
    env \
        BTC3_WALLET="$WALLET" \
        BTC3_POOL_HOST="$POOL_HOST" \
        BTC3_POOL_PORT="$POOL_PORT" \
        BTC3_WORKER="$WORKER" \
        BTC3_SERIAL="JCM33-DUAL" \
        JCM33_XVC_HOST=127.0.0.1 \
        JCM33_XVC_PORT="$XVC_PORT" \
        python3 "$MINER" 2>&1 | tee "$RUN_DIR/miner.log"
miner_status=${PIPESTATUS[0]}
set -e

if [ "$miner_status" -ne 0 ] && [ "$miner_status" -ne 124 ]; then
    die "dual miner exited unexpectedly with status $miner_status"
fi

PHASE=classification
accepted_a=$(grep -c 'ACCEPTED.*device=A' "$RUN_DIR/miner.log" || true)
accepted_b=$(grep -c 'ACCEPTED.*device=B' "$RUN_DIR/miner.log" || true)
rejected=$(grep -c 'REJECTED' "$RUN_DIR/miner.log" || true)
mismatches=$(grep -c 'SHARE mismatch' "$RUN_DIR/miner.log" || true)

echo
echo "===== CANARY RESULT ====="
echo "accepted_A=$accepted_a"
echo "accepted_B=$accepted_b"
echo "rejected=$rejected"
echo "hardware_software_mismatches=$mismatches"

(( accepted_a > 0 )) || die "FPGA A produced no accepted share"
(( accepted_b > 0 )) || die "FPGA B produced no accepted share"
(( rejected == 0 )) || die "pool rejected one or more 650 MHz shares"
(( mismatches == 0 )) || die "hardware/software share mismatch detected"

PHASE=complete

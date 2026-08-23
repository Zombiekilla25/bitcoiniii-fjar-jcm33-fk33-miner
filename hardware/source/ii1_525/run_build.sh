#!/usr/bin/env bash
set -Eeuo pipefail

SRC=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
OUT="$SRC/output"
VIVADO=${VIVADO:-"$HOME/Xilinx/2026.1/Vivado/bin/vivado"}
STAMP=$(date -u '+%Y%m%dT%H%M%SZ')
LOG="$SRC/build_${STAMP}.log"

if [[ ! -x "$VIVADO" ]]; then
    printf 'ABORT: Vivado executable not found: %s\n' "$VIVADO" >&2
    exit 1
fi

if pgrep -af '[v]ivado|[v]itis|[x]sim|[x]elab|[x]vlog'; then
    printf 'ABORT: another Xilinx build or simulation process is running\n' >&2
    exit 1
fi

mkdir -p "$OUT"
exec > >(tee -a "$LOG") 2>&1

printf '===== FJAR II1 BSCAN 525 MHZ BUILD =====\n'
printf 'Expected duration: 45-120 minutes\n'
printf 'This build does not access, program, or change voltage on any FPGA.\n'

SIM_LOG="$SRC/simulation_${STAMP}.log"
"$VIVADO" -mode batch -nojournal -nolog \
    -source "$SRC/simulate_engine.tcl" 2>&1 | tee "$SIM_LOG"

grep -Fq 'SHA3T II1 RAW DIGEST ALL PASS' "$SIM_LOG" || {
    printf 'ABORT: raw-digest simulation gate did not pass\n' >&2
    exit 1
}

"$VIVADO" -mode batch -nojournal -nolog \
    -source "$SRC/build_bscan_525.tcl"

BIT="$OUT/fk33_fjar_bscan_525.bit"
[[ -s "$BIT" ]] || {
    printf 'ABORT: final bitstream was not created\n' >&2
    exit 1
}

grep -Fq 'All user specified timing constraints are met.' \
    "$OUT/timing_routed.rpt" || {
    printf 'ABORT: routed timing did not pass\n' >&2
    exit 1
}

if grep -Eq \
    'Number of Nets with Routing Errors[[:space:]]*:[[:space:]]*[1-9]|Number of Node Overlaps[[:space:]]*:[[:space:]]*[1-9]' \
    "$OUT/route_status.rpt"; then
    printf 'ABORT: routing errors or node overlaps found\n' >&2
    exit 1
fi

sha256sum "$BIT" >"$OUT/SHA256SUMS"
cat "$OUT/SHA256SUMS"
printf 'PASS: simulation, routing, setup timing, and hold timing gates passed\n'

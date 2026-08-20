#!/usr/bin/env bash
set -euo pipefail

VIVADO_BIN="${VIVADO_BIN:-$HOME/Xilinx/2026.1/Vivado/bin/vivado}"

if [[ ! -x "$VIVADO_BIN" ]]; then
    echo "Vivado executable not found: $VIVADO_BIN" >&2
    exit 1
fi

run_step() {
    local script="$1"
    local log="$2"
    "$VIVADO_BIN" -mode batch -nojournal -nolog -source "$script" 2>&1 | tee "$log"
}

run_step simulate_token3_cycles.tcl simulate_token3_cycles.log
grep -q "TOKEN3 ALL PASS" simulate_token3_cycles.log

run_step build_synth_80pipe_token3_350_margin.tcl build_synth_80pipe_token3_350_margin.log
run_step place_only_80pipe_token3_350_margin.tcl place_only_80pipe_token3_350_margin.log
run_step finish_80pipe_token3_350_margin.tcl finish_80pipe_token3_350_margin.log

test -s bc3_80pipe_token3_350_margin.bit
test -s bc3_80pipe_token3_350_margin.ltx

echo "Build complete:"
ls -lh bc3_80pipe_token3_350_margin.bit bc3_80pipe_token3_350_margin.ltx

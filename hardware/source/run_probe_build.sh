#!/usr/bin/env bash
set -Eeuo pipefail

VIVADO=${VIVADO:-"$HOME/Xilinx/2026.1/Vivado/bin/vivado"}
SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)

if [ ! -x "$VIVADO" ]; then
    printf 'Vivado executable not found: %s\n' "$VIVADO" >&2
    exit 1
fi

cd "$SCRIPT_DIR"
"$VIVADO" \
    -mode batch -nojournal -nolog \
    -source build_protocol_probe.tcl \
    2>&1 | tee build_protocol_probe.log

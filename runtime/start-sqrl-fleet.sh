#!/usr/bin/env bash
set -Eeuo pipefail

CONFIG=${FJAR_FLEET_CONFIG:-"$HOME/.config/fk33-fjar-miner/fleet.env"}
INSTALL_ROOT="$HOME/.local/share/fk33-fjar-miner"
RUN="$HOME/.local/state/fk33-fjar-miner/fleet"

if [[ ! -r "$CONFIG" ]]; then
    printf 'Fleet configuration is missing: %s\n' "$CONFIG" >&2
    exit 1
fi

# shellcheck disable=SC1090
source "$CONFIG"

SERIAL_LIST=${FJAR_FLEET_SERIALS:-}
BASE_PORT=${FJAR_FLEET_BASE_PORT:-}

if [[ ! "$SERIAL_LIST" =~ ^[0-9]{6,32}(,[0-9]{6,32})*$ ]]; then
    printf 'Invalid FJAR_FLEET_SERIALS in %s\n' "$CONFIG" >&2
    exit 1
fi
if [[ ! "$BASE_PORT" =~ ^[0-9]+$ ]] ||
   ((BASE_PORT < 1 || BASE_PORT > 65535)); then
    printf 'Invalid FJAR_FLEET_BASE_PORT in %s\n' "$CONFIG" >&2
    exit 1
fi

SQRL="$INSTALL_ROOT/private/bin/sqrl_bridge_rawjtag_coe"
LIBS="$INSTALL_ROOT/private/compat_libs"
BIT="$INSTALL_ROOT/current/hardware/prebuilt/fk33_fjar_bscan_350.bit"

[[ -x "$SQRL" ]] || {
    printf 'SQRL bridge is missing or not executable: %s\n' "$SQRL" >&2
    exit 1
}
[[ -s "$BIT" ]] || {
    printf 'Mining bitstream is missing: %s\n' "$BIT" >&2
    exit 1
}

mkdir -p "$RUN"
chmod 700 "$RUN"
cd "$RUN"

: >virtual_ports
: >sqrl.log
chmod 600 virtual_ports sqrl.log

exec env \
    LANG=C \
    LC_ALL=C \
    LD_LIBRARY_PATH="$LIBS" \
    "$SQRL" \
        -s ",$SERIAL_LIST" \
        -b "$BIT" \
        -p "$BASE_PORT" \
        -t \
        -f "$RUN/sqrl.log"

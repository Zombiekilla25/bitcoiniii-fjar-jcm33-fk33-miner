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
BITSTREAM_SELECTION=${FJAR_FLEET_BITSTREAM:-525}

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
case "$BITSTREAM_SELECTION" in
    525)
        BIT="$INSTALL_ROOT/current/hardware/prebuilt/fk33_fjar_bscan_525.bit"
        EXPECTED_BIT_SHA="64e0a7d21a10b4aa04b340c826af7d75363b5d5ba5e39330fe28c42ff103821c"
        ;;
    650)
        BIT="$INSTALL_ROOT/current/hardware/prebuilt/fk33_native_bscan_650_validated.bit"
        EXPECTED_BIT_SHA="bd494ba2ea697a5e916b51caf4bdab8e5c620cd121bfd4b2e9a806deb5596c39"
        printf 'WARNING: selecting one-card-qualified 650 MHz image for staged fleet deployment.\n' >&2
        ;;
    *)
        printf 'Invalid FJAR_FLEET_BITSTREAM in %s: %s (expected 525 or 650)\n' \
            "$CONFIG" "$BITSTREAM_SELECTION" >&2
        exit 1
        ;;
esac

[[ -x "$SQRL" ]] || {
    printf 'SQRL bridge is missing or not executable: %s\n' "$SQRL" >&2
    exit 1
}
[[ -s "$BIT" ]] || {
    printf 'Mining bitstream is missing: %s\n' "$BIT" >&2
    exit 1
}
ACTUAL_BIT_SHA=$(sha256sum "$BIT" | awk '{print $1}')
[[ "$ACTUAL_BIT_SHA" == "$EXPECTED_BIT_SHA" ]] || {
    printf 'Mining bitstream checksum mismatch: expected=%s actual=%s path=%s\n' \
        "$EXPECTED_BIT_SHA" "$ACTUAL_BIT_SHA" "$BIT" >&2
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

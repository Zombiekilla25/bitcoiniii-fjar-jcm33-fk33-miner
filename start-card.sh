#!/usr/bin/env bash
set -Eeuo pipefail

SERIAL=${1:-}
if [[ ! "$SERIAL" =~ ^[0-9]{6,32}$ ]]; then
    printf 'Usage: %s FK_SERIAL\n' "$0" >&2
    exit 2
fi

CONFIG_ROOT="$HOME/.config/fk33-fjar-miner"
INSTALL_ROOT="$HOME/.local/share/fk33-fjar-miner"

test -r "$CONFIG_ROOT/miner.env"
test -r "$CONFIG_ROOT/cards/$SERIAL.env"
test -x "$INSTALL_ROOT/private/bin/sqrl_bridge_rawjtag_coe"
test -s "$INSTALL_ROOT/current/hardware/prebuilt/fk33_fjar_bscan_350.bit"

MATCHES=$(grep -l "^${SERIAL}$" \
    /sys/bus/usb/devices/*/serial 2>/dev/null | wc -l)
if [[ "$MATCHES" -ne 1 ]]; then
    printf 'Expected exactly one attached FK33 serial %s; found %s.\n' \
        "$SERIAL" "$MATCHES" >&2
    exit 3
fi

systemctl --user enable --now "fk33-sqrl-bridge@$SERIAL.service"
systemctl --user enable --now "fjar-fk33-standalone@$SERIAL.service"

systemctl --user --no-pager --full status \
    "fk33-sqrl-bridge@$SERIAL.service" \
    "fjar-fk33-standalone@$SERIAL.service"

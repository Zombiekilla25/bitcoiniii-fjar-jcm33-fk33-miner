#!/usr/bin/env bash
set -Eeuo pipefail

SERIAL=${1:-}
if [[ ! "$SERIAL" =~ ^[0-9]{6,32}$ ]]; then
    printf 'Usage: %s FK_SERIAL\n' "$0" >&2
    exit 2
fi

CONFIG_ROOT="$HOME/.config/fk33-fjar-miner"
test -r "$CONFIG_ROOT/miner.env"
test -r "$CONFIG_ROOT/fleet.env"
test -r "$CONFIG_ROOT/cards/$SERIAL.env"

systemctl --user enable --now fk33-sqrl-fleet.service
systemctl --user enable --now "fjar-fk33-fleet@$SERIAL.service"
systemctl --user --no-pager --full status \
    fk33-sqrl-fleet.service "fjar-fk33-fleet@$SERIAL.service"

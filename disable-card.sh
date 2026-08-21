#!/usr/bin/env bash
set -Eeuo pipefail

SERIAL=${1:-}
if [[ ! "$SERIAL" =~ ^[0-9]{6,32}$ ]]; then
    printf 'Usage: %s FK_SERIAL\n' "$0" >&2
    exit 2
fi

systemctl --user disable --now "fjar-fk33-fleet@$SERIAL.service" || true
printf 'Disabled miner %s; the shared fleet bridge remains available.\n' "$SERIAL"

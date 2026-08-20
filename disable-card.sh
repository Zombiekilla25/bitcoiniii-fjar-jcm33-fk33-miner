#!/usr/bin/env bash
set -euo pipefail

SERIAL=${1:-}
if [[ ! "$SERIAL" =~ ^[0-9]{6,32}$ ]]; then
    printf 'Usage: %s FK_SERIAL\n' "$0" >&2
    exit 2
fi

systemctl --user disable --now "fjar-fk33-bridge@$SERIAL.service" || true
systemctl --user disable --now "fjar-fk33-worker@$SERIAL.service" || true

printf 'Disabled FK33 serial %s. Configuration, logs, and release files were retained.\n' \
    "$SERIAL"

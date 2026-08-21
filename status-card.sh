#!/usr/bin/env bash
set -Eeuo pipefail

SERIAL=${1:-}
if [[ ! "$SERIAL" =~ ^[0-9]{6,32}$ ]]; then
    printf 'Usage: %s FK_SERIAL\n' "$0" >&2
    exit 2
fi

STATE="$HOME/.local/state/fk33-fjar-miner/$SERIAL"

printf '===== SERVICES =====\n'
systemctl --user --no-pager --full status \
    "fk33-sqrl-bridge@$SERIAL.service" \
    "fjar-fk33-standalone@$SERIAL.service" || true

printf '\n===== RECENT MINER ACTIVITY =====\n'
grep -E \
    'DEVFEE|connected|subscribed|authorized|difficulty=|FPGA job|SHARE|hw=|sw=|SUBMITTED|ACCEPTED|REJECTED|MISMATCH|disagreement|reconnecting' \
    "$STATE/miner.log" 2>/dev/null | tail -n 80 || true

printf '\n===== RECENT SQRL ACTIVITY =====\n'
grep -E \
    'matches filter|Opened virtual|Bitstream Loaded|Got connection|Accepting Client|Failed|Error' \
    "$STATE/sqrl.log" 2>/dev/null | tail -n 50 || true

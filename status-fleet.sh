#!/usr/bin/env bash
set -Eeuo pipefail

CONFIG="$HOME/.config/fk33-fjar-miner/fleet.env"
test -r "$CONFIG"
# shellcheck disable=SC1090
source "$CONFIG"
IFS=, read -r -a SERIALS <<<"${FJAR_FLEET_SERIALS:-}"

printf '===== FLEET BRIDGE =====\n'
systemctl --user show fk33-sqrl-fleet.service \
    -p ActiveState -p SubState -p MainPID -p NRestarts

printf '\n===== CARDS =====\n'
for SERIAL in "${SERIALS[@]}"; do
    PORT=$(sed -n 's/^FJAR_HW_PORT=//p' \
        "$HOME/.config/fk33-fjar-miner/cards/$SERIAL.env" | tail -n1)
    STATE=$(systemctl --user is-active \
        "fjar-fk33-fleet@$SERIAL.service" 2>/dev/null || true)
    LAST=$(grep -E '\[ACCEPTED\]\[USER\]|MISMATCH|\[REJECTED\]|Traceback' \
        "$HOME/.local/state/fk33-fjar-miner/$SERIAL/miner.log" 2>/dev/null |
        tail -n1 || true)
    printf '%s port=%s service=%s\n' "$SERIAL" "$PORT" "$STATE"
    [[ -n "$LAST" ]] && printf '  %s\n' "$LAST"
done

printf '\n===== LISTENERS =====\n'
/usr/bin/ss -ltnp 2>/dev/null |
    grep -E 'sqrl_bridge_raw|Local Address' || true

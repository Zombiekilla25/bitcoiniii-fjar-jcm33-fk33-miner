#!/usr/bin/env bash
set -Eeuo pipefail

CONFIG="$HOME/.config/fk33-fjar-miner/fleet.env"
test -r "$CONFIG"
# shellcheck disable=SC1090
source "$CONFIG"
IFS=, read -r -a SERIALS <<<"${FJAR_FLEET_SERIALS:-}"

systemctl --user enable --now fk33-sqrl-fleet.service
for SERIAL in "${SERIALS[@]}"; do
    systemctl --user enable --now "fjar-fk33-fleet@$SERIAL.service"
done

"$(dirname -- "$0")/status-fleet.sh"

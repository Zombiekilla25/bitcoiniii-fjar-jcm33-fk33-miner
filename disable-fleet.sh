#!/usr/bin/env bash
set -Eeuo pipefail

CONFIG="$HOME/.config/fk33-fjar-miner/fleet.env"
test -r "$CONFIG"
# shellcheck disable=SC1090
source "$CONFIG"
IFS=, read -r -a SERIALS <<<"${FJAR_FLEET_SERIALS:-}"

for SERIAL in "${SERIALS[@]}"; do
    systemctl --user disable --now "fjar-fk33-fleet@$SERIAL.service" || true
done
systemctl --user disable --now fk33-sqrl-fleet.service || true
printf 'Disabled the FK33 fleet; configuration and logs were retained.\n'

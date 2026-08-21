#!/usr/bin/env bash
set -Eeuo pipefail

SERIAL=${1:-}
PORT=${2:-}
CONFIG=${FJAR_FLEET_CONFIG:-"$HOME/.config/fk33-fjar-miner/fleet.env"}
LOG="$HOME/.local/state/fk33-fjar-miner/fleet/sqrl.log"

if [[ ! "$SERIAL" =~ ^[0-9]{6,32}$ ]] ||
   [[ ! "$PORT" =~ ^[0-9]+$ ]] ||
   ((PORT < 1 || PORT > 65535)); then
    printf 'Usage: %s SERIAL PORT\n' "$0" >&2
    exit 2
fi

# shellcheck disable=SC1090
source "$CONFIG"
IFS=, read -r -a SERIALS <<<"${FJAR_FLEET_SERIALS:-}"
EXPECTED_LOADS=${#SERIALS[@]}

mapping_ready() {
    awk -v serial="$SERIAL" -v port="$PORT" '
        index($0, "Device with serial " serial "A matches filter") {
            scanning=1
            next
        }
        scanning && index($0, "Device with serial ") {
            exit
        }
        scanning && index($0, "Opened virtual TCP serial port ") {
            found=index($0, "Opened virtual TCP serial port " port) > 0
            exit
        }
        END {exit !found}
    ' "$LOG" 2>/dev/null
}

for _ in {1..300}; do
    LOADED=$(grep -c 'Bitstream Loaded' "$LOG" 2>/dev/null || true)
    LOADED=${LOADED:-0}

    if ((LOADED >= EXPECTED_LOADS)) &&
       mapping_ready &&
       /usr/bin/ss -ltnH |
           awk -v port="$PORT" '
               $4 ~ (":" port "$") {found=1}
               END {exit !found}
           '; then
        exit 0
    fi

    sleep 1
done

printf 'Fleet card did not become ready: serial=%s port=%s\n' \
    "$SERIAL" "$PORT" >&2
tail -n 160 "$LOG" >&2 || true
exit 1

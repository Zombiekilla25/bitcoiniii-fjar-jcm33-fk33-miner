#!/usr/bin/env bash
set -Eeuo pipefail

VERSION="0.2.0-beta"
SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
INSTALL_ROOT="$HOME/.local/share/fk33-fjar-miner"
INSTALL_DIR="$INSTALL_ROOT/$VERSION"
PRIVATE_ROOT="$INSTALL_ROOT/private"
PRIVATE_BIN="$PRIVATE_ROOT/bin"
PRIVATE_COMPAT="$PRIVATE_ROOT/compat_libs"
CONFIG_DIR="$HOME/.config/fk33-fjar-miner"
CARD_CONFIG_DIR="$CONFIG_DIR/cards"
CONFIG_FILE="$CONFIG_DIR/miner.env"
STATE_ROOT="$HOME/.local/state/fk33-fjar-miner"
SYSTEMD_DIR="$HOME/.config/systemd/user"

WALLET=""
SERIAL=""
SQRL_BRIDGE=""
COMPAT_LIBS=""
POOL_HOST="stratum.pythonpool.dev"
POOL_PORT="3358"
HW_PORT="22000"
WORKER=""
START_NOW=0

usage() {
    cat <<'USAGE'
Usage:
  ./install.sh --wallet ADDRESS --serial SERIAL --sqrl-bridge PATH [options]

Required:
  --wallet ADDRESS       Lowercase public fjarcode: payout address
  --serial SERIAL        Exact SQRL FK33 USB serial
  --sqrl-bridge PATH     Legally obtained sqrl_bridge_rawjtag_coe executable

Options:
  --compat-libs DIR      Directory containing required legacy shared libraries
  --pool-host HOST       Compatible Stratum v1 host
  --pool-port PORT       Compatible Stratum v1 port
  --hw-port PORT         Unique local SQRL TCP port (default: 22000)
  --worker NAME          Pool worker suffix (default: fk33-SERIAL)
  --start                Enable services and program/start the selected card
  -h, --help             Show this help

Every card on one host requires a different --hw-port. This miner contains a
transparent 1% time-based developer fee; read docs/DEV_FEE.md before starting.
USAGE
}

need_value() {
    if (($# < 2)) || [[ -z ${2:-} ]]; then
        printf 'Missing value for %s\n' "$1" >&2
        exit 2
    fi
}

while (($#)); do
    case "$1" in
        --wallet)
            need_value "$@"; WALLET=$2; shift 2 ;;
        --serial)
            need_value "$@"; SERIAL=$2; shift 2 ;;
        --sqrl-bridge)
            need_value "$@"; SQRL_BRIDGE=$2; shift 2 ;;
        --compat-libs)
            need_value "$@"; COMPAT_LIBS=$2; shift 2 ;;
        --pool-host)
            need_value "$@"; POOL_HOST=$2; shift 2 ;;
        --pool-port)
            need_value "$@"; POOL_PORT=$2; shift 2 ;;
        --hw-port)
            need_value "$@"; HW_PORT=$2; shift 2 ;;
        --worker)
            need_value "$@"; WORKER=$2; shift 2 ;;
        --start)
            START_NOW=1; shift ;;
        -h|--help)
            usage; exit 0 ;;
        *)
            printf 'Unknown argument: %s\n' "$1" >&2
            usage >&2
            exit 2 ;;
    esac
done

if [[ ! "$WALLET" =~ ^fjarcode:[a-z0-9]{20,120}$ ]]; then
    printf 'Invalid or missing --wallet value.\n' >&2
    exit 2
fi
if [[ ! "$SERIAL" =~ ^[0-9]{6,32}$ ]]; then
    printf 'Invalid or missing --serial value.\n' >&2
    exit 2
fi
if [[ ! "$POOL_HOST" =~ ^[A-Za-z0-9.-]+$ ]]; then
    printf 'Invalid --pool-host value.\n' >&2
    exit 2
fi
for PORT_SPEC in "pool:$POOL_PORT" "hardware:$HW_PORT"; do
    PORT_NAME=${PORT_SPEC%%:*}
    PORT_VALUE=${PORT_SPEC#*:}
    if [[ ! "$PORT_VALUE" =~ ^[0-9]+$ ]] ||
       ((PORT_VALUE < 1 || PORT_VALUE > 65535)); then
        printf 'Invalid %s port: %s\n' "$PORT_NAME" "$PORT_VALUE" >&2
        exit 2
    fi
done

if [[ -z "$WORKER" ]]; then
    WORKER="fk33-$SERIAL"
fi
if [[ ! "$WORKER" =~ ^[A-Za-z0-9_-]{1,64}$ ]]; then
    printf 'Invalid --worker value.\n' >&2
    exit 2
fi
if [[ ! -x "$SQRL_BRIDGE" ]]; then
    printf 'SQRL bridge is missing or not executable: %s\n' "$SQRL_BRIDGE" >&2
    exit 2
fi
if [[ -n "$COMPAT_LIBS" && ! -d "$COMPAT_LIBS" ]]; then
    printf 'Compatibility-library directory is missing: %s\n' "$COMPAT_LIBS" >&2
    exit 2
fi

LDD_OUTPUT=$(env LD_LIBRARY_PATH="$COMPAT_LIBS" ldd "$SQRL_BRIDGE")
if grep -q 'not found' <<<"$LDD_OUTPUT"; then
    printf 'Unresolved SQRL bridge dependencies:\n%s\n' \
        "$(grep 'not found' <<<"$LDD_OUTPUT")" >&2
    exit 2
fi

"$SCRIPT_DIR/verify-release.sh"

mkdir -p \
    "$INSTALL_ROOT" "$PRIVATE_BIN" "$PRIVATE_COMPAT" \
    "$CONFIG_DIR" "$CARD_CONFIG_DIR" \
    "$STATE_ROOT/$SERIAL/sqrl" "$SYSTEMD_DIR"
chmod 700 \
    "$PRIVATE_ROOT" "$PRIVATE_BIN" "$PRIVATE_COMPAT" \
    "$CONFIG_DIR" "$CARD_CONFIG_DIR" \
    "$STATE_ROOT" "$STATE_ROOT/$SERIAL" "$STATE_ROOT/$SERIAL/sqrl"

for CARD_FILE in "$CARD_CONFIG_DIR"/*.env; do
    [[ -e "$CARD_FILE" ]] || continue
    [[ $(basename "$CARD_FILE") == "$SERIAL.env" ]] && continue
    EXISTING_PORT=$(sed -n 's/^FJAR_HW_PORT=//p' "$CARD_FILE" | tail -n 1)
    if [[ "$EXISTING_PORT" == "$HW_PORT" ]]; then
        printf 'Hardware port %s is already assigned in %s\n' \
            "$HW_PORT" "$CARD_FILE" >&2
        exit 3
    fi
done

if [[ -e "$INSTALL_DIR" ]]; then
    printf 'Using existing installed release: %s\n' "$INSTALL_DIR"
else
    cp -a "$SCRIPT_DIR" "$INSTALL_DIR"
fi
ln -sfn "$INSTALL_DIR" "$INSTALL_ROOT/current"

PRIVATE_BRIDGE="$PRIVATE_BIN/sqrl_bridge_rawjtag_coe"
if [[ ! -e "$PRIVATE_BRIDGE" ]] ||
   [[ $(readlink -f "$SQRL_BRIDGE") != $(readlink -f "$PRIVATE_BRIDGE") ]]; then
    install -m 0755 "$SQRL_BRIDGE" "$PRIVATE_BRIDGE"
fi
if [[ -n "$COMPAT_LIBS" ]] &&
   [[ $(readlink -f "$COMPAT_LIBS") != $(readlink -f "$PRIVATE_COMPAT") ]]; then
    cp -a "$COMPAT_LIBS"/. "$PRIVATE_COMPAT"/
fi

STAMP=$(date -u +%Y%m%dT%H%M%SZ)
if [[ -e "$CONFIG_FILE" ]]; then
    cp -p "$CONFIG_FILE" "$CONFIG_FILE.before-$STAMP"
fi
if [[ -e "$CARD_CONFIG_DIR/$SERIAL.env" ]]; then
    cp -p "$CARD_CONFIG_DIR/$SERIAL.env" \
        "$CARD_CONFIG_DIR/$SERIAL.env.before-$STAMP"
fi

umask 077
{
    printf 'FJAR_WALLET=%s\n' "$WALLET"
    printf 'FJAR_POOL_HOST=%s\n' "$POOL_HOST"
    printf 'FJAR_POOL_PORT=%s\n' "$POOL_PORT"
} >"$CONFIG_FILE"
{
    printf 'FJAR_HW_PORT=%s\n' "$HW_PORT"
    printf 'FJAR_WORKER=%s\n' "$WORKER"
} >"$CARD_CONFIG_DIR/$SERIAL.env"

for UNIT in fk33-sqrl-bridge@.service fjar-fk33-standalone@.service; do
    if [[ -e "$SYSTEMD_DIR/$UNIT" ]]; then
        cp -p "$SYSTEMD_DIR/$UNIT" "$SYSTEMD_DIR/$UNIT.before-$STAMP"
    fi
    install -m 0644 "$SCRIPT_DIR/systemd/$UNIT" "$SYSTEMD_DIR/$UNIT"
done

systemctl --user daemon-reload

printf '\nInstalled FK33 FJAR Miner %s\n' "$VERSION"
printf 'Release: %s\n' "$INSTALL_DIR"
printf 'Serial:  %s\n' "$SERIAL"
printf 'Port:    %s\n' "$HW_PORT"
printf 'Config:  %s\n' "$CARD_CONFIG_DIR/$SERIAL.env"
printf 'SQRL:    %s\n' "$PRIVATE_BIN/sqrl_bridge_rawjtag_coe"

if ((START_NOW)); then
    "$SCRIPT_DIR/start-card.sh" "$SERIAL"
else
    printf '\nNo hardware was programmed. Start after review with:\n\n'
    printf '  %q %q\n' "$SCRIPT_DIR/start-card.sh" "$SERIAL"
fi

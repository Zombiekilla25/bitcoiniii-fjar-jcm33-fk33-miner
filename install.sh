#!/usr/bin/env bash
set -euo pipefail

VERSION="0.1.0-beta"
SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
INSTALL_ROOT="$HOME/.local/share/fk33-fjar-miner"
INSTALL_DIR="$INSTALL_ROOT/$VERSION"
CONFIG_DIR="$HOME/.config/fk33-fjar-miner"
CONFIG_FILE="$CONFIG_DIR/miner.env"
STATE_ROOT="$HOME/.local/state/fk33-fjar-miner"
SYSTEMD_DIR="$HOME/.config/systemd/user"

WALLET=""
SERIAL=""
POOL_HOST="stratum.pythonpool.dev"
POOL_PORT="3358"
VIVADO_BIN="$HOME/Xilinx/2026.1/Vivado/bin/vivado"
START_NOW=0

usage() {
    cat <<'USAGE'
Usage:
  ./install.sh --wallet FJAR_ADDRESS --serial FK_SERIAL [options]

Required:
  --wallet ADDRESS   Lowercase fjarcode: payout address owned by you
  --serial SERIAL    Exact USB/JTAG serial of one SQRL FK33

Options:
  --vivado PATH      Vivado executable (default: ~/Xilinx/2026.1/...)
  --pool-host HOST   Compatible Stratum v1 host
  --pool-port PORT   Compatible Stratum v1 port
  --start            Enable services and program/start the selected card
  -h, --help         Show this help

The miner contains a transparent 1% time-based developer fee. Read
docs/DEV_FEE.md before using --start.
USAGE
}

while (($#)); do
    case "$1" in
        --wallet)
            WALLET=${2:-}
            shift 2
            ;;
        --serial)
            SERIAL=${2:-}
            shift 2
            ;;
        --vivado)
            VIVADO_BIN=${2:-}
            shift 2
            ;;
        --pool-host)
            POOL_HOST=${2:-}
            shift 2
            ;;
        --pool-port)
            POOL_PORT=${2:-}
            shift 2
            ;;
        --start)
            START_NOW=1
            shift
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            printf 'Unknown argument: %s\n' "$1" >&2
            usage >&2
            exit 2
            ;;
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

if [[ ! "$POOL_PORT" =~ ^[0-9]+$ ]] ||
   ((POOL_PORT < 1 || POOL_PORT > 65535)); then
    printf 'Invalid --pool-port value.\n' >&2
    exit 2
fi

if [[ ! -x "$VIVADO_BIN" ]]; then
    printf 'Vivado executable not found: %s\n' "$VIVADO_BIN" >&2
    exit 2
fi

if [[ -e "$INSTALL_DIR" ]]; then
    printf 'Refusing to overwrite existing version: %s\n' "$INSTALL_DIR" >&2
    exit 3
fi

"$SCRIPT_DIR/verify-release.sh"

mkdir -p "$INSTALL_ROOT" "$CONFIG_DIR" "$STATE_ROOT/$SERIAL" "$SYSTEMD_DIR"
chmod 700 "$CONFIG_DIR" "$STATE_ROOT" "$STATE_ROOT/$SERIAL"

cp -a "$SCRIPT_DIR" "$INSTALL_DIR"
ln -sfn "$INSTALL_DIR" "$INSTALL_ROOT/current"

if [[ -e "$CONFIG_FILE" ]]; then
    printf 'Keeping existing configuration: %s\n' "$CONFIG_FILE"
else
    umask 077
    {
        printf 'FJAR_WALLET=%s\n' "$WALLET"
        printf 'FJAR_POOL_HOST=%s\n' "$POOL_HOST"
        printf 'FJAR_POOL_PORT=%s\n' "$POOL_PORT"
        printf 'VIVADO_BIN=%s\n' "$VIVADO_BIN"
    } > "$CONFIG_FILE"
fi

STAMP=$(date -u +%Y%m%dT%H%M%SZ)
for UNIT in fjar-fk33-worker@.service fjar-fk33-bridge@.service; do
    if [[ -e "$SYSTEMD_DIR/$UNIT" ]]; then
        cp -p "$SYSTEMD_DIR/$UNIT" "$SYSTEMD_DIR/$UNIT.before-$STAMP"
    fi
    install -m 0644 "$SCRIPT_DIR/systemd/$UNIT" "$SYSTEMD_DIR/$UNIT"
done

systemctl --user daemon-reload

printf '\nInstalled FK33 FJAR Miner %s\n' "$VERSION"
printf 'Release: %s\n' "$INSTALL_DIR"
printf 'Config:  %s\n' "$CONFIG_FILE"
printf 'State:   %s\n' "$STATE_ROOT/$SERIAL"

if ((START_NOW)); then
    printf '\nStarting serial %s; Vivado will program the FPGA.\n' "$SERIAL"
    systemctl --user enable --now "fjar-fk33-worker@$SERIAL.service"
    systemctl --user enable --now "fjar-fk33-bridge@$SERIAL.service"
    systemctl --user --no-pager --full status \
        "fjar-fk33-worker@$SERIAL.service" \
        "fjar-fk33-bridge@$SERIAL.service"
else
    cat <<EOF

No hardware was programmed. After reviewing the configuration, start with:

  systemctl --user enable --now fjar-fk33-worker@$SERIAL.service
  systemctl --user enable --now fjar-fk33-bridge@$SERIAL.service
EOF
fi

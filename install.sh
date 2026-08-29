#!/usr/bin/env bash
set -Eeuo pipefail

VERSION="0.5.0-beta"
SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
INSTALL_ROOT="$HOME/.local/share/fk33-fjar-miner"
INSTALL_DIR="$INSTALL_ROOT/$VERSION"
PRIVATE_ROOT="$INSTALL_ROOT/private"
PRIVATE_BIN="$PRIVATE_ROOT/bin"
PRIVATE_COMPAT="$PRIVATE_ROOT/compat_libs"
CONFIG_DIR="$HOME/.config/fk33-fjar-miner"
CARD_CONFIG_DIR="$CONFIG_DIR/cards"
STATE_ROOT="$HOME/.local/state/fk33-fjar-miner"
SYSTEMD_DIR="$HOME/.config/systemd/user"

WALLET=""
SQRL_BRIDGE="$SCRIPT_DIR/third_party/sqrl/sqrl_bridge_rawjtag_coe"
COMPAT_LIBS=""
POOL_HOST="stratum.pythonpool.dev"
POOL_PORT="3358"
BITSTREAM_SELECTION="525"
INSTALL_UDEV=0
ENABLE_LINGER=0
START_NOW=0
CARDS=()

usage() {
    cat <<'USAGE'
Usage:
  ./install.sh --wallet ADDRESS --card SERIAL:PORT [--card SERIAL:PORT ...]
               [options]

Required:
  --wallet ADDRESS       Lowercase public fjarcode: payout address
  --card SERIAL:PORT     FK33 USB serial and its fleet TCP port; repeat per card

Options:
  --sqrl-bridge PATH     Authorized compatible bridge override
                        (default: bundled patched SQRL bridge)
  --compat-libs DIR      Directory containing required legacy shared libraries
  --pool-host HOST       Compatible Stratum v1 host
  --pool-port PORT       Compatible Stratum v1 port
  --bitstream 525|650    Select the authenticated image (default: 525);
                         650 is one-card qualified and a staged fleet rollout
  --install-udev         Install serial-specific USB permissions (needs sudo -n)
  --enable-linger        Start user services before login (needs sudo -n)
  --start                Enable and start the complete fleet after installation
  -h, --help             Show this help

Cards must be listed in the bridge's physical scan order and assigned consecutive
ports. Example: --card SERIAL_A:22000 --card SERIAL_B:22001.

The runtime contains a transparent 1% time-based developer fee. Read
docs/DEV_FEE.md and THIRD_PARTY.md before starting.
USAGE
}

need_value() {
    if (($# < 2)) || [[ -z ${2:-} ]]; then
        printf 'Missing value for %s\n' "$1" >&2
        exit 2
    fi
}

valid_port() {
    [[ $1 =~ ^[0-9]+$ ]] && ((10#$1 >= 1 && 10#$1 <= 65535))
}

while (($#)); do
    case "$1" in
        --wallet)
            need_value "$@"; WALLET=$2; shift 2 ;;
        --card)
            need_value "$@"; CARDS+=("$2"); shift 2 ;;
        --sqrl-bridge)
            need_value "$@"; SQRL_BRIDGE=$2; shift 2 ;;
        --compat-libs)
            need_value "$@"; COMPAT_LIBS=$2; shift 2 ;;
        --pool-host)
            need_value "$@"; POOL_HOST=$2; shift 2 ;;
        --pool-port)
            need_value "$@"; POOL_PORT=$2; shift 2 ;;
        --bitstream)
            need_value "$@"; BITSTREAM_SELECTION=$2; shift 2 ;;
        --install-udev)
            INSTALL_UDEV=1; shift ;;
        --enable-linger)
            ENABLE_LINGER=1; shift ;;
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
if ((${#CARDS[@]} == 0)); then
    printf 'At least one --card SERIAL:PORT is required.\n' >&2
    exit 2
fi
if [[ ! "$POOL_HOST" =~ ^[A-Za-z0-9.-]+$ ]] || ! valid_port "$POOL_PORT"; then
    printf 'Invalid pool host or port.\n' >&2
    exit 2
fi
if [[ "$BITSTREAM_SELECTION" != 525 && "$BITSTREAM_SELECTION" != 650 ]]; then
    printf 'Invalid --bitstream value: %s (expected 525 or 650).\n' \
        "$BITSTREAM_SELECTION" >&2
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

SERIALS=()
PORTS=()
declare -A SEEN_SERIALS=()
declare -A SEEN_PORTS=()

for SPEC in "${CARDS[@]}"; do
    if [[ ! "$SPEC" =~ ^([0-9]{6,32}):([0-9]+)$ ]]; then
        printf 'Invalid --card value: %s (expected SERIAL:PORT)\n' "$SPEC" >&2
        exit 2
    fi

    SERIAL=${BASH_REMATCH[1]}
    PORT=${BASH_REMATCH[2]}
    valid_port "$PORT" || {
        printf 'Invalid hardware port in --card %s\n' "$SPEC" >&2
        exit 2
    }
    if [[ -n ${SEEN_SERIALS[$SERIAL]:-} || -n ${SEEN_PORTS[$PORT]:-} ]]; then
        printf 'Duplicate serial or port in --card %s\n' "$SPEC" >&2
        exit 2
    fi

    SEEN_SERIALS[$SERIAL]=1
    SEEN_PORTS[$PORT]=1
    SERIALS+=("$SERIAL")
    PORTS+=("$PORT")
done

BASE_PORT=${PORTS[0]}
for INDEX in "${!PORTS[@]}"; do
    EXPECTED=$((10#$BASE_PORT + INDEX))
    if ((10#${PORTS[$INDEX]} != EXPECTED)); then
        printf 'Fleet ports must be consecutive in card order; expected %s for %s.\n' \
            "$EXPECTED" "${SERIALS[$INDEX]}" >&2
        exit 2
    fi
done

LDD_OUTPUT=$(env LD_LIBRARY_PATH="$COMPAT_LIBS" ldd "$SQRL_BRIDGE")
if grep -q 'not found' <<<"$LDD_OUTPUT"; then
    printf 'Unresolved SQRL bridge dependencies:\n%s\n' \
        "$(grep 'not found' <<<"$LDD_OUTPUT")" >&2
    printf 'Supply authorized ABI libraries with --compat-libs DIR.\n' >&2
    exit 2
fi

"$SCRIPT_DIR/verify-release.sh"

mkdir -p \
    "$INSTALL_ROOT" "$PRIVATE_BIN" "$PRIVATE_COMPAT" \
    "$CONFIG_DIR" "$CARD_CONFIG_DIR" "$STATE_ROOT/fleet" "$SYSTEMD_DIR"
chmod 700 \
    "$PRIVATE_ROOT" "$PRIVATE_BIN" "$PRIVATE_COMPAT" \
    "$CONFIG_DIR" "$CARD_CONFIG_DIR" "$STATE_ROOT" "$STATE_ROOT/fleet"

for SERIAL in "${SERIALS[@]}"; do
    mkdir -p "$STATE_ROOT/$SERIAL"
    chmod 700 "$STATE_ROOT/$SERIAL"
done

if [[ -e "$INSTALL_DIR" ]]; then
    printf 'Using existing installed release: %s\n' "$INSTALL_DIR"
else
    cp -a "$SCRIPT_DIR" "$INSTALL_DIR"
fi
ln -sfn "$INSTALL_DIR" "$INSTALL_ROOT/current"

install -m 0755 "$SQRL_BRIDGE" \
    "$PRIVATE_BIN/sqrl_bridge_rawjtag_coe"
if [[ -n "$COMPAT_LIBS" ]] &&
   [[ $(readlink -f "$COMPAT_LIBS") != $(readlink -f "$PRIVATE_COMPAT") ]]; then
    cp -a "$COMPAT_LIBS"/. "$PRIVATE_COMPAT"/
fi

STAMP=$(date -u +%Y%m%dT%H%M%SZ)
for PATH_TO_BACK_UP in "$CONFIG_DIR/miner.env" "$CONFIG_DIR/fleet.env"; do
    if [[ -e "$PATH_TO_BACK_UP" ]]; then
        cp -p "$PATH_TO_BACK_UP" "$PATH_TO_BACK_UP.before-$STAMP"
    fi
done

umask 077
{
    printf 'FJAR_WALLET=%s\n' "$WALLET"
    printf 'FJAR_POOL_HOST=%s\n' "$POOL_HOST"
    printf 'FJAR_POOL_PORT=%s\n' "$POOL_PORT"
} >"$CONFIG_DIR/miner.env"

SERIAL_LIST=$(IFS=,; printf '%s' "${SERIALS[*]}")
{
    printf 'FJAR_FLEET_SERIALS=%s\n' "$SERIAL_LIST"
    printf 'FJAR_FLEET_BASE_PORT=%s\n' "$BASE_PORT"
    printf 'FJAR_FLEET_BITSTREAM=%s\n' "$BITSTREAM_SELECTION"
} >"$CONFIG_DIR/fleet.env"

for INDEX in "${!SERIALS[@]}"; do
    SERIAL=${SERIALS[$INDEX]}
    {
        printf 'FJAR_HW_PORT=%s\n' "${PORTS[$INDEX]}"
        printf 'FJAR_WORKER=fk33-%s\n' "$SERIAL"
    } >"$CARD_CONFIG_DIR/$SERIAL.env"
done

UDEV_GENERATED="$CONFIG_DIR/99-fk33-sqrl.rules"
{
    printf '# Generated by FK33 FJAR Miner %s.\n' "$VERSION"
    for SERIAL in "${SERIALS[@]}"; do
        printf '%s\n' \
            "SUBSYSTEM==\"usb\", ATTR{idVendor}==\"0403\", ATTR{idProduct}==\"6010\", ATTR{serial}==\"$SERIAL\", GROUP=\"plugdev\", MODE=\"0660\", TAG+=\"uaccess\""
    done
} >"$UDEV_GENERATED"

for UNIT in fk33-sqrl-fleet.service fjar-fk33-fleet@.service; do
    if [[ -e "$SYSTEMD_DIR/$UNIT" ]]; then
        cp -p "$SYSTEMD_DIR/$UNIT" "$SYSTEMD_DIR/$UNIT.before-$STAMP"
    fi
    install -m 0644 "$SCRIPT_DIR/systemd/$UNIT" "$SYSTEMD_DIR/$UNIT"
done

if ((INSTALL_UDEV)); then
    /usr/bin/sudo -n /usr/bin/install -o root -g root -m 0644 \
        "$UDEV_GENERATED" /etc/udev/rules.d/99-fk33-sqrl.rules
    /usr/bin/sudo -n /usr/bin/udevadm control --reload-rules
    for SERIAL in "${SERIALS[@]}"; do
        SERIAL_FILE=$(grep -l "^${SERIAL}$" \
            /sys/bus/usb/devices/*/serial 2>/dev/null || true)
        [[ -n "$SERIAL_FILE" ]] &&
            /usr/bin/sudo -n /usr/bin/udevadm trigger \
                --action=change "${SERIAL_FILE%/serial}" || true
    done
fi

if ((ENABLE_LINGER)); then
    /usr/bin/sudo -n /usr/bin/loginctl enable-linger "$USER"
fi

systemctl --user daemon-reload

printf '\nInstalled FK33 FJAR Miner %s\n' "$VERSION"
printf 'Release: %s\n' "$INSTALL_DIR"
printf 'Fleet:   %s\n' "$SERIAL_LIST"
printf 'Ports:   %s-%s\n' "$BASE_PORT" "${PORTS[-1]}"
printf 'Image:   %s MHz\n' "$BITSTREAM_SELECTION"
printf 'Config:  %s\n' "$CONFIG_DIR"
printf 'SQRL:    %s\n' "$PRIVATE_BIN/sqrl_bridge_rawjtag_coe"
printf 'Udev:    %s\n' "$UDEV_GENERATED"

if ((START_NOW)); then
    "$SCRIPT_DIR/start-fleet.sh"
else
    printf '\nNo hardware was programmed. After reviewing the configuration, run:\n\n'
    printf '  %q\n' "$SCRIPT_DIR/start-fleet.sh"
fi

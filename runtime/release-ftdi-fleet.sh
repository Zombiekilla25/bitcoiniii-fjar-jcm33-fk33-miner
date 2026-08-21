#!/usr/bin/env bash
set -Eeuo pipefail

CONFIG=${FJAR_FLEET_CONFIG:-"$HOME/.config/fk33-fjar-miner/fleet.env"}

if [[ ! -r "$CONFIG" ]]; then
    printf 'Fleet configuration is missing: %s\n' "$CONFIG" >&2
    exit 1
fi

# shellcheck disable=SC1090
source "$CONFIG"

SERIAL_LIST=${FJAR_FLEET_SERIALS:-}
if [[ ! "$SERIAL_LIST" =~ ^[0-9]{6,32}(,[0-9]{6,32})*$ ]]; then
    printf 'Invalid FJAR_FLEET_SERIALS in %s\n' "$CONFIG" >&2
    exit 1
fi

IFS=, read -r -a SERIALS <<<"$SERIAL_LIST"

for _ in {1..120}; do
    FOUND=0

    for SERIAL in "${SERIALS[@]}"; do
        grep -l "^${SERIAL}$" /sys/bus/usb/devices/*/serial \
            >/dev/null 2>&1 && ((FOUND += 1)) || true
    done

    ((FOUND == ${#SERIALS[@]})) && break
    sleep 1
done

if ((FOUND != ${#SERIALS[@]})); then
    printf 'Expected %s configured FK33 cards; found %s\n' \
        "${#SERIALS[@]}" "$FOUND" >&2
    exit 1
fi

for SERIAL in "${SERIALS[@]}"; do
    mapfile -t MATCHES < <(
        grep -l "^${SERIAL}$" /sys/bus/usb/devices/*/serial 2>/dev/null
    )

    if ((${#MATCHES[@]} != 1)); then
        printf 'Serial %s has %s USB matches\n' \
            "$SERIAL" "${#MATCHES[@]}" >&2
        exit 1
    fi

    USB_DEV=${MATCHES[0]%/serial}

    if [[ $(cat "$USB_DEV/idVendor" 2>/dev/null) != 0403 ]] ||
       [[ $(cat "$USB_DEV/idProduct" 2>/dev/null) != 6010 ]]; then
        printf 'Serial %s is not an FK33-compatible 0403:6010 device\n' \
            "$SERIAL" >&2
        exit 1
    fi

    for INTERFACE in "$USB_DEV":1.*; do
        [[ -d "$INTERFACE" ]] || continue

        DRIVER=unbound
        if [[ -L "$INTERFACE/driver" ]]; then
            DRIVER=$(basename "$(readlink -f "$INTERFACE/driver")")
        fi

        case "$DRIVER" in
            unbound)
                ;;
            ftdi_sio)
                basename "$INTERFACE" |
                    /usr/bin/sudo -n /usr/bin/tee \
                        /sys/bus/usb/drivers/ftdi_sio/unbind \
                        >/dev/null
                ;;
            *)
                printf '%s uses unexpected driver %s\n' \
                    "$(basename "$INTERFACE")" "$DRIVER" >&2
                exit 1
                ;;
        esac
    done

    BUSNUM=$(cat "$USB_DEV/busnum")
    DEVNUM=$(cat "$USB_DEV/devnum")
    USB_NODE=$(printf '/dev/bus/usb/%03d/%03d' "$BUSNUM" "$DEVNUM")

    if [[ ! -r "$USB_NODE" || ! -w "$USB_NODE" ]]; then
        printf 'No read/write access to FK33 serial %s at %s. ' \
            "$SERIAL" "$USB_NODE" >&2
        printf 'Install the generated udev rule with install.sh --install-udev.\n' \
            >&2
        exit 1
    fi
done

sleep 1

for SERIAL in "${SERIALS[@]}"; do
    SERIAL_FILE=$(grep -l "^${SERIAL}$" \
        /sys/bus/usb/devices/*/serial)
    USB_DEV=${SERIAL_FILE%/serial}

    for INTERFACE in "$USB_DEV":1.*; do
        [[ -d "$INTERFACE" ]] || continue

        if [[ -L "$INTERFACE/driver" ]]; then
            printf '%s remains bound to %s\n' \
                "$(basename "$INTERFACE")" \
                "$(basename "$(readlink -f "$INTERFACE/driver")")" >&2
            exit 1
        fi
    done
done

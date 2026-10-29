#!/bin/bash
# Build Keychron B1 Pro firmware: board `keychron` + shield `keychron_b1_us`.
# Commands taken from the space-fn branch README ("how to build").
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
KEYBOARD_ID="blue"

usage() {
    echo "Usage: $0 [--id ID|-i ID]" >&2
    echo "Example: $0 --id red" >&2
}

while (($# > 0)); do
    case "$1" in
        --id|-i)
            if (($# < 2)); then
                usage
                exit 2
            fi
            KEYBOARD_ID="$2"
            shift 2
            ;;
        --id=*)
            KEYBOARD_ID="${1#*=}"
            shift
            ;;
        --help|-h)
            usage
            exit 0
            ;;
        *)
            usage
            exit 2
            ;;
    esac
done

if [[ ! "$KEYBOARD_ID" =~ ^[[:alnum:]_-]+$ ]]; then
    echo "Invalid keyboard ID: '$KEYBOARD_ID'" >&2
    echo "Use only letters, numbers, '_' and '-'." >&2
    exit 2
fi

CONFIG_FILE="$SCRIPT_DIR/app/boards/shields/keychron/b1/us/keychron_b1_us.conf"
CONFIG_BACKUP="$(mktemp)"

restore_config() {
    cp "$CONFIG_BACKUP" "$CONFIG_FILE"
    rm -f "$CONFIG_BACKUP"
}

trap restore_config EXIT INT TERM HUP
cp "$CONFIG_FILE" "$CONFIG_BACKUP"

if [[ "$KEYBOARD_ID" != "blue" ]]; then
    # The configuration is restored by the EXIT trap after the build, including
    # when west or the copy step fails.
    sed -E -i \
        -e "s|^(CONFIG_KEYCHRON_B1_COLOR=).*|\\1\"$KEYBOARD_ID\"|" \
        -e "s|^(CONFIG_USB_DEVICE_PRODUCT=)\"b1-[^\"]+-usb\"|\\1\"b1-$KEYBOARD_ID-usb\"|" \
        -e "s|^(CONFIG_BT_DIS_MODEL=)\"b1-[^\"]+\"|\\1\"b1-$KEYBOARD_ID\"|" \
        -e "s|^(CONFIG_ZMK_KEYBOARD_NAME=)\"b1-[^\"]+\"|\\1\"b1-$KEYBOARD_ID\"|" \
        "$CONFIG_FILE"
fi

cd "$SCRIPT_DIR/app"
export ZEPHYR_TOOLCHAIN_VARIANT=zephyr
export ZEPHYR_SDK_INSTALL_DIR="$HOME/.opt/zephyr-sdk-0.17.4"

west build -b keychron -p always -- -DSHIELD=keychron_b1_us
BRANCH_NAME="$(git branch --show-current)"
cp ./build/zephyr/zmk.uf2 "$HOME/Downloads/b1_${BRANCH_NAME}_${KEYBOARD_ID}.uf2"

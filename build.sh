#!/bin/bash
# Build Keychron B1 Pro firmware: board `keychron` + shield `keychron_b1_us`.
# Commands taken from the space-fn branch README ("how to build").
#
# Matrix revision:
#   default 2023  -> original matrix wiring
#   --matrix 2025 -> 2025 revision matrix wiring
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
KEYBOARD_ID="blue"
MATRIX_REV="2023"

usage() {
    echo "Usage: $0 [--id ID|-i ID] [--matrix REV|-m REV] [--rev REV] [--new-matrix]" >&2
    echo "  --id/-i ID        keyboard ID (default: blue)" >&2
    echo "  --matrix/-m/--rev matrix revision: 2023 or 2025 (default: 2023)" >&2
    echo "  --new-matrix      shorthand for --matrix 2025" >&2
    echo "Example: $0 --id red --matrix 2025" >&2
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
        --matrix|-m|--rev)
            if (($# < 2)); then
                usage
                exit 2
            fi
            MATRIX_REV="$2"
            shift 2
            ;;
        --matrix=*|--rev=*)
            MATRIX_REV="${1#*=}"
            shift
            ;;
        --new-matrix)
            MATRIX_REV="2025"
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

case "$MATRIX_REV" in
    2023|2025)
        ;;
    *)
        echo "Invalid matrix revision: '$MATRIX_REV'" >&2
        echo "Allowed values: 2023, 2025" >&2
        exit 2
        ;;
esac

CONFIG_FILE="$SCRIPT_DIR/app/boards/shields/keychron/b1/us/keychron_b1_us.conf"
OVERLAY_FILE="$SCRIPT_DIR/app/boards/shields/keychron/b1/us/keychron_b1_us.overlay"
CONFIG_BACKUP="$(mktemp)"
OVERLAY_BACKUP="$(mktemp)"

restore_all() {
    cp "$CONFIG_BACKUP" "$CONFIG_FILE"
    cp "$OVERLAY_BACKUP" "$OVERLAY_FILE"
    rm -f "$CONFIG_BACKUP"
    rm -f "$OVERLAY_BACKUP"
}

trap restore_all EXIT INT TERM HUP
cp "$CONFIG_FILE" "$CONFIG_BACKUP"
cp "$OVERLAY_FILE" "$OVERLAY_BACKUP"

if [[ "$KEYBOARD_ID" != "blue" ]]; then
    sed -E -i \
        -e "s|^(CONFIG_KEYCHRON_B1_COLOR=).*|\\1\"$KEYBOARD_ID\"|" \
        -e "s|^(CONFIG_USB_DEVICE_PRODUCT=)\"b1-[^\"]+-usb\"|\\1\"b1-$KEYBOARD_ID-usb\"|" \
        -e "s|^(CONFIG_BT_DIS_MODEL=)\"b1-[^\"]+\"|\\1\"b1-$KEYBOARD_ID\"|" \
        -e "s|^(CONFIG_ZMK_KEYBOARD_NAME=)\"b1-[^\"]+\"|\\1\"b1-$KEYBOARD_ID\"|" \
        "$CONFIG_FILE"
fi

if [[ "$MATRIX_REV" == "2025" ]]; then
    python3 - "$OVERLAY_FILE" <<'PY'
import re
import sys

path = sys.argv[1]
matrix_2025 = [
    (7, 5), (1, 2), (3, 4), (1, 14), (1, 4), (2, 2), (4, 2), (2, 5),
    (2, 6), (2, 7), (2, 10), (2, 8), (3, 7), (5, 8),
    (0, 17), (1, 0), (1, 15), (1, 1), (3, 6), (1, 12), (1, 13), (5, 5),
    (5, 6), (5, 7), (5, 10), (1, 6), (1, 7), (1, 8),
    (0, 5), (0, 10), (0, 8), (0, 9), (0, 13), (0, 14), (3, 5), (3, 1),
    (1, 3), (2, 4), (1, 11), (4, 6), (4, 7), (4, 10),
    (5, 17), (0, 4), (0, 6), (0, 7), (0, 2), (1, 17), (6, 8), (1, 10),
    (3, 2), (1, 9), (6, 5), (6, 7), (2, 1),
    (0, 16), (0, 0), (0, 15), (0, 1), (0, 12), (0, 11), (7, 6), (7, 11),
    (7, 10), (7, 8), (7, 9), (5, 15),
    (1, 5), (3, 10), (6, 17), (0, 3), (4, 0), (2, 9), (3, 17), (2, 17),
    (4, 17), (7, 17),
    (8, 0), (8, 1), (8, 2), (8, 3), (8, 4),
]

with open(path, encoding="utf-8") as f:
    text = f.read()

state = {"idx": 0}

def repl(match):
    idx = state["idx"]
    if idx >= len(matrix_2025):
        return match.group(0)
    row, col = matrix_2025[idx]
    state["idx"] += 1
    return "RC({}, {})".format(row, col)

patched = re.sub(r"RC\(\s*\d+\s*,\s*\d+\s*\)", repl, text, count=len(matrix_2025))
if state["idx"] != len(matrix_2025):
    raise SystemExit(
        "matrix 2025 patch failed: expected {} RC entries, patched {}"
        .format(len(matrix_2025), state["idx"])
    )

with open(path, "w", encoding="utf-8") as f:
    f.write(patched)
PY
fi

cd "$SCRIPT_DIR/app"
export ZEPHYR_TOOLCHAIN_VARIANT=zephyr
export ZEPHYR_SDK_INSTALL_DIR="$HOME/.opt/zephyr-sdk-0.17.4"

west build -b keychron -p always -- -DSHIELD=keychron_b1_us

BRANCH_NAME="$(git branch --show-current)"
if [[ "$MATRIX_REV" == "2025" ]]; then
    UF2_NAME="b1_${BRANCH_NAME}_2025_${KEYBOARD_ID}.uf2"
else
    UF2_NAME="b1_${BRANCH_NAME}_${KEYBOARD_ID}.uf2"
fi
cp ./build/zephyr/zmk.uf2 "$HOME/Downloads/$UF2_NAME"

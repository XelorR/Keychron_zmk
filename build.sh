#!/bin/bash
# Build Keychron B1 Pro firmware: board `keychron` + shield `keychron_b1_us`.
# Commands taken from the space-fn branch README ("how to build").
set -e
cd "$(dirname "$0")"

cd app
export ZEPHYR_TOOLCHAIN_VARIANT=zephyr
export ZEPHYR_SDK_INSTALL_DIR="$HOME/.opt/zephyr-sdk-0.17.4"

west build -b keychron -p always -- -DSHIELD=keychron_b1_us
cp ./build/zephyr/zmk.uf2 ~/Downloads/b1_$(git branch --show-current).uf2

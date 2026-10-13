# Zephyr™ Mechanical Keyboard (ZMK) Firmware

[![Discord](https://img.shields.io/discord/719497620560543766)](https://zmk.dev/community/discord/invite)
[![Build](https://github.com/zmkfirmware/zmk/workflows/Build/badge.svg)](https://github.com/zmkfirmware/zmk/actions)
[![Contributor Covenant](https://img.shields.io/badge/Contributor%20Covenant-v2.0%20adopted-ff69b4.svg)](CODE_OF_CONDUCT.md)

[ZMK Firmware](https://zmk.dev/) is an open source ([MIT](LICENSE)) keyboard firmware built on the [Zephyr™ Project](https://www.zephyrproject.org/) Real Time Operating System (RTOS). ZMK's goal is to provide a modern, wireless, and powerful firmware free of licensing issues.

Check out the website to learn more: https://zmk.dev/.

You can also come join our [ZMK Discord Server](https://zmk.dev/community/discord/invite).

To review features, check out the [feature overview](https://zmk.dev/docs/). ZMK is under active development, and new features are listed with the [enhancement label](https://github.com/zmkfirmware/zmk/issues?q=is%3Aissue+is%3Aopen+label%3Aenhancement) in GitHub. Please feel free to add 👍 to the issue description of any requests to upvote the feature.

[Keychron](https://keychron.com/) use zmk source code for Bpro series keyboards ,have made big changes fro Bpro, also add proprietary 2.4g communication.

To build the firmware ,for example: keychorn b1 pro

install prerequisites:

- wget
- cmake
- ninja
- `pipx install west`
- `pipx inject west pyelftools`

install SDK:
```bash
mkdir -p ~/.opt && cd ~/.opt && \
wget https://github.com/zephyrproject-rtos/sdk-ng/releases/download/v0.17.4/zephyr-sdk-0.17.4_linux-x86_64.tar.xz && \
tar xf zephyr-sdk-0.17.4_linux-x86_64.tar.xz && \
cd zephyr-sdk-0.17.4 && \
./setup.sh -t all -h -c
```

prepare:
```bash
git clone -b keychron_bpro https://github.com/keychron/zmk.git Keychron_ZMK
cd Keychron_ZMK
west init -l app/
west update
```
patch zephyr:
```bash
cd zephyr
git am ../0001-esb-nrf-fix.patch
```
build firmware:
```bash
cd app
west build -b keychron -p -- -DSHIELD=keychron_b1_us
cp ./build/zephyr/zmk.uf2 ~/Downloads/b1_$(git branch --show-current).uf2
```

flash compiled firmware from ./app/build/zephyr/ folder

## maclike-win-max: Windows layout with macOS behavior (Keychron B1 Pro US)

Branch [`maclike-win-max`](https://github.com/XelorR/Keychron_zmk/tree/maclike-win-max)
— the familiar Windows base with mac-style shortcuts. All changes are
win-layer only, Mac layers stay factory.

- Keymap: [`app/boards/shields/keychron/b1/us/keychron_b1_us.keymap`](app/boards/shields/keychron/b1/us/keychron_b1_us.keymap)
- Full feature list: [`app/boards/shields/keychron/b1/us/README.md`](app/boards/shields/keychron/b1/us/README.md)
- Build: `./build.sh` (board `keychron` + shield `keychron_b1_us`)

Highlights: bottom-row remap (Caps→Ctrl, Alt keys→RCtrl "command" key);
`RCtrl+Tab` / `Shift+Tab` window cycling with hold; `RCtrl+Q` closes window;
`LGUI+RCtrl+Q` locks; `RCtrl+Shift+3/4` screenshots; `RCtrl+C/V` copy/paste;
`RCtrl+[`/`]` browser nav, `+Shift` tab switching; `RCtrl+arrows` Home/End,
`+Up/Down` doc start/end; `LAlt+arrows` word jump, `LAlt+BSPC/Del` word
delete; `RCtrl+BSPC/Del` delete to line start/end; Caps-Ctrl + `N/P/F/B/G/H/A/E`
mac-style nav; `RCtrl+Space` window menu; `Fn+Esc` bootloader.

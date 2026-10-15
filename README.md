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

Bottom-row remap: Caps→LCtrl, LCtrl→Win, LGUI→Alt, both Alt keys→RCtrl
(the "command" key). `Fn+Esc` enters the UF2 bootloader.

| Shortcut | Action | macOS equivalent |
|---|---|---|
| `RCtrl+Tab` / `RCtrl+Shift+Tab` | Next / previous window (hold RCtrl keeps the switcher open) | `Cmd+Tab` / `Cmd+Shift+Tab` |
| `LAlt+Tab` | Stock native Alt+Tab (untouched) | — (Windows-only, no macOS equivalent) |
| `RCtrl+Q` | `Alt+F4` (close window) | `Cmd+Q` |
| `LGUI+RCtrl+Q` | `Win+L` (lock screen) | `Ctrl+Cmd+Q` |
| `RCtrl+Space` | `Alt+Space` → application launcher (on Windows use PowerToys Run — `Alt+Space` is its default shortcut) | `Cmd+Space` |
| `LGUI+Space` | native `Win+Space` → input language switch | `Ctrl+Space` (input sources) |
| `RCtrl+Shift+3` | `PrintScreen` | `Cmd+Shift+3` |
| `RCtrl+Shift+4` | `Win+Shift+S` (snipping tool) | `Cmd+Shift+4` |
| `RCtrl+C` / `RCtrl+V` | Copy (`Ctrl+Ins`) / paste (`Shift+Ins`) | `Cmd+C` / `Cmd+V` |
| `RCtrl+[` / `RCtrl+]` | Browser back / forward | `Cmd+[` / `Cmd+]` |
| `RCtrl+Shift+[` / `RCtrl+Shift+]` | Previous / next browser tab | `Cmd+Shift+[` / `Cmd+Shift+]` |
| `RCtrl+Left` / `RCtrl+Right` | `Home` / `End` | `Cmd+Left` / `Cmd+Right` |
| `RCtrl+Up` / `RCtrl+Down` | `Ctrl+Home` / `Ctrl+End` (doc start / end) | `Cmd+Up` / `Cmd+Down` |
| `LAlt+Left` / `LAlt+Right` | Word jump left / right | `Option+Left` / `Option+Right` |
| `LAlt+BSPC` / `LAlt+Del` | Delete word backward / forward | `Option+Backspace` / forward word delete |
| `RCtrl+BSPC` / `RCtrl+Del` | Delete to line start / line end | `Cmd+Backspace` / `Cmd-Del` |
| CapsCtrl + `N` | `Down` | `Ctrl+N` |
| CapsCtrl + `P` | `Up` | `Ctrl+P` |
| CapsCtrl + `F` | `Right` | `Ctrl+F` |
| CapsCtrl + `B` | `Left` | `Ctrl+B` |
| CapsCtrl + `D` | `Del` (forward delete) | `Ctrl+D` |
| CapsCtrl + `H` | `Backspace` | `Ctrl+H` |
| CapsCtrl + `A` | `Home` | `Ctrl+A` |
| CapsCtrl + `E` | `End` | `Ctrl+E` |
| CapsCtrl + `K` | Kill line (`Shift+Home`, `Ctrl+X`) | `Ctrl+K` |
| CapsCtrl + `Y` | Paste (`Shift+Ins`) | `Ctrl+Y` |
| CapsCtrl + `O` | New line below (`End`, `Shift+Enter`) | `Ctrl+O` |

Detailed behavior specification for porting to Kanata / Xremap / QMK /
RMK / ZMK (logic, trigger tables, switcher hold machine):
[`MACLIKE.md`](MACLIKE.md).

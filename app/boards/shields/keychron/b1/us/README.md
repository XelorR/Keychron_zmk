# Keychron B1 Pro US — maclike Windows layout (`keychron_b1_us`)

Windows base with macOS-style shortcuts. **All changes are win-layer only**
(`layer_two`/`layer_three`); the Mac layers are factory.

Build: `./build.sh` from repo root (board `keychron` + shield
`keychron_b1_us`), flash the resulting `~/Downloads/b1-*.uf2`.

## Bottom row remap (win)

| Physical key | Sends |
|---|---|
| Caps | Left Ctrl |
| Left Ctrl | Left GUI (Win) |
| Left GUI | Left Alt |
| Left/Right Alt | Right Ctrl (the "command" key) |

## Window switching

- `RCtrl+Tab` / `RCtrl+Shift+Tab` — next/previous window, cyclic. Holding
  Right Ctrl keeps the switcher open across taps; releasing it commits.
  Implemented by the custom `win_tab` behavior (no timers): Right Alt is
  asserted for the session only, the Right Ctrl mask lives around the tap,
  so `RCtrl+letters` stay native everywhere else.
- `LAlt+Tab` — stock native Alt+Tab (untouched).
- `RCtrl+Q` — `Alt+F4` (close window).
- `LGUI+RCtrl+Q` — `Win+L` (lock screen).
- `RCtrl+Space` — `Alt+Space` (application launcher; on Windows use PowerToys Run, `Alt+Space` is its default).
- `LGUI+Space` — native `Win+Space`, switches input language (mac-like position of `Ctrl+Space`).

## Navigation & editing (win)

- `RCtrl+[` / `]` — `Alt+Left` / `Alt+Right` (back/forward).
- `RCtrl+Shift+[` / `]` — `Ctrl+PgUp` / `Ctrl+PgDn` (prev/next tab).
- `RCtrl+C` — `Ctrl+Ins` (copy), `RCtrl+V` — `Shift+Ins` (paste).
- `RCtrl+←/→` — `Home` / `End`.
- `RCtrl+↑/↓` — `Ctrl+Home` / `Ctrl+End`.
- `LAlt+←/→` — `Ctrl+←/→` (word jump).
- `LAlt+BSPC/Del` — `Ctrl+BSPC/Del` (delete word back/forward).
- В Outlook/Office Alt уводит фокус в ленту, поэтому там слова — через CapsCtrl+стрелки/BSPC (чистый Ctrl без Alt, работает везде).
- `RCtrl+BSPC` — select to line start + delete; `RCtrl+Del` — select to
  line end + delete (macros).
- `RCtrl+Shift+3` — `PrintScreen`.
- `RCtrl+Shift+4` — `Win+Shift+S` (snipping tool).
- Caps-Ctrl (the ex-CapsLock key) + `N/P/F/B/D/H/A/E` — `Down/Up/Right/
  Left/Delete/Backspace/Home/End`, `K` — kill line (`Shift+Home`, `Ctrl+X`), `Y` — paste (`Shift+Ins`), `O` — new line below (`End`, `Shift+Enter`), `Shift+O` — new line above (`Home`, `Shift+Enter`, `Up`) (macOS style). Plain Ctrl
  combos for all other keys are native.

## Misc

- `Fn+Esc` — UF2 bootloader.
- The `hid.c` masked-modifiers accumulation one-liner is what makes nested
  mod-morphs (Alt+Shift cases) mask both mods; single morphs unaffected.

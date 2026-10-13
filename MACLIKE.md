# Maclike-Win: full behavior specification

This document precisely describes a mac-like keyboard layout for Windows,
with enough detail to **reimplement it anywhere**: software remappers
(Kanata, Xremap) or firmware (QMK, RMK, ZMK). It is not tied to any API —
only logic: what is held physically, what goes into the HID report, and when.
Reference ZMK implementation: branch `maclike-win-max`, keymap
[`app/boards/shields/keychron/b1/us/keychron_b1_us.keymap`](app/boards/shields/keychron/b1/us/keychron_b1_us.keymap).

Target keyboard is ANSI US (Keychron B1 Pro), but the spec is portable: all
it needs is `[` `]` `Q` `Space` `3` `4` `C` `V` `BSPC` `Del` `Tab`, arrows,
`N/P/F/B/G/H/A/E`, and left/right Ctrl/Alt/Win/Shift modifiers.

## 1. Model

### 1.1. Bottom row and Caps (win layer; Mac layers are factory, untouched)

| Physical key | Scancode sent |
|---|---|
| CapsLock | Left Ctrl (the "Ctrl for emacs bindings", §3.8) |
| ex-Left Ctrl | Left GUI / Win |
| ex-Left GUI | Left Alt |
| ex-Left Alt **and** ex-Right Alt | Right Ctrl (the "command" key of the whole scheme) |
| Fn | Fn layer (momentary), `Fn+Esc` — bootloader |

Everything below is about the **win layer**. Names like "LALT"/"RCTRL" refer
to scancodes, not to keycap labels.

### 1.2. Three kinds of key behavior

1. **Native** — the key goes into the HID report as-is (with held modifiers). Everything
   not listed below works this way: letters, digits, `Shift+3` → `#`,
   `Ctrl+3`, bare arrows, etc.
2. **Mod-morph** — on press, the held mods are checked; on match, something
   else is sent instead (a code and/or mods), and the matched mod is
   **masked** (removed from the report while held).
3. **Macro** — a tap sequence: `Shift+Home`, release, `Backspace`.

### 1.3. HID report

`report = (explicit − masked) + implicit`, where `explicit` = physically
held mods (refcounted: one press = +1, release = −1, the bit clears at
zero), `implicit` = mods from the key definition (live only while the key
is held), `masked` = temporarily suppressed. The morph trigger is evaluated
**at press time** against `explicit`.

Transport-agnostic: identical over wired USB and BLE — ZMK composes
the same HID report either way, only the endpoint differs.

### 1.4. Shift leak-through

If the morph trigger is not Shift (e.g. RCtrl) but Shift is also held, Shift
is **not** masked and leaks into the output. This is a feature, not a bug:
`RCtrl+Shift+Tab` → `Alt+Shift+Tab`, `RCtrl+Shift+Left` → `Shift+Home`.
Exception — where Shift is part of the trigger (§3.3, §3.4): there it is
masked.

## 2. Behavior table (win layer)

The "Output" column is what the OS sees: held mods minus the mask.

| # | Held + key | HID report | Note |
|---|---|---|---|
| 2.1 | `RCtrl+Tab` | `Alt+Tab` (RCtrl masked) | Forward through windows |
| 2.2 | `RCtrl+Shift+Tab` | `Alt+Shift+Tab` | Backward (Shift leaks through) |
| 2.3 | `LAlt+Tab` | default: bare Tab under held Alt | Native OS hold |
| 2.4 | `RCtrl+Q` | `Alt+F4` | Close window |
| 2.5 | `Win+RCtrl+Q` | `Win+L` | Lock (nested morph) |
| 2.6 | `RCtrl+Space` | `Alt+Space` | Window menu |
| 2.7 | `RCtrl+Shift+3` | `PrintScreen` (bare, mods eaten) | Both mods masked |
| 2.8 | `RCtrl+Shift+4` | `Win+Shift+S` | Both mods masked |
| 2.9 | `RCtrl+C` | `Ctrl+Ins` (copy) | RCtrl masked |
| 2.10 | `RCtrl+V` | `Shift+Ins` (paste) | RCtrl masked |
| 2.11 | `RCtrl+[` / `]` | `Alt+Left` / `Alt+Right` | Back/forward |
| 2.12 | `RCtrl+Shift+[` / `]` | `Ctrl+PgUp` / `Ctrl+PgDn` | Browser tabs (nested morph, both mods masked) |
| 2.13 | `RCtrl+Left/Right` | `Home` / `End` | |
| 2.14 | `RCtrl+Up/Down` | `Ctrl+Home` / `Ctrl+End` | |
| 2.15 | `LAlt+Left/Right` | `Ctrl+Left/Right` | Word jump (LAlt masked) |
| 2.16 | `LAlt+BSPC/Del` | `Ctrl+BSPC/Del` | Delete word backward/forward |
| 2.17 | `RCtrl+BSPC` | tap `Shift+Home`, tap `BSPC` | To line start |
| 2.18 | `RCtrl+Del` | tap `Shift+End`, tap `Del` | To line end |
| 2.19 | CapsCtrl + `N/P/F/B/D/H/A/E` | `Down/Up/Right/Left/Del/BSPC/Home/End` | Left Ctrl only; RCtrl+N etc. stay native |
| 2.19b | CapsCtrl+K | tap `Shift+Home`, tap `Ctrl+X` (kill line) |
| 2.19c | CapsCtrl+Y | `Shift+Ins` (paste) |
| 2.19d | CapsCtrl+O | tap `End`, tap `Shift+Enter` (open line below) |
| 2.20 | `Fn+Esc` | bootloader (UF2) | |
| 2.21 | everything else | native | Including `Shift+3`→`#`, `Ctrl+3/4`, bare arrows, `LAlt+Up/Down` |

Nesting (2.5, 2.12): outer morph on the first mod, inner morph on the
second; masks **accumulate** (see §5.2). A single morph with an `A|B`
trigger does not work: it fires on either one (OR), not on the combination.

## 3. Window switching in detail

### 3.1. Per-tap cycling (base, works everywhere)

No hold needed: each `RCtrl+Tab` tap is one step forward,
`RCtrl+Shift+Tab` one step back (per-tap commit is stock OS behavior for a
quick Alt+Tab). Implemented with a single morph, no code.

### 3.2. Switcher hold (extension)

Requirement: hold Right Ctrl → tap Tab (cycle without commit) → release
Right Ctrl → commit. Not achievable with stock primitives: between taps no
key is pressed, yet Alt must stay in the reports; morph triggers are OR and
masks get overwritten. Hence a small event-driven state machine, no timers:

```
Tab press:
  if Right Ctrl held (explicit mods or position tracker, see below) and
  Alt not yet asserted by us: assert Alt
  tap Alt+Tab with Right Ctrl masked; drop the mask right away;
  remember "our tap"
Tab release (if it was our tap): nothing (tap already done)
Right-Ctrl-key release: untrack it;
  if tracker empty and Alt asserted by us: release Alt (= commit), send report
Tab press while our Alt is asserted but nothing is held and no Right Ctrl:
  release the stale Alt (self-healing — a stuck Alt cannot outlive one tap)
```

- The tracker is the set of held Right Ctrl positions from keyboard
  press/release events (not from HID bits: the release moment cannot be
  observed any other way).
- The mask lives only around the synchronous tap; Shift is never masked.
- Reverse-order release (Right Ctrl up first, then Tab) is correct:
  Alt drops on the release event, the tap already ran.
- Holding both Right Ctrl keys, or additionally holding physical Left Alt
  on top, keeps Alt asserted (refcount + tracker) — matching native.

### 3.3. Native path

`LAlt+Tab` is a plain Tab under physical Alt: the OS itself holds the
switcher and commits on Alt release. Firmware is not involved at all.

### 3.4. Why ←/→ don't navigate the native switcher (accepted tradeoff)

`LAlt+arrows` must produce word jump (§2.15): the morph masks LALT, so the
report carries the arrow with **no Alt bit at all** — the OS reads that as
"Alt released" and commits the switcher. One and the same physical hold
cannot mean both "words" and "navigation" without stateful code. In the
RCtrl switcher (§3.2), ↑/↓ navigate for free (`Alt+Up/Down` conflicts with
nothing).

## 4. "Physics → HID report" matrix (porting cheat sheet)

| Physically held | Plus key | Report contains |
|---|---|---|
| RCtrl | Tab (tap) | `Alt+Tab`, RCtrl hidden by mask |
| RCtrl (held) | — (pause) | RCtrl + our Alt |
| RCtrl | letter | native `Ctrl+letter` (+ our Alt if switcher open — same as native) |
| RCtrl + Shift | Tab | `Alt+Shift+Tab` |
| RCtrl + Shift | 3 / 4 | `PrintScreen` / `Win+Shift+S` (everything eaten) |
| LAlt | arrows / BSPC / Del | `Ctrl+…` (LAlt eaten) |
| LAlt | Tab | native `Alt+Tab` |
| CapsCtrl | §2.19 letters | bare nav codes (Ctrl eaten) |
| Win + RCtrl | Q | `Win+L` (both eaten) |

## 5. Porting per platform

General checklist: 1) bottom-row remap (§1.1); 2) single morphs with
trigger masking (§2 except nested); 3) nested morphs with accumulating
masks (2.5, 2.12); 4) tap macros (2.17, 2.18); 5) switcher hold (§3.2) —
or native-only path.

- **Kanata**: bottom row via `defsrc`/`deflayer` remap; single morphs via
  the `fork` action (branch on held mods); nested via `fork` inside `fork`;
  macros via `macro`; hold without timers — physical Alt only (native
  path), or a layer held by a separate key where Tab/arrows are `A-tab` /
  `A-left` (layer release = commit). Timing-based tap-holds are not needed
  for this scheme and are out of scope.
- **Xremap**: `modmap` for the row; `keymap` accepts modifier combos as
  keys out of the box, including split `Ctrl_R-*` (e.g. `Ctrl_R-C: End`);
  extra modifiers leak through automatically (the §1.4 analog),
  exact matching via `exact_match: true`. Tap macros as arrays like
  `[Shift-Home, BackSpace]`. Hold — native path; custom hold needs an
  external daemon.
- **QMK**: remap via keymap keycodes; single and nested morphs via Key
  Overrides (`ko_make_basic`, trigger/suppressed mods,
  `KEY_OVERRIDE_ENABLE`); macros via `SEND_STRING` taps; switcher hold via
  a small `process_record_user` state machine from §3.2 (raise Alt on
  Tab-under-mod, drop it on mod release; no timers).
- **RMK**: TOML keymap + combos/macros/tap-holds for the single-morph
  cases; check the current release for nested and hold support (the API
  moves fast) — the contract is tables §2–§4 above.
- **ZMK**: the reference lives here — `zmk,behavior-mod-morph` (+nesting),
  `ZMK_MACRO` taps; subtlety: nested morph masks must **accumulate**
  (`masked_modifiers |=`, not `=`); hold —
  `app/src/behaviors/behavior_win_tab.c` as an event-machine template;
  in DTS you cannot use `RC(x)` for implicit Ctrl — it collides with the
  overlay's row/col macro, use `LC(x)` (side is indistinguishable for
  Ctrl+digit); always distinguish L/R mod variants (`MOD_RCTL` is not
  triggered by LCTL).

## 6. Gotchas

1. A mask erases the bit from the report: the OS sees "mod released". A
   morph masking Alt under a held Alt closes the switcher (see §3.4).
2. `implicit` lives only while its carrier key is down; `explicit` is
   refcounted; `masked` must be cleared symmetrically (or mods leak/stick).
3. The trigger fires at press time; release order is arbitrary — any hold
   protocol must survive both.
4. L/R mod variants are different bits; match exactly yours.
5. Shift leaks through foreign triggers — design outputs with that in mind
   (§1.4), don't fight it.
6. Lost scan events = stuck states: any hold protocol needs self-healing
   (§3.2, last item).

## 7. Acceptance (checklist)

- `RCtrl+Tab` / `+Shift` taps step forward/back; hold RCtrl + tap series
  without commit; release RCtrl commits the highlighted window.
- Quick tap = one step. `LAlt+Tab` native (hold / ↑↓ arrows / commit).
- `RCtrl+T/C/V`, `Ctrl+3/4`, `#`, `$`, bare Tab, bare arrows — native.
- Words/lines/Home-End/Q/Space/Win+L/screenshots/emacs — per table §2.
- Nothing extra while RCtrl held: `RCtrl+Tab` must not open the sticky
  switcher (a sign of Ctrl leaking into the tap); a bare RCtrl tap must not
  focus menus.

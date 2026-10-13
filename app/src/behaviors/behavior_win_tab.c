/*
 * Win-Tab switcher hold behavior (win layer only).
 *
 * Tab pressed while Right Ctrl is held (explicit mods or tracked hold
 * positions): assert Right Alt explicitly across the whole hold (no physical
 * key sends it; refcounted, so a physically held Alt is never lost) and tap
 * Left-Alt+Tab with Right Ctrl masked. The Left Alt in the tap is what opens
 * the switcher on every layout; the mask lives only around the synchronous
 * tap, keeping Right Ctrl native for Command-letter shortcuts at all other
 * times. The asserted Right Alt is released only when every tracked hold
 * position is up, so holding Right Ctrl keeps the OS window switcher open
 * across Tab taps (Shift composes naturally: Alt+Shift+Tab); releasing the
 * key commits the selection.
 *
 * Left Alt + Tab stays fully default/native and is intentionally not
 * tracked here.
 *
 * No timers, no hold-taps, no mod-taps.
 *
 * Copyright (c) 2026 The ZMK Contributors
 *
 * SPDX-License-Identifier: MIT
 */

#define DT_DRV_COMPAT zmk_behavior_win_tab

#include <zephyr/device.h>
#include <drivers/behavior.h>
#include <zephyr/logging/log.h>
#include <zmk/behavior.h>
#include <zmk/event_manager.h>
#include <zmk/events/position_state_changed.h>
#include <zmk/events/keycode_state_changed.h>
#include <zmk/hid.h>
#include <zmk/endpoints.h>
#include <dt-bindings/zmk/keys.h>
#include <dt-bindings/zmk/hid_usage.h>
#include <dt-bindings/zmk/hid_usage_pages.h>
#include <dt-bindings/zmk/modifiers.h>

LOG_MODULE_DECLARE(zmk, CONFIG_ZMK_LOG_LEVEL);

#define WIN_TAB_ALT_ID HID_USAGE_KEY_KEYBOARD_RIGHTALT
#define WIN_TAB_MAX_TRACKED 8

struct behavior_win_tab_data {
    bool alt_held;
    bool tab_is_ours;
    uint32_t held[WIN_TAB_MAX_TRACKED];
    uint8_t held_count;
};

#define _WIN_TAB_HOLD_CMP(node_id, prop, idx)                                                  \
    if (position == DT_PROP_BY_IDX(node_id, prop, idx)) {                                      \
        return true;                                                                           \
    }

/* Single instance design: the hold positions come from DT_DRV_INST(0). */
static bool win_tab_pos_is_hold(uint32_t position) {
    DT_FOREACH_PROP_ELEM(DT_DRV_INST(0), hold_positions, _WIN_TAB_HOLD_CMP)
    return false;
}

static struct behavior_win_tab_data *win_tab_data(void) {
    const struct device *dev = DEVICE_DT_GET(DT_DRV_INST(0));
    return (struct behavior_win_tab_data *)dev->data;
}

static void win_tab_release_alt(struct behavior_win_tab_data *data) {
    if (!data->alt_held) {
        return;
    }
    data->alt_held = false;
    zmk_hid_keyboard_release(WIN_TAB_ALT_ID);
    zmk_endpoints_send_report(HID_USAGE_KEY);
}

static int on_win_tab_pressed(struct zmk_behavior_binding *binding,
                              struct zmk_behavior_binding_event event) {
    struct behavior_win_tab_data *data = win_tab_data();

    if (!((zmk_hid_get_explicit_mods() & MOD_RCTL) || data->held_count > 0)) {
        data->tab_is_ours = false;
        return ZMK_EVENT_RAISE(
            zmk_keycode_state_changed_from_encoded(TAB, true, event.timestamp));
    }

    /* Switcher path: hold Right Alt across the whole hold, tap Left-Alt+Tab
     * with Right Ctrl masked. */
    if (!data->alt_held) {
        data->alt_held = true;
        zmk_hid_keyboard_press(WIN_TAB_ALT_ID);
        zmk_endpoints_send_report(HID_USAGE_KEY);
    }
    data->tab_is_ours = true;
    zmk_hid_masked_modifiers_set(MOD_RCTL);
    ZMK_EVENT_RAISE(zmk_keycode_state_changed_from_encoded(LA(TAB), true, event.timestamp));
    ZMK_EVENT_RAISE(zmk_keycode_state_changed_from_encoded(LA(TAB), false, event.timestamp));
    zmk_hid_masked_modifiers_clear();
    return 0;
}

static int on_win_tab_released(struct zmk_behavior_binding *binding,
                               struct zmk_behavior_binding_event event) {
    struct behavior_win_tab_data *data = win_tab_data();

    if (!data->tab_is_ours) {
        return ZMK_EVENT_RAISE(
            zmk_keycode_state_changed_from_encoded(TAB, false, event.timestamp));
    }

    /* The tap already completed on press; Alt lifecycle is owned entirely by
     * the tracked hold positions, so there is nothing to release here. */
    data->tab_is_ours = false;
    return 0;
}

static int win_tab_position_listener(const zmk_event_t *eh) {
    struct zmk_position_state_changed *ev = as_zmk_position_state_changed(eh);
    struct behavior_win_tab_data *data;
    int i;

    if (ev == NULL) {
        return ZMK_EV_EVENT_BUBBLE;
    }

    data = win_tab_data();

    if (ev->state) {
        bool seen = false;
        if (!win_tab_pos_is_hold(ev->position)) {
            return ZMK_EV_EVENT_BUBBLE;
        }
        for (i = 0; i < data->held_count; i++) {
            if (data->held[i] == ev->position) {
                seen = true;
                break;
            }
        }
        if (!seen && data->held_count < WIN_TAB_MAX_TRACKED) {
            data->held[data->held_count++] = ev->position;
        }
    } else {
        for (i = 0; i < data->held_count; i++) {
            if (data->held[i] == ev->position) {
                data->held[i] = data->held[--data->held_count];
                break;
            }
        }
        if (data->held_count == 0 && data->alt_held) {
            win_tab_release_alt(data);
            zmk_endpoints_send_report(HID_USAGE_KEY);
        }
    }
    return ZMK_EV_EVENT_BUBBLE;
}

static const struct behavior_driver_api behavior_win_tab_driver_api = {
    .binding_pressed = on_win_tab_pressed,
    .binding_released = on_win_tab_released,
};

static int behavior_win_tab_init(const struct device *dev) { return 0; }

#define KP_INST(n)                                                                                 \
    static struct behavior_win_tab_data behavior_win_tab_data_##n = {};                            \
    DEVICE_DT_INST_DEFINE(n, behavior_win_tab_init, NULL, &behavior_win_tab_data_##n, NULL,        \
                          APPLICATION, CONFIG_KERNEL_INIT_PRIORITY_DEFAULT,                        \
                          &behavior_win_tab_driver_api);

DT_INST_FOREACH_STATUS_OKAY(KP_INST)

ZMK_LISTENER(win_tab, win_tab_position_listener);
ZMK_SUBSCRIPTION(win_tab, zmk_position_state_changed);

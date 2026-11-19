/*
 * Copyright (c) 2026 The ZMK Contributors
 *
 * SPDX-License-Identifier: MIT
 */

#define DT_DRV_COMPAT zmk_behavior_mouse_jiggler

#include <zephyr/device.h>
#include <zephyr/kernel.h>
#include <zephyr/logging/log.h>
#include <zephyr/sys/atomic.h>

#include <drivers/behavior.h>
#include <zmk/behavior.h>
#include <zmk/event_manager.h>
#include <zmk/events/position_state_changed.h>
#include <zmk/hid.h>
#include <zmk/keymap.h>

#include "../launcher/mousekey.h"

LOG_MODULE_DECLARE(zmk, CONFIG_ZMK_LOG_LEVEL);

#if DT_HAS_COMPAT_STATUS_OKAY(DT_DRV_COMPAT)

#define MOUSE_JIGGLER_POSITION 27
#define MAC_FN_LAYER 1
#define WIN_FN_LAYER 3
#define MAC_NAVI_LAYER 5
#define WIN_NAVI_LAYER 6
#define MOUSE_JIGGLER_INTERVAL_MS 15000

static atomic_t jiggler_running;
static int8_t next_x_delta = 1;

static void mouse_jiggler_work_handler(struct k_work *work);
K_WORK_DELAYABLE_DEFINE(mouse_jiggler_work, mouse_jiggler_work_handler);

static void mouse_jiggler_send_step(void) {
    report_mouse_t report = {
        .report_id = ZMK_HID_REPORT_ID_MOUSE,
        .buttons = 0,
        .x = next_x_delta,
        .y = 0,
        .v = 0,
        .h = 0,
    };

    next_x_delta = -next_x_delta;
    int err = host_mouse_send(&report);
    if (err) {
        LOG_DBG("Mouse jiggler report failed: %d", err);
    }
}

static void mouse_jiggler_start(void) {
    next_x_delta = 1;
    atomic_set(&jiggler_running, 1);
    mouse_jiggler_send_step();
    k_work_reschedule(&mouse_jiggler_work, K_MSEC(MOUSE_JIGGLER_INTERVAL_MS));
    LOG_INF("Mouse jiggler started");
}

static void mouse_jiggler_stop(void) {
    atomic_clear(&jiggler_running);
    k_work_cancel_delayable(&mouse_jiggler_work);
    LOG_INF("Mouse jiggler stopped");
}

static void mouse_jiggler_work_handler(struct k_work *work) {
    if (!atomic_get(&jiggler_running)) {
        return;
    }

    mouse_jiggler_send_step();
    k_work_reschedule(&mouse_jiggler_work, K_MSEC(MOUSE_JIGGLER_INTERVAL_MS));
}

static int on_keymap_binding_pressed(struct zmk_behavior_binding *binding,
                                     struct zmk_behavior_binding_event event) {
    if (atomic_get(&jiggler_running)) {
        mouse_jiggler_stop();
    } else {
        mouse_jiggler_start();
    }

    return ZMK_BEHAVIOR_OPAQUE;
}

static int on_keymap_binding_released(struct zmk_behavior_binding *binding,
                                      struct zmk_behavior_binding_event event) {
    return ZMK_BEHAVIOR_OPAQUE;
}

static const struct behavior_driver_api behavior_mouse_jiggler_driver_api = {
    .binding_pressed = on_keymap_binding_pressed,
    .binding_released = on_keymap_binding_released,
};

static int mouse_jiggler_position_listener(const zmk_event_t *eh) {
    const struct zmk_position_state_changed *ev = as_zmk_position_state_changed(eh);
    if (ev == NULL || !ev->state || !atomic_get(&jiggler_running)) {
        return ZMK_EV_EVENT_BUBBLE;
    }

    /*
     * The trigger is the physical Backspace position (27) on either FN or
     * Navi layer. Its behavior handles the second press as the explicit stop
     * action. At the same physical position on other layers, ordinary key
     * presses should still stop a running jiggler.
     */
    bool is_jiggler_trigger =
        ev->position == MOUSE_JIGGLER_POSITION &&
        (zmk_keymap_layer_active(MAC_FN_LAYER) ||
         zmk_keymap_layer_active(WIN_FN_LAYER) ||
         zmk_keymap_layer_active(MAC_NAVI_LAYER) ||
         zmk_keymap_layer_active(WIN_NAVI_LAYER));

    if (!is_jiggler_trigger) {
        mouse_jiggler_stop();
    }

    return ZMK_EV_EVENT_BUBBLE;
}

ZMK_LISTENER(mouse_jiggler, mouse_jiggler_position_listener);
ZMK_SUBSCRIPTION(mouse_jiggler, zmk_position_state_changed);

static int behavior_mouse_jiggler_init(const struct device *dev) { return 0; }

#define MOUSE_JIGGLER_INST(n)                                                                      \
    DEVICE_DT_INST_DEFINE(n, behavior_mouse_jiggler_init, NULL, NULL, NULL, APPLICATION,           \
                          CONFIG_KERNEL_INIT_PRIORITY_DEFAULT,                                    \
                          &behavior_mouse_jiggler_driver_api);

DT_INST_FOREACH_STATUS_OKAY(MOUSE_JIGGLER_INST)

#endif /* DT_HAS_COMPAT_STATUS_OKAY(DT_DRV_COMPAT) */

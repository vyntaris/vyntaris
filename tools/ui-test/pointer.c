/* pointer X Y WIDTH HEIGHT [click]: moves the pointer of the Wayland session it runs in, and clicks. */
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <wayland-client.h>
#include "virtual-pointer.h"

static struct zwlr_virtual_pointer_manager_v1 *manager;

static void global(void *data, struct wl_registry *registry, uint32_t name, const char *interface, uint32_t version) {
    if (!strcmp(interface, zwlr_virtual_pointer_manager_v1_interface.name))
        manager = wl_registry_bind(registry, name, &zwlr_virtual_pointer_manager_v1_interface, 1);
}
static void global_remove(void *data, struct wl_registry *registry, uint32_t name) {}
static const struct wl_registry_listener listener = { global, global_remove };

static void button(struct wl_display *display, struct zwlr_virtual_pointer_v1 *pointer, uint32_t state) {
    zwlr_virtual_pointer_v1_button(pointer, 2, 0x110, state);
    zwlr_virtual_pointer_v1_frame(pointer);
    wl_display_roundtrip(display);
    usleep(60000);
}

int main(int argc, char **argv) {
    if (argc < 5) return 2;
    struct wl_display *display = wl_display_connect(NULL);
    if (!display) return 1;
    struct wl_registry *registry = wl_display_get_registry(display);
    wl_registry_add_listener(registry, &listener, NULL);
    wl_display_roundtrip(display);
    if (!manager) return 1;
    struct zwlr_virtual_pointer_v1 *pointer = zwlr_virtual_pointer_manager_v1_create_virtual_pointer(manager, NULL);
    zwlr_virtual_pointer_v1_motion_absolute(pointer, 1, atoi(argv[1]), atoi(argv[2]), atoi(argv[3]), atoi(argv[4]));
    zwlr_virtual_pointer_v1_frame(pointer);
    wl_display_roundtrip(display);
    usleep(200000);
    if (argc > 5) {
        button(display, pointer, 1);
        button(display, pointer, 0);
    }
    wl_display_roundtrip(display);
    return 0;
}

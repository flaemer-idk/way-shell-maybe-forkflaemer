#ifndef WAY_SHELL_WP_HELPERS_H
#define WAY_SHELL_WP_HELPERS_H

#include <glib-object.h>

void way_shell_wp_set_volume (GObject *mixer_api, guint32 id, double volume);
void way_shell_wp_set_mute (GObject *mixer_api, guint32 id, gboolean mute);

#endif
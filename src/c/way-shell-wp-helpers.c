#include "way-shell-wp-helpers.h"
#include <glib-object.h>

void way_shell_wp_set_volume (GObject *mixer_api, guint32 id, double volume) {
    if (!mixer_api) return;

    // Создаем GVariant типа var-dict, упаковывая значение громкости double
    GVariantBuilder b;
    g_variant_builder_init (&b, G_VARIANT_TYPE_VARDICT);
    g_variant_builder_add (&b, "{sv}", "volume", g_variant_new_double (volume));
    GVariant *variant = g_variant_builder_end (&b);

    gboolean success = FALSE;
    // Передаем собранный GVariant* третьим параметром
    g_signal_emit_by_name (mixer_api, "set-volume", id, variant, &success);
}

void way_shell_wp_set_mute (GObject *mixer_api, guint32 id, gboolean mute) {
    if (!mixer_api) return;

    // В WirePlumber 0.5 мутирование также происходит через сигнал "set-volume"
    GVariantBuilder b;
    g_variant_builder_init (&b, G_VARIANT_TYPE_VARDICT);
    g_variant_builder_add (&b, "{sv}", "mute", g_variant_new_boolean (mute));
    GVariant *variant = g_variant_builder_end (&b);

    gboolean success = FALSE;
    // Передаем собранный GVariant* третьим параметром
    g_signal_emit_by_name (mixer_api, "set-volume", id, variant, &success);
}
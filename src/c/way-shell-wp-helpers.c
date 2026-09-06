#include "way-shell-wp-helpers.h"
#include <glib-object.h>
#include <wireplumber-0.5/wp/wp.h>

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

/* Устройство (карта), к которому привязан узел с данным node.name.
 * Возвращает без дополнительной ссылки: объект живёт в ObjectManager. */
static WpDevice *find_device_for_node (WpObjectManager *om, const gchar *node_name) {
    if (!om || !node_name) return NULL;

    // Сначала находим узел и берём с него device.id.
    const gchar *device_id = NULL;
    g_autoptr (WpIterator) node_it = wp_object_manager_new_iterator (om);
    GValue val = G_VALUE_INIT;
    while (wp_iterator_next (node_it, &val)) {
        GObject *obj = g_value_get_object (&val);
        if (WP_IS_NODE (obj)) {
            const gchar *name =
                wp_pipewire_object_get_property (WP_PIPEWIRE_OBJECT (obj), "node.name");
            if (name && g_strcmp0 (name, node_name) == 0) {
                device_id = wp_pipewire_object_get_property (WP_PIPEWIRE_OBJECT (obj),
                                                             "device.id");
                g_value_unset (&val);
                break;
            }
        }
        g_value_unset (&val);
    }

    if (!device_id) return NULL;

    g_autoptr (WpIterator) dev_it = wp_object_manager_new_iterator (om);
    GValue dval = G_VALUE_INIT;
    while (wp_iterator_next (dev_it, &dval)) {
        GObject *obj = g_value_get_object (&dval);
        if (WP_IS_DEVICE (obj)) {
            guint32 bound = wp_proxy_get_bound_id (WP_PROXY (obj));
            gchar *bound_str = g_strdup_printf ("%u", bound);
            gboolean match = (g_strcmp0 (bound_str, device_id) == 0);
            g_free (bound_str);
            if (match) {
                WpDevice *dev = WP_DEVICE (obj);
                g_value_unset (&dval);
                return dev;
            }
        }
        g_value_unset (&dval);
    }

    return NULL;
}

/* Индекс активного профиля из параметра "Profile". */
static gint32 active_profile_index (WpDevice *dev) {
    g_autoptr (WpIterator) it =
        wp_pipewire_object_enum_params_sync (WP_PIPEWIRE_OBJECT (dev), "Profile", NULL);
    if (!it) return -1;

    gint32 result = -1;
    GValue val = G_VALUE_INIT;
    while (wp_iterator_next (it, &val)) {
        WpSpaPod *pod = g_value_get_boxed (&val);
        g_autoptr (WpIterator) pit = wp_spa_pod_new_iterator (pod);
        GValue pval = G_VALUE_INIT;
        while (wp_iterator_next (pit, &pval)) {
            WpSpaPod *prop = g_value_get_boxed (&pval);
            const gchar *key = NULL;
            WpSpaPod *value = NULL;
            if (wp_spa_pod_get_property (prop, &key, &value)) {
                if (g_strcmp0 (key, "index") == 0) {
                    wp_spa_pod_get_int (value, &result);
                }
                if (value) wp_spa_pod_unref (value);
            }
            g_value_unset (&pval);
            if (result != -1) break;
        }
        g_value_unset (&val);
        break; // Профиль всегда один.
    }

    return result;
}

GVariant *way_shell_wp_get_card_profiles (GObject *om, const gchar *node_name) {
    if (!om || !node_name) return NULL;

    WpDevice *dev = find_device_for_node (WP_OBJECT_MANAGER (om), node_name);
    if (!dev) return NULL;

    const gchar *card_name =
        wp_pipewire_object_get_property (WP_PIPEWIRE_OBJECT (dev), "device.name");
    if (!card_name) return NULL;

    g_autoptr (WpIterator) it =
        wp_pipewire_object_enum_params_sync (WP_PIPEWIRE_OBJECT (dev), "EnumProfile", NULL);
    if (!it) return NULL;

    GVariantBuilder profiles;
    g_variant_builder_init (&profiles, G_VARIANT_TYPE ("a(is)"));
    guint count = 0;

    GValue val = G_VALUE_INIT;
    while (wp_iterator_next (it, &val)) {
        WpSpaPod *pod = g_value_get_boxed (&val);

        gint32 index = -1;
        const gchar *name = NULL;
        gint32 available = -1; // SPA_PARAM_AVAILABILITY_unknown

        g_autoptr (WpIterator) pit = wp_spa_pod_new_iterator (pod);
        GValue pval = G_VALUE_INIT;
        while (wp_iterator_next (pit, &pval)) {
            WpSpaPod *prop = g_value_get_boxed (&pval);
            const gchar *key = NULL;
            WpSpaPod *value = NULL;
            if (wp_spa_pod_get_property (prop, &key, &value)) {
                if (g_strcmp0 (key, "index") == 0) {
                    wp_spa_pod_get_int (value, &index);
                } else if (g_strcmp0 (key, "name") == 0) {
                    wp_spa_pod_get_string (value, &name);
                } else if (g_strcmp0 (key, "available") == 0) {
                    guint32 av = 0;
                    if (wp_spa_pod_get_id (value, &av)) available = (gint32) av;
                }
                if (value) wp_spa_pod_unref (value);
            }
            g_value_unset (&pval);
        }

        // available: 0 unknown, 1 no, 2 yes. Недоступные профили в список не идут.
        if (index >= 0 && name && available != 1) {
            g_variant_builder_add (&profiles, "(is)", index, name);
            count++;
        }

        g_value_unset (&val);
    }

    if (count == 0) {
        g_variant_builder_clear (&profiles);
        return NULL;
    }

    /* ref_sink, а не сырой g_variant_new: тот отдаёт floating-ссылку, а Vala
     * на стороне вызова считает результат владеемым (transfer full). */
    return g_variant_ref_sink (
        g_variant_new ("(sia(is))", card_name, active_profile_index (dev), &profiles));
}

gboolean way_shell_wp_set_card_profile (GObject *om, const gchar *card_name,
                                       gint32 index) {
    if (!om || !card_name || index < 0) return FALSE;

    WpDevice *target = NULL;
    g_autoptr (WpIterator) it = wp_object_manager_new_iterator (WP_OBJECT_MANAGER (om));
    GValue val = G_VALUE_INIT;
    while (wp_iterator_next (it, &val)) {
        GObject *obj = g_value_get_object (&val);
        if (WP_IS_DEVICE (obj)) {
            const gchar *name =
                wp_pipewire_object_get_property (WP_PIPEWIRE_OBJECT (obj), "device.name");
            if (name && g_strcmp0 (name, card_name) == 0) {
                target = WP_DEVICE (obj);
                g_value_unset (&val);
                break;
            }
        }
        g_value_unset (&val);
    }

    if (!target) return FALSE;

    WpSpaPod *pod = wp_spa_pod_new_object ("Spa:Pod:Object:Param:Profile", "Profile",
                                           "index", "i", index, NULL);
    if (!pod) return FALSE;

    // set_param забирает под себе, unref не нужен.
    return wp_pipewire_object_set_param (WP_PIPEWIRE_OBJECT (target), "Profile", 0, pod);
}

#ifndef WAY_SHELL_WP_HELPERS_H
#define WAY_SHELL_WP_HELPERS_H

#include <glib-object.h>

void way_shell_wp_set_volume (GObject *mixer_api, guint32 id, double volume);
void way_shell_wp_set_mute (GObject *mixer_api, guint32 id, gboolean mute);

/* Профили звуковой карты, к которой принадлежит узел node_name.
 *
 * У Bluetooth-устройств профиль карты и есть выбор кодека (a2dp-sink-sbc,
 * a2dp-sink-aptx, headset-head-unit и так далее), поэтому эти две функции
 * заменяют разбор вывода `pactl list cards` и спавн `pactl set-card-profile`.
 * Разбор SPA-подов на Vala не выражается: wp_spa_pod_get_property отдаёт
 * вложенный под через out-параметр, а обход объекта идёт итератором подов.
 *
 * Возвращает GVariant типа "(sia(is))": имя карты, индекс активного профиля
 * (-1 если неизвестен), массив доступных профилей (индекс, имя).
 * NULL — карта не найдена или профилей нет. Вызывающий владеет ссылкой.
 */
GVariant *way_shell_wp_get_card_profiles (GObject *om, const gchar *node_name);

/* Переключает профиль карты. index — из массива, отданного функцией выше. */
gboolean way_shell_wp_set_card_profile (GObject *om, const gchar *card_name,
                                       gint32 index);

#endif

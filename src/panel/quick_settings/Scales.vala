// Путь: src/panel/quick_settings/Scales.vala
using Gtk;
using WayShell.Services;

namespace WayShell.QS {
    public class Scales : Box {
        private Box default_sink_container;
        private Image default_sink_icon;
        private Button default_sink_button;
        private Scale default_sink_scale;

        private Box default_source_container;
        private Image default_source_icon;
        private Button default_source_button;
        private Scale default_source_scale;

        private Box? brightness_container = null;
        private Image? brightness_icon = null;
        private Scale? brightness_scale = null;

        // Флаги для предотвращения бесконечных петель вызовов при обновлении
        private bool is_updating_sink = false;
        private bool is_updating_source = false;
        private bool is_updating_brightness = false;

        public Scales () {
            Object (orientation: Orientation.VERTICAL, spacing: 0);
            this.name = "quick-settings-scales";

            // --- 1. Слайдер громкости (Default Sink) ---
            default_sink_container = new Box (Orientation.HORIZONTAL, 0);
            default_sink_container.name = "default-sink-container";

            default_sink_button = new Button ();
            default_sink_button.add_css_class ("flat");
            default_sink_icon = new Image.from_icon_name ("audio-volume-muted-symbolic");
            default_sink_button.set_child (default_sink_icon);
            // Кнопка — только иконка, без метки скринридер не скажет, что это.
            default_sink_button.update_property (Gtk.AccessibleProperty.LABEL,
                                                _("Sound: mute or unmute"), -1);

            default_sink_scale = new Scale.with_range (Orientation.HORIZONTAL, 0.0, 1.0, 0.05);
            default_sink_scale.hexpand = true;
            default_sink_scale.update_property (Gtk.AccessibleProperty.LABEL, _("Volume"), -1);

            default_sink_container.append (default_sink_button);
            default_sink_container.append (default_sink_scale);
            this.append (default_sink_container);

            // Клик по иконке переключает Mute по умолчанию
            default_sink_button.clicked.connect (() => {
                var wp = WirePlumberService.get_global ();
                if (wp == null) return;
                var def_sink = wp.get_default_sink ();
                if (def_sink == null) return;

                bool mute = !def_sink.mute;
                wp.set_mute (def_sink, mute);
                // Не ждём mixer_changed с шины: иконка и подсказка должны
                // меняться в тот же кадр, что и клик.
                is_updating_sink = true;
                default_sink_scale.set_value (mute ? 0.0 : def_sink.volume);
                default_sink_icon.set_from_icon_name (
                    WirePlumberService.map_sink_vol_icon ((float)def_sink.volume, mute));
                update_sink_tooltip (def_sink.volume, mute);
                is_updating_sink = false;
            });

            // Регулировка слайдера пользователем
            default_sink_scale.value_changed.connect (() => {
                if (is_updating_sink) return;
                if (default_sink_scale.get_root () == null) return;

                var wp = WirePlumberService.get_global ();
                if (wp != null) {
                    var def_sink = wp.get_default_sink ();
                    if (def_sink != null) {
                        is_updating_sink = true;
                        wp.set_volume (def_sink, default_sink_scale.get_value ());

                        // Обновление иконки на лету при перетаскивании
                        default_sink_icon.set_from_icon_name (
                            WirePlumberService.map_sink_vol_icon ((float)default_sink_scale.get_value (), def_sink.mute)
                        );
                        update_sink_tooltip (default_sink_scale.get_value (), def_sink.mute);
                        is_updating_sink = false;
                    }
                }
            });

            // --- 2. Слайдер микрофона (Default Source) ---
            default_source_container = new Box (Orientation.HORIZONTAL, 0);
            default_source_container.name = "default-source-container";
            // Виден, если в системе есть устройство записи. Раньше здесь стояло
            // is_microphone_active() == !mute: приглушённый микрофон исчезал
            // из шторки вместе с кнопкой, которой его включают обратно.
            default_source_container.visible = false;

            default_source_button = new Button ();
            default_source_button.add_css_class ("flat");
            default_source_icon = new Image.from_icon_name ("microphone-sensitivity-muted-symbolic");
            default_source_button.set_child (default_source_icon);
            default_source_button.update_property (Gtk.AccessibleProperty.LABEL,
                                                  _("Microphone: mute or unmute"), -1);

            default_source_scale = new Scale.with_range (Orientation.HORIZONTAL, 0.0, 1.0, 0.05);
            default_source_scale.hexpand = true;
            default_source_scale.update_property (Gtk.AccessibleProperty.LABEL,
                                                 _("Microphone sensitivity"), -1);

            default_source_container.append (default_source_button);
            default_source_container.append (default_source_scale);
            this.append (default_source_container);

            default_source_button.clicked.connect (() => {
                var wp = WirePlumberService.get_global ();
                if (wp == null) return;
                var def_source = wp.get_default_source ();
                if (def_source == null) return;

                bool mute = !def_source.mute;
                wp.set_mute (def_source, mute);
                is_updating_source = true;
                default_source_scale.set_value (mute ? 0.0 : def_source.volume);
                default_source_icon.set_from_icon_name (
                    WirePlumberService.map_source_vol_icon ((float)def_source.volume, mute));
                update_source_tooltip (def_source.volume, mute);
                is_updating_source = false;
            });

            default_source_scale.value_changed.connect (() => {
                if (is_updating_source) return;
                if (default_source_scale.get_root () == null) return;

                var wp = WirePlumberService.get_global ();
                if (wp != null) {
                    var def_source = wp.get_default_source ();
                    if (def_source != null) {
                        is_updating_source = true;
                        wp.set_volume (def_source, default_source_scale.get_value ());

                        default_source_icon.set_from_icon_name (
                            WirePlumberService.map_source_vol_icon ((float)default_source_scale.get_value (), def_source.mute)
                        );
                        update_source_tooltip (default_source_scale.get_value (), def_source.mute);
                        is_updating_source = false;
                    }
                }
            });

            // --- 3. Слайдер яркости экрана ---
            // Только если подсветка вообще есть: на десктопе без /sys/class/backlight
            // строка была бы мёртвой.
            var bs = BrightnessService.get_global ();
            if (bs != null && bs.has_backlight_brightness ()) {
                brightness_container = new Box (Orientation.HORIZONTAL, 0);
                brightness_container.name = "brightness-container";

                brightness_icon = new Image.from_icon_name ("display-brightness-symbolic");
                // Не Button: у яркости нет состояния «выключено», нажимать нечего.
                // Отступы выравнивают её с иконками-кнопками выше — в CSS.

                brightness_scale = new Scale.with_range (Orientation.HORIZONTAL, 0.05, 1.0, 0.01);
                brightness_scale.hexpand = true;
                brightness_scale.update_property (Gtk.AccessibleProperty.LABEL,
                                                 _("Screen brightness"), -1);

                brightness_container.append (brightness_icon);
                brightness_container.append (brightness_scale);
                this.append (brightness_container);

                brightness_scale.value_changed.connect (() => {
                    if (is_updating_brightness) return;
                    if (brightness_scale.get_root () == null) return;

                    var b = BrightnessService.get_global ();
                    if (b == null) return;
                    b.set_backlight_percent (brightness_scale.get_value ());
                    update_brightness_tooltip (brightness_scale.get_value ());
                });

                // Яркость меняют ещё и горячими клавишами — слайдер должен
                // догонять. FileMonitor в сервисе шлёт brightness_changed и на
                // запись со стороны logind, и на brightnessctl из niri-биндов.
                bs.brightness_changed.connect ((percent) => {
                    is_updating_brightness = true;
                    brightness_scale.set_value (percent);
                    update_brightness_tooltip (percent);
                    is_updating_brightness = false;
                });

                is_updating_brightness = true;
                float cur = bs.get_backlight_percent ();
                brightness_scale.set_value (cur);
                update_brightness_tooltip (cur);
                is_updating_brightness = false;
            }

            // Подключение фоновых сигналов обновления аудиоустройств
            var wp_service = WirePlumberService.get_global ();
            if (wp_service != null) {
                wp_service.mixer_changed.connect (update_states);

                // Первичная инициализация состояния слайдеров при старте
                update_states ();
            }
        }

        // Синхронизация графического положения слайдеров со значениями в системе
        private void update_states () {
            var wp = WirePlumberService.get_global ();
            if (wp == null) return;

            // Обновляем слайдер наушников/колонок по умолчанию
            var sink = wp.get_default_sink ();
            if (sink != null) {
                is_updating_sink = true;
                default_sink_scale.set_value (sink.mute ? 0.0 : sink.volume);
                default_sink_icon.set_from_icon_name (
                    WirePlumberService.map_sink_vol_icon ((float)sink.volume, sink.mute)
                );
                update_sink_tooltip (sink.volume, sink.mute);
                is_updating_sink = false;
            }

            // Слайдер микрофона: показываем, пока в системе есть устройство записи.
            var source = wp.get_default_source ();
            default_source_container.visible = (source != null);
            if (source != null) {
                is_updating_source = true;
                default_source_scale.set_value (source.mute ? 0.0 : source.volume);
                default_source_icon.set_from_icon_name (
                    WirePlumberService.map_source_vol_icon ((float)source.volume, source.mute)
                );
                update_source_tooltip (source.volume, source.mute);
                is_updating_source = false;
            }
        }

        // Подсказки с процентами: на слайдере и на кнопке mute одинаковое значение,
        // чтобы наведение в любом месте строки отвечало на вопрос «сколько сейчас».
        private void update_sink_tooltip (double volume, bool mute) {
            string val = WirePlumberService.format_volume (volume, mute);
            default_sink_scale.tooltip_text = _("Volume: %s").printf (val);
            default_sink_button.tooltip_text = mute
                ? _("Sound muted, click to unmute")
                : _("Volume: %s, click to mute").printf (val);
        }

        private void update_source_tooltip (double volume, bool mute) {
            string val = WirePlumberService.format_volume (volume, mute);
            default_source_scale.tooltip_text = _("Microphone: %s").printf (val);
            default_source_button.tooltip_text = mute
                ? _("Microphone muted, click to unmute")
                : _("Microphone: %s, click to mute").printf (val);
        }

        private void update_brightness_tooltip (double percent) {
            if (brightness_scale == null || brightness_icon == null) return;
            string text = _("Screen brightness: %d%%").printf ((int) Math.round (percent * 100.0));
            brightness_scale.tooltip_text = text;
            brightness_icon.tooltip_text = text;
        }
    }
}

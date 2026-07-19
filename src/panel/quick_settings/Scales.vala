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

        // Флаги для предотвращения бесконечных петель вызовов при обновлении
        private bool is_updating_sink = false;
        private bool is_updating_source = false;

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

            default_sink_scale = new Scale.with_range (Orientation.HORIZONTAL, 0.0, 1.0, 0.05);
            default_sink_scale.hexpand = true;

            default_sink_container.append (default_sink_button);
            default_sink_container.append (default_sink_scale);
            this.append (default_sink_container);

            // Клик по иконке переключает Mute по умолчанию
            default_sink_button.clicked.connect (() => {
                var wp = WirePlumberService.get_global ();
                if (wp != null) {
                    var def_sink = wp.get_default_sink ();
                    if (def_sink != null) {
                        wp.set_mute (def_sink, !def_sink.mute);
                    }
                }
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
                        is_updating_sink = false;
                    }
                }
            });

            // --- 2. Слайдер микрофона (Default Source) ---
            default_source_container = new Box (Orientation.HORIZONTAL, 0);
            default_source_container.name = "default-source-container";
            default_source_container.visible = false; // Виден только при активном микрофоне

            default_source_button = new Button ();
            default_source_button.add_css_class ("flat");
            default_source_icon = new Image.from_icon_name ("microphone-sensitivity-muted-symbolic");
            default_source_button.set_child (default_source_icon);

            default_source_scale = new Scale.with_range (Orientation.HORIZONTAL, 0.0, 1.0, 0.05);
            default_source_scale.hexpand = true;

            default_source_container.append (default_source_button);
            default_source_container.append (default_source_scale);
            this.append (default_source_container);

            default_source_button.clicked.connect (() => {
                var wp = WirePlumberService.get_global ();
                if (wp != null) {
                    var def_source = wp.get_default_source ();
                    if (def_source != null) {
                        wp.set_mute (def_source, !def_source.mute);
                    }
                }
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
                            map_source_vol_icon ((float)default_source_scale.get_value (), def_source.mute)
                        );
                        is_updating_source = false;
                    }
                }
            });

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
                is_updating_sink = false;
            }

            // Обновляем слайдер микрофона (скрываем контейнер, если микрофон отключен или неактивен)
            default_source_container.visible = wp.is_microphone_active ();
            var source = wp.get_default_source ();
            if (source != null) {
                is_updating_source = true;
                default_source_scale.set_value (source.mute ? 0.0 : source.volume);
                default_source_icon.set_from_icon_name (
                    map_source_vol_icon ((float)source.volume, source.mute)
                );
                is_updating_source = false;
            }
        }

        private string map_source_vol_icon (float vol, bool mute) {
            if (mute) {
                return "microphone-sensitivity-muted-symbolic";
            }
            if (vol < 0.25) {
                return "microphone-sensitivity-low-symbolic";
            }
            if (vol < 0.5) {
                return "microphone-sensitivity-medium-symbolic";
            }
            return "microphone-sensitivity-high-symbolic";
        }
    }
}
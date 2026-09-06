using Gtk;
using Adw;
using WayShell.Services;

namespace WayShell.Osd {
    public class Osd : GLib.Object {
        private static Osd? global = null;

        public Gtk.Window win;
        public Box container;
        public Overlay overlay;
        public Adw.Animation animation;

        private Box volume_osd;
        private Scale volume_scale;
        private Image volume_icon;

        private Box? brightness_osd = null;
        private Scale? brightness_scale = null;
        private Image? brightness_icon = null;

        private Box? keyboard_brightness_osd = null;
        private Scale? keyboard_brightness_scale = null;
        private Image? keyboard_brightness_icon = null;

        private uint timeout_id = 0;

        // Поля для отслеживания реального изменения состояния аудио
        private double last_volume = -1.0;
        private bool last_mute = false;
        private uint32 last_sink_id = 0;
        private bool initialized = false;

        public static Osd get_global() {
            if (global == null) {
                global = new Osd();
            }
            return global;
        }

        private Osd() {
            init_layout();
        }

        private void init_layout() {
            container = new Box(Orientation.VERTICAL, 0);
            overlay = new Overlay();
            overlay.set_child(container);

            win = new Gtk.Window();
            win.set_size_request(340, 64);
            // Блокируем уничтожение окна: раньше здесь был reinitialize(),
            // который пересобирал всё заново и плодил новые подписки.
            win.close_request.connect(() => {
                win.set_visible(false);
                return true;
            });

            Gtk4LayerShell.init_for_window(win);
            Gtk4LayerShell.set_namespace(win, "way-shell-osd");
            Gtk4LayerShell.set_layer(win, Gtk4LayerShell.Layer.OVERLAY);
            win.name = "osd";
            Gtk4LayerShell.set_anchor(win, Gtk4LayerShell.Edge.BOTTOM, true);
            Gtk4LayerShell.set_margin(win, Gtk4LayerShell.Edge.BOTTOM, 150);
            win.visible = false;

            // Анимация плавного подъема панели снизу вверх
            var target = new Adw.CallbackAnimationTarget((value) => {
                Gtk4LayerShell.set_margin(win, Gtk4LayerShell.Edge.BOTTOM, (int)value);
            });
            animation = new Adw.TimedAnimation(win, 0.0, 120.0, 350, target);
            animation.done.connect(on_animation_done);

            // --- Индикатор громкости ---
            volume_osd = new Box(Orientation.HORIZONTAL, 0);
            volume_osd.name = "osd-container";
            volume_icon = new Image.from_icon_name("audio-volume-high-symbolic");
            volume_icon.pixel_size = 32;
            volume_scale = new Scale.with_range(Orientation.HORIZONTAL, 0.0, 1.0, 0.05);
            volume_scale.hexpand = true;
            volume_scale.sensitive = false;
            volume_osd.append(volume_icon);
            volume_osd.append(volume_scale);

            var wp = WirePlumberService.get_global();
            if (wp != null) {
                wp.default_sink_volume_changed.connect(on_default_sink_changed);
            }
            overlay.add_overlay(volume_osd);

            // --- Индикатор яркости экрана ---
            var bs = BrightnessService.get_global();
            if (bs != null && bs.has_backlight_brightness()) {
                brightness_osd = new Box(Orientation.HORIZONTAL, 0);
                brightness_osd.name = "osd-container";
                brightness_icon = new Image.from_icon_name("display-brightness-symbolic");
                brightness_icon.pixel_size = 32;
                brightness_scale = new Scale.with_range(Orientation.HORIZONTAL, 0.0, 1.0, 0.05);
                brightness_scale.hexpand = true;
                brightness_scale.sensitive = false;
                brightness_osd.append(brightness_icon);
                brightness_osd.append(brightness_scale);

                bs.brightness_changed.connect(on_brightness_changed);
                overlay.add_overlay(brightness_osd);
            }

            // --- Индикатор подсветки клавиатуры ---
            if (bs != null && bs.has_keyboard_brightness()) {
                keyboard_brightness_osd = new Box(Orientation.HORIZONTAL, 0);
                keyboard_brightness_osd.name = "osd-container";
                keyboard_brightness_icon = new Image.from_icon_name("keyboard-brightness-symbolic");
                keyboard_brightness_icon.pixel_size = 32;
                uint keyboard_max = bs.get_keyboard_max();
                keyboard_brightness_scale = new Scale.with_range(Orientation.HORIZONTAL, 0, keyboard_max, 1);
                keyboard_brightness_scale.hexpand = true;
                keyboard_brightness_scale.sensitive = false;
                keyboard_brightness_osd.append(keyboard_brightness_icon);
                keyboard_brightness_osd.append(keyboard_brightness_scale);

                bs.keyboard_brightness_changed.connect(on_keyboard_brightness_changed);
                overlay.add_overlay(keyboard_brightness_osd);
            }

            win.set_child(overlay);
        }

        private void on_animation_done() {
            var timed_anim = (Adw.TimedAnimation)animation;
            if (timed_anim.get_reverse()) {
                win.visible = false;
                return;
            }
            reset_timeout();
            timeout_id = GLib.Timeout.add_seconds(2, timed_dismiss);
        }

        private bool timed_dismiss() {
            if (win == null) return false;
            var timed_anim = (Adw.TimedAnimation)animation;
            timed_anim.set_reverse(true);
            animation.play();
            timeout_id = 0;
            return false;
        }

        private void reset_timeout() {
            if (timeout_id != 0) {
                GLib.Source.remove(timeout_id);
                timeout_id = 0;
            }
        }

        private void show_osd(Box active_osd) {
            if (brightness_osd != null && active_osd != brightness_osd) brightness_osd.visible = false;
            if (keyboard_brightness_osd != null && active_osd != keyboard_brightness_osd) keyboard_brightness_osd.visible = false;
            if (active_osd != volume_osd) volume_osd.visible = false;

            active_osd.visible = true;
        }

        private void trigger_osd(Box active_osd) {
            var qs = WayShell.QS.Drawer.get_global();
            if (qs.win.get_visible()) return;

            reset_timeout();
            show_osd(active_osd);

            if (!win.get_visible()) {
                // Окно одно на весь процесс; set_monitor пересоздаёт surface,
                // поэтому трогаем только пока оно скрыто.
                WayShell.Panel.Panel.place_on_active_monitor(win);
                win.visible = true;
                var timed_anim = (Adw.TimedAnimation)animation;
                timed_anim.set_reverse(false);
                animation.play();
            } else {
                timeout_id = GLib.Timeout.add_seconds(2, timed_dismiss);
            }
        }

        private void on_default_sink_changed(WirePlumberServiceNode sink) {
            string icon_name = WirePlumberService.map_sink_vol_icon((float)sink.volume, sink.mute);
            volume_icon.set_from_icon_name(icon_name);
            volume_scale.set_value(sink.mute ? 0.0 : sink.volume);

            // Если это первое получение данных при старте панели, просто запоминаем начальное состояние
            if (!initialized) {
                last_volume = sink.volume;
                last_mute = sink.mute;
                last_sink_id = sink.id;
                initialized = true;
                return;
            }

            // Вычисляем, изменились ли реальные параметры звука
            bool volume_changed = (sink.volume != last_volume);
            bool mute_changed = (sink.mute != last_mute);
            bool sink_changed = (sink.id != last_sink_id);

            // Показываем OSD только если действительно изменилась громкость, мут или сменился аудиовыход
            if (volume_changed || mute_changed || sink_changed) {
                trigger_osd(volume_osd);
            }

            // Запоминаем текущее состояние для последующего сравнения
            last_volume = sink.volume;
            last_mute = sink.mute;
            last_sink_id = sink.id;
        }

        private void on_brightness_changed(float percent) {
            var bs = BrightnessService.get_global();
            if (bs == null || brightness_icon == null || brightness_scale == null) return;

            string icon_name = bs.map_icon();
            brightness_icon.set_from_icon_name(icon_name);
            brightness_scale.set_value(percent);

            trigger_osd(brightness_osd);
        }

        private void on_keyboard_brightness_changed(uint percent) {
            if (keyboard_brightness_scale == null) return;
            keyboard_brightness_scale.set_value(percent);

            trigger_osd(keyboard_brightness_osd);
        }

        public void set_hidden() {
            reset_timeout();
            win.visible = false;
        }
    }
}
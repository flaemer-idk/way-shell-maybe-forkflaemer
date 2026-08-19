// Путь: src/osd/NotificationBanner.vala
using Gtk;
using Adw;
using WayShell.Services;
using WayShell.Panel;

namespace WayShell.Osd {
    public class NotificationBanner : GLib.Object {
        private static NotificationBanner? global = null;

        public Gtk.Window win;
        public Box container;
        public Adw.Animation animation;
        private uint timer_id = 0;
        private uint32 current_notification_id = 0;
        private GLib.Settings notif_settings;

        public static NotificationBanner get_global () {
            if (global == null) {
                global = new NotificationBanner ();
            }
            return global;
        }

        private NotificationBanner () {
            notif_settings = new GLib.Settings ("org.flaemer.way-shell.notifications");
            init_layout ();

            var ns = NotificationsService.get_global ();
            ns.notification_added.connect (on_notification_added);
            ns.notification_closed.connect (on_notification_closed);
        }

        private void init_layout () {
            win = new Gtk.Window ();
            win.name = "notifications-osd";

            Gtk4LayerShell.init_for_window (win);
            Gtk4LayerShell.set_namespace (win, "way-shell-notification-banner");
            Gtk4LayerShell.set_layer (win, Gtk4LayerShell.Layer.OVERLAY);
            Gtk4LayerShell.set_anchor (win, Gtk4LayerShell.Edge.TOP, true);
            Gtk4LayerShell.set_margin (win, Gtk4LayerShell.Edge.TOP, 10);
            Gtk4LayerShell.set_keyboard_mode (win, Gtk4LayerShell.KeyboardMode.NONE);
            win.visible = false;

            // Анимация выезда сверху
            var target = new Adw.CallbackAnimationTarget ((value) => {
                Gtk4LayerShell.set_margin (win, Gtk4LayerShell.Edge.TOP, (int) value);
                double opacity = (value + 70.0) / 80.0;
                win.set_opacity (double.max (0.0, double.min (opacity, 1.0)));
            });
            animation = new Adw.TimedAnimation (win, -70.0, 10.0, 250, target);
            animation.done.connect (on_animation_done);

            container = new Box (Orientation.VERTICAL, 0);

            // Пауза таймера при наведении мыши
            var motion = new EventControllerMotion ();
            motion.enter.connect (() => {
                reset_timer ();
            });
            motion.leave.connect (() => {
                start_timer (10);
            });
            container.add_controller (motion);

            win.set_child (container);
        }

        private void on_notification_added (Services.Notification n) {
            if (notif_settings.get_boolean ("do-not-disturb")) {
                return;
            }

            current_notification_id = n.id;

            // Очищаем старое содержимое
            Widget? child;
            while ((child = container.get_first_child ()) != null) {
                container.remove (child);
            }

            // Создаем виджет
            var widget = new NotificationWidget (n, true);
            
            // При нажатии на тело баннера — сразу прячем его с экрана!
            widget.activated.connect (() => {
                hide_banner ();
            });

            container.append (widget);

            show_banner ();
        }

        private void on_notification_closed (uint32 id) {
            if (current_notification_id == id) {
                hide_banner ();
            }
        }

        private void show_banner () {
            reset_timer ();

            if (!win.visible) {
                win.visible = true;
                var timed_anim = (Adw.TimedAnimation) animation;
                timed_anim.set_reverse (false);
                animation.play ();
            } else {
                start_timer (10); // 10 секунд
            }
        }

        public void hide_banner () {
            reset_timer ();
            if (win.visible) {
                var timed_anim = (Adw.TimedAnimation) animation;
                timed_anim.set_reverse (true);
                animation.play ();
            }
        }

        private void on_animation_done () {
            var timed_anim = (Adw.TimedAnimation) animation;
            if (timed_anim.get_reverse ()) {
                win.visible = false;
            } else {
                start_timer (10);
            }
        }

        private void start_timer (uint seconds) {
            reset_timer ();
            timer_id = GLib.Timeout.add_seconds (seconds, () => {
                hide_banner ();
                timer_id = 0;
                return false;
            });
        }

        private void reset_timer () {
            if (timer_id != 0) {
                GLib.Source.remove (timer_id);
                timer_id = 0;
            }
        }
    }
}
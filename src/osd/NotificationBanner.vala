using Gtk;
using Adw;
using WayShell.Services;
using WayShell.Panel;

namespace WayShell.Osd {
    public class NotificationBanner : GLib.Object {
        private static NotificationBanner? global = null;

        public Gtk.Window win;
        public Adw.Clamp clamp;
        public Box container;
        public Adw.Animation animation;
        private uint timer_id = 0;
        private uint32 current_notification_id = 0;
        private GLib.Settings notif_settings;
        private EventControllerMotion motion;

        private const uint DEFAULT_TIMEOUT_SECONDS = 6;
        private const uint HOVER_RECHECK_SECONDS = 2;

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

            var target = new Adw.CallbackAnimationTarget ((value) => {
                Gtk4LayerShell.set_margin (win, Gtk4LayerShell.Edge.TOP, (int) value);
                double opacity = (value + 70.0) / 80.0;
                win.set_opacity (double.max (0.0, double.min (opacity, 1.0)));
            });
            animation = new Adw.TimedAnimation (win, -70.0, 10.0, 250, target);
            animation.done.connect (on_animation_done);

            // Adw.Clamp жестко удерживает ширину 380px и заставляет текст переноситься
            clamp = new Adw.Clamp ();
            clamp.maximum_size = 380;
            clamp.tightening_threshold = 360;

            container = new Box (Orientation.VERTICAL, 0);
            clamp.set_child (container);

            motion = new EventControllerMotion ();
            // enter здесь сознательно не подключён: когда баннер появляется
            // под курсором, GTK синтезирует crossing-событие — таймер снимался,
            // а leave без движения мыши не приходил, и баннер висел вечно.
            // Пауза при наведении теперь делается опросом contains_pointer в таймере.
            motion.leave.connect (() => {
                start_timer (DEFAULT_TIMEOUT_SECONDS);
            });
            clamp.add_controller (motion);

            win.set_child (clamp);
        }

        private void on_notification_added (Services.Notification n) {
            if (notif_settings.get_boolean ("do-not-disturb")) {
                return;
            }

            current_notification_id = n.id;

            Widget? child;
            while ((child = container.get_first_child ()) != null) {
                container.remove (child);
            }

            var widget = new NotificationWidget (n, true);
            widget.activated.connect (() => {
                hide_banner ();
            });

            container.append (widget);
            show_banner (resolve_timeout (n));
        }

        // Клиент может задать expire_timeout в мс (спека org.freedesktop.Notifications):
        // -1 — решает сервер, 0 — не закрывать автоматически.
        private uint resolve_timeout (Services.Notification n) {
            if (n.expire_timeout == 0) return 0;
            if (n.expire_timeout < 0) return DEFAULT_TIMEOUT_SECONDS;
            return (uint) (n.expire_timeout / 1000).clamp (1, 60);
        }

        private void on_notification_closed (uint32 id) {
            if (current_notification_id == id) {
                hide_banner ();
            }
        }

        private void show_banner (uint seconds = DEFAULT_TIMEOUT_SECONDS) {
            if (!win.visible) {
                // Баннер один на весь процесс — привязываем к активному монитору,
                // иначе компози́тор выбирает выход сам.
                WayShell.Panel.Panel.place_on_active_monitor (win);
                win.visible = true;
                var timed_anim = (Adw.TimedAnimation) animation;
                if (animation.state == Adw.AnimationState.PLAYING) animation.reset ();
                timed_anim.set_reverse (false);
                animation.play ();
            }
            // Таймер стартует всегда и сразу. Раньше он зависел от animation.done,
            // а Adw.Animation пропускает проигрывание, если окно ещё не смапено.
            if (seconds > 0) start_timer (seconds);
            else reset_timer ();
        }

        public void hide_banner () {
            reset_timer ();
            if (!win.visible) return;
            var timed_anim = (Adw.TimedAnimation) animation;
            if (animation.state == Adw.AnimationState.PLAYING) animation.reset ();
            timed_anim.set_reverse (true);
            animation.play ();
        }

        private void on_animation_done () {
            if (((Adw.TimedAnimation) animation).get_reverse ()) {
                win.visible = false;
            }
        }

        private void start_timer (uint seconds) {
            reset_timer ();
            timer_id = GLib.Timeout.add_seconds (seconds, () => {
                timer_id = 0;
                if (motion.contains_pointer) {
                    start_timer (HOVER_RECHECK_SECONDS);
                    return Source.REMOVE;
                }
                hide_banner ();
                return Source.REMOVE;
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
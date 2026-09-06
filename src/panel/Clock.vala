using Gtk;
using Adw;
using WayShell.Services;

namespace WayShell.Panel {
    public class Clock : Box {
        public weak Panel panel;
        public Button button;
        public Image notif_dot;
        public Label label;
        
        private string clock_format;
        private bool toggled = false;
        private bool dnd = false;
        private GLib.Settings notifications_settings;
        private GLib.Settings panel_settings;

        public Clock() {
            Object(orientation: Orientation.HORIZONTAL, spacing: 0);
            this.add_css_class("panel-clock");
            init_layout();
        }

        private void init_layout() {
            panel_settings = new GLib.Settings("org.flaemer.way-shell.panel");
            clock_format = panel_settings.get_string("clock-format");

            var now = new DateTime.now_local();
            string date_str = now.format(clock_format);

            var cs = ClockService.get_global();
            cs.tick.connect(on_tick);

            button = new Button();
            button.add_css_class("panel-button");
            button.clicked.connect(on_clicked);
            // Для скринридера это была безымянная кнопка с меняющейся цифрой внутри.
            button.tooltip_text = _("Date and time: open notification center");
            button.update_property(Gtk.AccessibleProperty.LABEL, _("Notification center"), -1);

            var button_content = new Box(Orientation.HORIZONTAL, 6);
            label = new Label(date_str);
            notif_dot = new Image.from_icon_name("preferences-system-notifications-symbolic");
            notif_dot.add_css_class("panel-clock-notif");
            notif_dot.visible = false;
            // Индикатор-точка несёт смысл только визуально; текстовое состояние
            // скринридер получает из метки кнопки, которая обновляется в update_notif_label().
            notif_dot.update_state(Gtk.AccessibleState.HIDDEN, true, -1);

            button_content.append(label);
            button_content.append(notif_dot);
            button.set_child(button_content);
            this.append(button);

            var ns = NotificationsService.get_global();
            on_notifications_changed(ns, ns.get_notifications());
            ns.notification_changed.connect(on_notifications_changed);

            notifications_settings = new GLib.Settings("org.flaemer.way-shell.notifications");
            notifications_settings.changed["do-not-disturb"].connect(on_dnd_changed);
            dnd = notifications_settings.get_boolean("do-not-disturb");
            apply_dnd_state();
        }

        private void on_tick(ClockService cs, DateTime now) {
            label.set_text(now.format(clock_format));
        }

        private void on_clicked() {
            if (panel != null) Panel.set_active_monitor(panel.get_monitor());
            var mt = MessageTray.get_global();
            if (mt != null) mt.toggle();
        }

        private void on_notifications_changed(NotificationsService ns, GenericArray<WayShell.Services.Notification> notifications) {
            if (dnd) return;
            notif_dot.visible = (notifications.length > 0);
            update_accessible_label(notifications.length);
        }

        private void on_dnd_changed() {
            dnd = notifications_settings.get_boolean("do-not-disturb");
            apply_dnd_state();
        }

        private void apply_dnd_state() {
            if (dnd) {
                notif_dot.set_from_icon_name("notifications-disabled-symbolic");
                notif_dot.visible = true;
                update_accessible_label(0);
            } else {
                notif_dot.set_from_icon_name("preferences-system-notifications-symbolic");
                var ns = NotificationsService.get_global();
                on_notifications_changed(ns, ns.get_notifications());
            }
        }

        // Состояние уведомлений выражено только иконкой, так что для скринридера
        // дублируем его текстом в метке кнопки.
        private void update_accessible_label(uint count) {
            string state;
            if (dnd) {
                state = _("do not disturb");
            } else if (count > 0) {
                state = _("%u notifications").printf(count);
            } else {
                state = _("no notifications");
            }
            button.update_property(Gtk.AccessibleProperty.LABEL,
                                   _("Notification center, %s").printf(state), -1);
        }

        public void set_toggled(bool val) {
            this.toggled = val;
            if (val) {
                button.add_css_class("panel-button-toggled");
            } else {
                button.remove_css_class("panel-button-toggled");
            }
        }
    }
}
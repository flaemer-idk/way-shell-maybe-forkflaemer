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

            var button_content = new Box(Orientation.HORIZONTAL, 6);
            label = new Label(date_str);
            notif_dot = new Image.from_icon_name("preferences-system-notifications-symbolic");
            notif_dot.add_css_class("panel-clock-notif");
            notif_dot.visible = false;

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
            var mt = MessageTray.get_global();
            if (mt != null) mt.toggle();
        }

        private void on_notifications_changed(NotificationsService ns, GenericArray<WayShell.Services.Notification> notifications) {
            if (dnd) return;
            notif_dot.visible = (notifications.length > 0);
        }

        private void on_dnd_changed() {
            dnd = notifications_settings.get_boolean("do-not-disturb");
            apply_dnd_state();
        }

        private void apply_dnd_state() {
            if (dnd) {
                notif_dot.set_from_icon_name("notifications-disabled-symbolic");
                notif_dot.visible = true;
            } else {
                notif_dot.set_from_icon_name("preferences-system-notifications-symbolic");
                var ns = NotificationsService.get_global();
                on_notifications_changed(ns, ns.get_notifications());
            }
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
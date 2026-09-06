using Gtk;
using Adw;
using WayShell.Services;

namespace WayShell.Panel {
    public class NotificationGroup : Box {
        public string app_name;
        public Box header_box;
        public Box list_box;
        private HashTable<uint32, NotificationWidget> widgets;

        public signal void empty();

        public NotificationGroup(string app) {
            Object(orientation: Orientation.VERTICAL, spacing: 4);
            this.app_name = app;
            widgets = new HashTable<uint32, NotificationWidget>(direct_hash, direct_equal);

            header_box = new Box(Orientation.HORIZONTAL, 6);
            var label = new Label(app);
            label.add_css_class("notification-group-app-name");
            header_box.append(label);

            var dismiss_btn = new Button.from_icon_name("window-close-symbolic");
            dismiss_btn.add_css_class("circular");
            // Кнопка только с иконкой: без метки скринридер видит безымянную кнопку.
            dismiss_btn.tooltip_text = _("Dismiss all notifications from %s").printf(app);
            dismiss_btn.update_property(Gtk.AccessibleProperty.LABEL,
                                        _("Dismiss all notifications from %s").printf(app), -1);
            dismiss_btn.clicked.connect(dismiss_all);
            header_box.append(dismiss_btn);

            list_box = new Box(Orientation.VERTICAL, 2);

            this.append(header_box);
            this.append(list_box);
        }

        public void add_notification(Services.Notification n) {
            var widget = new NotificationWidget(n);
            widgets.insert(n.id, widget);
            list_box.prepend(widget);
        }

        public void remove_notification(uint32 id) {
            var widget = widgets.lookup(id);
            if (widget != null) {
                list_box.remove(widget);
                widgets.remove(id);
            }
            if (widgets.size() == 0) {
                empty();
            }
        }

        public void dismiss_all() {
            var ns = Services.NotificationsService.get_global();
            foreach (var id in widgets.get_keys()) {
                ns.closed_notification(id, 2);
            }
        }
    }

    public class NotificationsList : Box {
        public ScrolledWindow scroll;
        public Box list;
        public StatusPage status;
        public SwitchRow dnd_switch;
        private HashTable<string, NotificationGroup> groups;

        public NotificationsList() {
            Object(orientation: Orientation.VERTICAL, spacing: 0);
            this.name = "notifications-list";
            groups = new HashTable<string, NotificationGroup>(str_hash, str_equal);

            scroll = new ScrolledWindow();
            scroll.vexpand = true;
            scroll.set_policy(PolicyType.NEVER, PolicyType.AUTOMATIC);

            status = new StatusPage();
            status.icon_name = "notifications-disabled-symbolic";
            status.title = "No Notifications";
            status.vexpand = true;

            list = new Box(Orientation.VERTICAL, 4);
            scroll.set_child(list);

            dnd_switch = new SwitchRow();
            dnd_switch.title = "Do Not Disturb";
            
            var settings = new GLib.Settings("org.flaemer.way-shell.notifications");
            settings.bind("do-not-disturb", dnd_switch, "active", SettingsBindFlags.DEFAULT);

            this.append(status);
            this.append(scroll);
            this.append(dnd_switch);

            var ns = Services.NotificationsService.get_global();
            ns.notification_added.connect(on_notification_added);
            ns.notification_closed.connect(on_notification_closed);

            foreach (var n in ns.get_notifications()) {
                add_to_list(n);
            }
            update_view_state();
        }

        private void on_notification_added(Services.Notification n) {
            add_to_list(n);
            update_view_state();
        }

        private void on_notification_closed(uint32 id) {
            foreach (var group in groups.get_values()) {
                group.remove_notification(id);
            }
            update_view_state();
        }

        private void add_to_list(Services.Notification n) {
            var group = groups.lookup(n.app_name);
            if (group == null) {
                group = new NotificationGroup(n.app_name);
                group.empty.connect(() => {
                    list.remove(group);
                    groups.remove(n.app_name);
                    update_view_state();
                });
                groups.insert(n.app_name, group);
                list.prepend(group);
            }
            group.add_notification(n);
        }

        private void update_view_state() {
            bool has_items = (groups.size() > 0);
            status.visible = !has_items;
            scroll.visible = has_items;
        }
    }

    public class MessageTray : GLib.Object {
        private static MessageTray? global = null;

        public Gtk.Window win;
        public Box container;
        public Adw.Animation animation;
        public CalendarWidget calendar;
        public NotificationsList notifications_list;

        public signal void visible();
        public signal void hidden();

        public static MessageTray get_global() {
            if (global == null) {
                global = new MessageTray();
            }
            return global;
        }

        private MessageTray() {
            // Присваиваем global до построения layout: дети в их конструкторах
            // могут вызвать get_global() — иначе будет рекурсия.
            global = this;
            init_layout();
        }

        private void init_layout() {
            win = new Gtk.Window();
            win.name = "message-tray";
            // Блокируем уничтожение: рекурсивный init_layout() на close_request
            // при каждом закрытии создавал новый NotificationsList с новыми
            // подписками на NotificationsService, старые не отключались.
            win.close_request.connect(() => {
                set_hidden();
                return true;
            });

            Gtk4LayerShell.init_for_window(win);
            Gtk4LayerShell.set_namespace(win, "way-shell-message-tray");
            Gtk4LayerShell.set_layer(win, Gtk4LayerShell.Layer.TOP);
            Gtk4LayerShell.set_anchor(win, Gtk4LayerShell.Edge.TOP, true);
            Gtk4LayerShell.set_margin(win, Gtk4LayerShell.Edge.TOP, 8);

            container = new Box(Orientation.HORIZONTAL, 0);
            container.set_size_request(700, 600);

            var left_box = new Box(Orientation.VERTICAL, 0);
            left_box.set_size_request((int)(700 * 0.67), 600);
            
            var right_box = new Box(Orientation.VERTICAL, 0);
            right_box.hexpand = true;
            right_box.vexpand = true;

            var sep = new Separator(Orientation.VERTICAL);

            notifications_list = new NotificationsList();
            left_box.append(notifications_list);

            calendar = new CalendarWidget();
            right_box.append(calendar);

            container.append(left_box);
            container.append(sep);
            container.append(right_box);

            var target = new Adw.CallbackAnimationTarget((value) => {
                win.set_opacity(value);
            });
            animation = new Adw.TimedAnimation(win, 0.0, 1.0, 250, target);
            win.set_child(container);
        }

        public void set_visible() {
            // Окно трея одно на весь процесс: без явного set_monitor компози́тор
            // сам решает, на каком выходе его показать.
            WayShell.Panel.Panel.place_on_active_monitor(win);
            win.set_opacity(1.0); // Сразу устанавливаем 1.0
            win.present();
            visible();
        }

        public void set_hidden() {
            win.set_visible(false);
            hidden();
        }

        public void toggle() {
            if (!win.get_visible()) {
                set_visible();
                return;
            }
            // Окно одно на процесс: клик по панели другого монитора переносит трей
            // туда, а не закрывает его.
            if (WayShell.Panel.Panel.is_on_active_monitor(win)) {
                set_hidden();
            } else {
                // Без set_hidden(): его сигнал hidden() гасит подсветку кнопок
                // панели, а мы тут же показываемся снова.
                win.set_visible(false);
                set_visible();
            }
        }
    }
}
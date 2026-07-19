using GLib;

namespace WayShell.Services {
    public class Notification : GLib.Object {
        public uint32 id;
        public string app_name;
        public string app_icon;
        public string summary;
        public string body;
        public string[] actions;
        public uint8 urgency;
        public DateTime created_on;

        public Notification(uint32 id, string app_name, string app_icon, string summary, string body, string[] actions, uint8 urgency) {
            this.id = id;
            this.app_name = app_name;
            this.app_icon = app_icon;
            this.summary = summary;
            this.body = body;
            this.actions = actions;
            this.urgency = urgency;
            this.created_on = new DateTime.now_local();
        }
    }

    [DBus (name = "org.freedesktop.Notifications")]
    public class NotificationsServer : GLib.Object {
        private weak NotificationsService service;

        public NotificationsServer(NotificationsService service) {
            this.service = service;
        }

        public uint32 Notify(string app_name, uint32 replaces_id, string app_icon, string summary, string body, string[] actions, HashTable<string, Variant> hints, int32 expire_timeout) {
            return service.notify_incoming(app_name, replaces_id, app_icon, summary, body, actions, hints, expire_timeout);
        }

        public void CloseNotification(uint32 id) {
            service.closed_notification(id, 3);
        }

        public string[] GetCapabilities() {
            return { "actions", "body", "persistence", "icon-static" };
        }

        public void GetServerInformation(out string name, out string vendor, out string version, out string spec_version) {
            name = "way-shell";
            vendor = "way-shell";
            version = "0.1";
            spec_version = "1.2";
        }

        public signal void NotificationClosed(uint32 id, uint32 reason);
        public signal void ActionInvoked(uint32 id, string action_key);
    }

    public class NotificationsService : GLib.Object {
        private static NotificationsService? global = null;
        private uint32 last_id = 0;
        private GenericArray<Notification> notifications;
        private NotificationsServer server;
        private uint registration_id = 0;

        public signal void notification_added(Notification n);
        public signal void notification_closed(uint32 id);
        public signal void notification_changed(GenericArray<Notification> notifications);

        public static NotificationsService get_global() {
            if (global == null) {
                global = new NotificationsService();
            }
            return global;
        }

        private NotificationsService() {
            notifications = new GenericArray<Notification>();
            server = new NotificationsServer(this);
            register_dbus();
        }

        private void register_dbus() {
            try {
                var conn = Bus.get_sync(BusType.SESSION);
                registration_id = conn.register_object("/org/freedesktop/Notifications", server);
                // Ровно 5 аргументов: conn, имя, флаги, null (acquired handler), лямбда (lost handler)
                Bus.own_name_on_connection(conn, "org.freedesktop.Notifications", BusNameOwnerFlags.NONE, null, (c, n) => {
                    warning("NotificationsService: Name org.freedesktop.Notifications was lost");
                });
            } catch (Error e) {
                critical("NotificationsService: Failed to register DBus object: %s", e.message);
            }
        }

        public uint32 notify_incoming(string app_name, uint32 replaces_id, string app_icon, string summary, string body, string[] actions, HashTable<string, Variant> hints, int32 expire_timeout) {
            uint32 id = last_id++;
            uint8 urgency = 1;
            if (hints.contains("urgency")) {
                urgency = hints.lookup("urgency").get_byte();
            }

            var n = new Notification(id, app_name, app_icon, summary, body, actions, urgency);
            notifications.add(n);

            notification_added(n);
            notification_changed(notifications);

            return id;
        }

        public void closed_notification(uint32 id, uint32 reason) {
            for (int i = 0; i < notifications.length; i++) {
                if (notifications.get(i).id == id) {
                    notifications.remove_index(i);
                    notification_closed(id);
                    notification_changed(notifications);
                    server.NotificationClosed(id, reason);
                    break;
                }
            }
        }

        public void invoke_action(uint32 id, string action_key) {
            server.ActionInvoked(id, action_key);
        }

        public GenericArray<Notification> get_notifications() {
            return notifications;
        }
    }
}
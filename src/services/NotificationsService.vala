using GLib;
using Gdk;

namespace WayShell.Services {
    public class Notification : GLib.Object {
        public uint32 id { get; set; }
        public string app_name { get; set; }
        public string app_icon { get; set; }
        public string? image_path { get; set; }
        public Gdk.Pixbuf? image_pixbuf { get; set; }
        public string summary { get; set; }
        public string body { get; set; }
        public string[] actions { get; set; }
        public uint8 urgency { get; set; }
        public int32 expire_timeout { get; set; }
        public DateTime created_on { get; set; }

        public Notification(uint32 id, string app_name, string app_icon, string? image_path, Gdk.Pixbuf? image_pixbuf, string summary, string body, string[] actions, uint8 urgency, int32 expire_timeout = -1) {
            this.id = id;
            this.app_name = app_name;
            this.app_icon = app_icon;
            this.image_path = image_path;
            this.image_pixbuf = image_pixbuf;
            this.summary = summary;
            this.body = body;
            this.actions = actions;
            this.urgency = urgency;
            this.expire_timeout = expire_timeout;
            this.created_on = new DateTime.now_local();
        }
    }

    [DBus (name = "org.freedesktop.Notifications")]
    public class NotificationsServer : GLib.Object {
        private weak NotificationsService service;

        public NotificationsServer(NotificationsService service) {
            this.service = service;
        }

        public uint32 Notify(string app_name, uint32 replaces_id, string app_icon, string summary, string body, string[] actions, HashTable<string, Variant> hints, int32 expire_timeout) throws DBusError, IOError {
            return service.notify_incoming(app_name, replaces_id, app_icon, summary, body, actions, hints, expire_timeout);
        }

        public void CloseNotification(uint32 id) throws DBusError, IOError {
            service.closed_notification(id, 3);
        }

        public string[] GetCapabilities() throws DBusError, IOError {
            return { "actions", "body", "persistence", "icon-static", "image-data", "image-path" };
        }

        public void GetServerInformation(out string name, out string vendor, out string version, out string spec_version) throws DBusError, IOError {
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
                Bus.own_name_on_connection(conn, "org.freedesktop.Notifications",
                                           BusNameOwnerFlags.REPLACE | BusNameOwnerFlags.ALLOW_REPLACEMENT,
                                           null,
                                           (c, n) => {
                                               warning("NotificationsService: Name org.freedesktop.Notifications was lost.");
                                           });
            } catch (Error e) {
                critical("NotificationsService: Failed to register DBus object: %s", e.message);
            }
        }

        public uint32 notify_incoming(string app_name, uint32 replaces_id, string app_icon, string summary, string body, string[] actions, HashTable<string, Variant> hints, int32 expire_timeout) {
            uint8 urgency = 1;
            if (hints.contains("urgency")) {
                var u_var = hints.lookup("urgency");
                while (u_var != null && u_var.is_of_type(VariantType.VARIANT)) u_var = u_var.get_variant();
                // Спека требует byte, но некоторые клиенты присылают int32/uint32.
                // Без проверки типа get_byte() роняет процесс через g_critical.
                if (u_var != null) {
                    if (u_var.is_of_type(VariantType.BYTE)) urgency = u_var.get_byte();
                    else if (u_var.is_of_type(VariantType.INT32)) urgency = (uint8) u_var.get_int32().clamp(0, 2);
                    else if (u_var.is_of_type(VariantType.UINT32)) urgency = (uint8) u_var.get_uint32().clamp(0, 2);
                }
            }

            // 1. Извлекаем image-path
            string? image_path = null;
            Variant? path_var = null;
            if (hints.contains("image-path")) path_var = hints.lookup("image-path");
            else if (hints.contains("image_path")) path_var = hints.lookup("image_path");

            if (path_var != null) {
                while (path_var.is_of_type(VariantType.VARIANT)) path_var = path_var.get_variant();
                if (path_var.is_of_type(VariantType.STRING)) image_path = path_var.get_string();
            }

            // 2. Извлекаем сырые пиксели image-data / icon_data
            Gdk.Pixbuf? image_pixbuf = null;
            Variant? img_var = null;
            if (hints.contains("image-data")) img_var = hints.lookup("image-data");
            else if (hints.contains("image_data")) img_var = hints.lookup("image_data");
            else if (hints.contains("icon_data")) img_var = hints.lookup("icon_data");

            if (img_var != null) {
                image_pixbuf = parse_image_data(img_var);
            }

            if (replaces_id > 0) {
                for (int i = 0; i < notifications.length; i++) {
                    var existing = notifications.get(i);
                    if (existing.id == replaces_id) {
                        existing.app_name = app_name;
                        existing.app_icon = app_icon;
                        existing.image_path = image_path;
                        existing.image_pixbuf = image_pixbuf;
                        existing.summary = summary;
                        existing.body = body;
                        existing.actions = actions;
                        existing.urgency = urgency;
                        existing.expire_timeout = expire_timeout;
                        existing.created_on = new DateTime.now_local();

                        notification_changed(notifications);
                        return replaces_id;
                    }
                }
            }

            uint32 id = ++last_id;
            var n = new Notification(id, app_name, app_icon, image_path, image_pixbuf, summary, body, actions, urgency, expire_timeout);
            notifications.add(n);

            notification_added(n);
            notification_changed(notifications);

            return id;
        }

        private Gdk.Pixbuf? parse_image_data(Variant v) {
            // Распаковываем вложенный Variant ('v')
            Variant inner = v;
            while (inner.is_of_type(VariantType.VARIANT)) {
                inner = inner.get_variant();
            }

            int32 width = 0;
            int32 height = 0;
            int32 rowstride = 0;
            bool has_alpha = false;
            int32 bits_per_sample = 8;
            int32 channels = 3;
            Variant? byte_array_variant = null;

            var iter = inner.iterator();
            Variant? item;

            item = iter.next_value(); if (item != null && item.is_of_type(VariantType.INT32)) width = item.get_int32();
            item = iter.next_value(); if (item != null && item.is_of_type(VariantType.INT32)) height = item.get_int32();
            item = iter.next_value(); if (item != null && item.is_of_type(VariantType.INT32)) rowstride = item.get_int32();
            item = iter.next_value(); if (item != null && item.is_of_type(VariantType.BOOLEAN)) has_alpha = item.get_boolean();
            item = iter.next_value(); if (item != null && item.is_of_type(VariantType.INT32)) bits_per_sample = item.get_int32();
            item = iter.next_value(); if (item != null && item.is_of_type(VariantType.INT32)) channels = item.get_int32();
            byte_array_variant = iter.next_value();

            if (byte_array_variant == null || width <= 0 || height <= 0) return null;

            // Sanity-лимиты: данные пришли по D-Bus от любого приложения.
            if (width > 8192 || height > 8192 || bits_per_sample != 8 ||
                channels < 3 || channels > 4) {
                warning("NotificationsService: отброшен некорректный image-data (%dx%d, bps=%d, ch=%d)",
                        width, height, bits_per_sample, channels);
                return null;
            }
            if (rowstride < width * channels) {
                warning("NotificationsService: rowstride %d меньше строки %d", rowstride, width * channels);
                return null;
            }

            size_t required = (size_t) rowstride * (height - 1) + (size_t) width * channels;
            uint8[] data;

            if (byte_array_variant.is_of_type(new VariantType("ay"))) {
                // get_data() не несёт длины — её надо брать из get_size().
                size_t raw_len = byte_array_variant.get_size();
                if (raw_len < required) {
                    warning("NotificationsService: image-data обрезан (%" + size_t.FORMAT + " < %" + size_t.FORMAT + ")", raw_len, required);
                    return null;
                }
                unowned uint8* raw = (uint8*) byte_array_variant.get_data();
                if (raw == null) return null;
                data = new uint8[raw_len];
                Memory.copy(data, raw, raw_len);
            } else {
                size_t n_elements = byte_array_variant.n_children();
                if (n_elements < required) {
                    warning("NotificationsService: image-data обрезан (%" + size_t.FORMAT + " < %" + size_t.FORMAT + ")", n_elements, required);
                    return null;
                }
                data = new uint8[n_elements];
                for (size_t i = 0; i < n_elements; i++) {
                    data[i] = byte_array_variant.get_child_value(i).get_byte();
                }
            }

            var bytes = new GLib.Bytes.take((owned) data);

            return new Gdk.Pixbuf.from_bytes(
                bytes,
                Gdk.Colorspace.RGB,
                has_alpha,
                bits_per_sample,
                width,
                height,
                rowstride
            );
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
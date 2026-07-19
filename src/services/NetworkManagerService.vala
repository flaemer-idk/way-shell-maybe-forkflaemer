using NM;

namespace WayShell.Services {
    
    public class NetworkManagerService : GLib.Object {
        private static NetworkManagerService? global = null;
        private NM.Client client;

        public signal void changed ();
        public signal void vpn_activated ();
        public signal void vpn_deactivated ();

        public static NetworkManagerService? get_global () {
            if (global == null) {
                try {
                    global = new NetworkManagerService ();
                } catch (Error e) {
                    warning ("NetworkManagerService: Failed to connect: %s", e.message);
                    return null;
                }
            }
            return global;
        }

        private NetworkManagerService () throws Error {
            client = new NM.Client (null);
            
            client.notify["state"].connect (() => { changed (); });
            client.notify["primary-connection"].connect (() => { changed (); });
            client.notify["networking-enabled"].connect (() => { changed (); });
            client.notify["wireless-enabled"].connect (() => { changed (); });

            client.active_connection_added.connect (on_connection_added);
            client.active_connection_removed.connect (on_connection_removed);
        }

        private void on_connection_added (NM.ActiveConnection conn) {
            if (conn.vpn) {
                vpn_activated ();
            }
            changed ();
        }

        private void on_connection_removed (NM.ActiveConnection conn) {
            if (conn.vpn) {
                vpn_deactivated ();
            }
            changed ();
        }

        public bool get_networking_enabled () {
            return client.networking_enabled;
        }

        public bool wifi_available () {
            if (!client.wireless_enabled) return false;
            foreach (var dev in client.get_devices ()) {
                if (dev.device_type == NM.DeviceType.WIFI) {
                    return true;
                }
            }
            return false;
        }

        // Возвращаем стандартный NM.Device, Vala сам безопасно сделает g_object_ref!
        public NM.Device? get_primary_device () {
            var primary = client.primary_connection;
            if (primary == null) return null;
            var devs = primary.get_devices ();
            if (devs != null && devs.length > 0) {
                return devs[0];
            }
            return null;
        }

        // Используем стандартное перечисление NM.State
        public NM.State get_state () {
            return client.state;
        }

        public GenericArray<NM.ActiveConnection> get_active_vpn_connections () {
            var vpn_conns = new GenericArray<NM.ActiveConnection> ();
            foreach (var conn in client.get_active_connections ()) {
                if (conn.vpn || conn.get_connection_type () == "vpn") {
                    vpn_conns.add (conn);
                }
            }
            return vpn_conns;
        }

        public static string ap_strength_to_icon_name (uint8 strength) {
            if (strength < 20) return "network-wireless-signal-none-symbolic";
            if (strength < 40) return "network-wireless-signal-weak-symbolic";
            if (strength < 60) return "network-wireless-signal-ok-symbolic";
            if (strength < 80) return "network-wireless-signal-good-symbolic";
            return "network-wireless-signal-excellent-symbolic";
        }

        public void scan_wifi () {
            foreach (var dev in client.get_devices ()) {
                if (dev.device_type == NM.DeviceType.WIFI) {
                    var wifi = (NM.DeviceWifi) dev;
                    wifi.request_scan_async.begin (null, (obj, res) => {
                        try {
                            wifi.request_scan_async.end (res);
                            debug ("NetworkManagerService: Scan done successfully.");
                            changed ();
                        } catch (Error e) {
                            warning ("NetworkManagerService: Scan failed: %s", e.message);
                        }
                    });
                }
            }
        }
    }
}
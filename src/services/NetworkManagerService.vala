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

        // Единственный NM.Client в процессе. Раньше WifiButton и EthernetButton
        // создавали свои — три синхронных nm_client_new() на старте и три копии
        // кэша объектов NetworkManager. Весь доступ к NM идёт через сервис.
        public NM.Client get_client () {
            return client;
        }

        public NM.DeviceWifi? get_wifi_device () {
            foreach (var dev in client.get_devices ()) {
                if (dev.device_type == NM.DeviceType.WIFI) return (NM.DeviceWifi) dev;
            }
            return null;
        }

        public NM.DeviceEthernet? get_ethernet_device () {
            foreach (var dev in client.get_devices ()) {
                if (dev.device_type == NM.DeviceType.ETHERNET) return (NM.DeviceEthernet) dev;
            }
            return null;
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

        // SSID в NM — это GBytes без гарантии завершающего нуля и без гарантии UTF-8.
        // Копия того же разбора живёт в WifiButton.ap_to_name — там она возвращает
        // непереводимые строки-маркеры, которые сравниваются в update_active_ap_status.
        public static string ap_to_ssid (NM.AccessPoint ap) {
            var ssid = ap.get_ssid ();
            if (ssid == null) return _("unknown network");
            unowned uint8[] data = ssid.get_data ();
            var sb = new StringBuilder ();
            for (int i = 0; i < data.length; i++) {
                if (data[i] == 0) break;
                sb.append_c ((char) data[i]);
            }
            string result = sb.str;
            if (!result.validate ()) return _("unknown network");
            return result;
        }

        // Первый IPv4-адрес устройства. Для подсказки кабельного подключения:
        // у Ethernet нет SSID, и единственное полезное число — адрес в локалке.
        public static string device_ip4 (NM.Device? dev) {
            if (dev == null) return "";
            var cfg = dev.get_ip4_config ();
            if (cfg == null) return "";
            var addresses = cfg.get_addresses ();
            if (addresses == null || addresses.length == 0) return "";
            return addresses[0].get_address ();
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
// Путь: src/panel/quick_settings/modules/EthernetButton.vala
using Gtk;
using GLib;
using NM;

namespace WayShell.QS {
    public class EthernetButton : GridButton {
        public MenuWidget eth_menu;
        public NM.Client? nm_client = null;
        private NM.DeviceEthernet? eth_device = null;

        public EthernetButton() {
            var menu = new MenuWidget("Wired Network", "network-wired-symbolic", true);
            menu.set_size_request(-1, 260);

            base(ButtonType.GENERIC, "Ethernet", "Disconnected", "network-wired-offline-symbolic", menu);
            this.eth_menu = menu;

            try {
                nm_client = new NM.Client(null);
                find_ethernet_device();
            } catch (Error e) {
                warning("EthernetButton: Failed to connect to NetworkManager: %s", e.message);
            }

            if (eth_device != null) {
                eth_device.notify["state"].connect(() => {
                    update_status();
                    refresh_eth_list();
                });
                eth_device.notify["carrier"].connect(() => {
                    update_status();
                    refresh_eth_list();
                });
                eth_device.notify["speed"].connect(update_status);
            }

            if (nm_client != null) {
                nm_client.notify["networking-enabled"].connect(update_status);
                nm_client.notify["primary-connection"].connect(update_status);
            }

            toggle.clicked.connect(on_toggle_clicked);
            reveal_changed.connect((is_revealed) => {
                if (is_revealed) refresh_eth_list();
            });

            update_status();
            GLib.Timeout.add_seconds(3, () => {
                update_status();
                return true;
            });
        }

        private void find_ethernet_device() {
            if (nm_client == null) return;
            foreach (var dev in nm_client.get_devices()) {
                if (dev.device_type == NM.DeviceType.ETHERNET) {
                    eth_device = (NM.DeviceEthernet) dev;
                    break;
                }
            }
        }

        private void on_toggle_clicked() {
            if (nm_client == null || eth_device == null) return;

            try {
                var active_conn = eth_device.active_connection;
                if (active_conn != null) {
                    nm_client.deactivate_connection_async.begin(active_conn, null);
                } else {
                    var conns = eth_device.get_available_connections();
                    if (conns != null && conns.length > 0) {
                        nm_client.activate_connection_async.begin(conns[0], eth_device, null, null);
                    }
                }
            } catch (Error e) {
                warning("EthernetButton: Failed to toggle connection: %s", e.message);
            }
        }

        private void update_status() {
            if (nm_client == null || eth_device == null) {
                set_toggled(false);
                subtitle.set_text("Unavailable");
                icon.set_from_icon_name("network-wired-offline-symbolic");
                return;
            }

            if (!nm_client.networking_enabled) {
                set_toggled(false);
                subtitle.set_text("Disabled");
                icon.set_from_icon_name("network-wired-offline-symbolic");
                return;
            }

            var state = eth_device.state;
            bool carrier = eth_device.carrier;

            if (!carrier) {
                set_toggled(false);
                subtitle.set_text("Unplugged");
                icon.set_from_icon_name("network-wired-offline-symbolic");
                return;
            }

            switch (state) {
                case NM.DeviceState.ACTIVATED:
                    set_toggled(true);
                    string ip_str = get_ip4_address();
                    subtitle.set_text(ip_str != "" ? ip_str : "Connected");
                    icon.set_from_icon_name("network-wired-symbolic");
                    break;
                case NM.DeviceState.PREPARE:
                case NM.DeviceState.CONFIG:
                case NM.DeviceState.IP_CONFIG:
                case NM.DeviceState.IP_CHECK:
                    set_toggled(true);
                    subtitle.set_text("Connecting...");
                    icon.set_from_icon_name("network-wired-acquiring-symbolic");
                    break;
                default:
                    set_toggled(false);
                    subtitle.set_text("Disconnected");
                    icon.set_from_icon_name("network-wired-offline-symbolic");
                    break;
            }
        }

        private string get_ip4_address() {
            if (eth_device == null) return "";
            var ip4_config = eth_device.get_ip4_config();
            if (ip4_config != null) {
                var addresses = ip4_config.get_addresses();
                if (addresses != null && addresses.length > 0) {
                    return addresses[0].get_address();
                }
            }
            return "";
        }

        public void refresh_eth_list() {
            Widget? child;
            while ((child = eth_menu.options.get_first_child()) != null) {
                eth_menu.options.remove(child);
            }

            if (nm_client == null) return;

            foreach (var dev in nm_client.get_devices()) {
                if (dev.device_type == NM.DeviceType.ETHERNET) {
                    var eth = (NM.DeviceEthernet) dev;
                    var item_box = new Box(Orientation.VERTICAL, 4);
                    item_box.add_css_class("quick-settings-menu-option");

                    var header_row = new Box(Orientation.HORIZONTAL, 8);
                    var dev_icon = new Image.from_icon_name(eth.carrier ? "network-wired-symbolic" : "network-wired-offline-symbolic");
                    var iface_label = new Label(eth.get_iface());
                    iface_label.add_css_class("heading");
                    iface_label.halign = Align.START;
                    iface_label.hexpand = true;

                    var state_label = new Label(eth.state == NM.DeviceState.ACTIVATED ? "Connected" : (eth.carrier ? "Ready" : "No Cable"));
                    if (eth.state == NM.DeviceState.ACTIVATED) {
                        state_label.add_css_class("active-icon-activated");
                    }

                    header_row.append(dev_icon);
                    header_row.append(iface_label);
                    header_row.append(state_label);
                    item_box.append(header_row);

                    // Дополнительные детали интерфейса (Скорость, IP, MAC)
                    var details_box = new Box(Orientation.VERTICAL, 2);
                    details_box.margin_start = 24;

                    if (eth.speed > 0) {
                        var speed_label = new Label(@"Speed: $(eth.speed) Mb/s");
                        speed_label.halign = Align.START;
                        speed_label.add_css_class("dim-label");
                        details_box.append(speed_label);
                    }

                    string hw_addr = eth.hw_address;
                    if (hw_addr != null && hw_addr != "") {
                        var mac_label = new Label(@"MAC: $hw_addr");
                        mac_label.halign = Align.START;
                        mac_label.add_css_class("dim-label");
                        details_box.append(mac_label);
                    }

                    item_box.append(details_box);
                    eth_menu.options.append(item_box);
                }
            }
        }
    }
}
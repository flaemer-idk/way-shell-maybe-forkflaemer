using Gtk;
using GLib;
using NM;

namespace WayShell.QS {
    public class EthernetButton : GridButton {
        public MenuWidget eth_menu;
        public NM.Client? nm_client = null;
        public NM.DeviceEthernet? eth_device = null;

        public signal void state_changed();

        public EthernetButton() {
            var menu = new MenuWidget(_("Wired Network"), "network-wired-symbolic", true);
            menu.set_size_request(-1, 260);

            base(ButtonType.GENERIC, _("Ethernet"), _("Disconnected"), "network-wired-offline-symbolic", menu);
            this.eth_menu = menu;

            // Один NM.Client на процесс, живёт в NetworkManagerService.
            ensure_client();

            toggle.clicked.connect(on_toggle_clicked);
            reveal_changed.connect((is_revealed) => {
                if (is_revealed) refresh_eth_list();
            });

            update_status();
        }

        // Лениво берёт клиента из сервиса. Если NetworkManager на старте ещё не поднялся,
        // сервис отдаёт null и попытка повторится при следующем обращении — поэтому
        // подписки на клиента навешиваются здесь, а не в конструкторе.
        private void ensure_client() {
            if (nm_client != null) return;
            var nm = Services.NetworkManagerService.get_global();
            if (nm == null) return;
            nm_client = nm.get_client();

            nm_client.notify["networking-enabled"].connect(() => {
                update_status();
                state_changed();
            });
            nm_client.notify["primary-connection"].connect(() => {
                update_status();
                state_changed();
            });
            // Отслеживание подключения/отключения сетевых карт на лету (USB-Ethernet и др.)
            nm_client.device_added.connect((dev) => {
                if (dev.device_type == NM.DeviceType.ETHERNET) {
                    find_ethernet_device();
                    update_status();
                    state_changed();
                }
            });
            nm_client.device_removed.connect((dev) => {
                if (dev == eth_device) {
                    eth_device = null;
                    find_ethernet_device();
                    update_status();
                    state_changed();
                }
            });

            find_ethernet_device();
        }

        private void setup_device_signals() {
            if (eth_device == null) return;

            eth_device.notify["state"].connect(() => {
                update_status();
                refresh_eth_list();
                state_changed();
            });
            eth_device.notify["carrier"].connect(() => {
                update_status();
                refresh_eth_list();
                state_changed();
            });
            eth_device.notify["speed"].connect(update_status);
            // Заменяет бывший опрос каждые 3 с: подпись на IP нужна, чтобы
            // подзаголовок с адресом обновлялся после DHCP.
            eth_device.notify["ip4-config"].connect(update_status);
        }

        public void find_ethernet_device() {
            if (nm_client == null) return;

            NM.DeviceEthernet? found = null;
            foreach (var dev in nm_client.get_devices()) {
                if (dev.device_type == NM.DeviceType.ETHERNET) {
                    found = (NM.DeviceEthernet) dev;
                    break;
                }
            }

            // Без этого повторные вызовы (device_added, update_status, should_be_visible)
            // навешивали ещё один набор notify-обработчиков на то же устройство.
            if (found == eth_device) return;
            eth_device = found;
            setup_device_signals();
        }

        /**
         * Логика умного показа:
         * - Если кабеля нет, но есть Wi-Fi (ноутбук) -> скрываем
         * - Если кабеля нет и Wi-Fi нет (ПК) -> показываем Unplugged
         * - Если кабель вставлен -> показываем всегда
         */
        public bool should_be_visible(bool has_wifi) {
            // Метод вызывается на каждом открытии шторки (Drawer.will_show).
            // Здесь был синхронный new NM.Client(null) — шторка замирала на время
            // загрузки всего кэша NM прямо в ответ на клик.
            ensure_client();
            if (nm_client == null) return false;

            if (eth_device == null) {
                find_ethernet_device();
            }

            if (eth_device == null) {
                return false;
            }

            // Кабель вставлен — показываем всегда. Нет кабеля — показываем только там,
            // где больше нечем подключаться (ПК без Wi-Fi), иначе плашка Unplugged
            // на ноутбуке просто занимает место.
            return eth_device.carrier || !has_wifi;
        }

        private void on_toggle_clicked() {
            if (nm_client == null || eth_device == null) return;

            var active_conn = eth_device.active_connection;
            if (active_conn != null) {
                nm_client.deactivate_connection_async.begin(active_conn, null);
            } else {
                var conns = eth_device.get_available_connections();
                if (conns != null && conns.length > 0) {
                    nm_client.activate_connection_async.begin(conns[0], eth_device, null, null);
                }
            }
        }

        public void update_status() {
            ensure_client();
            if (nm_client != null && eth_device == null) {
                find_ethernet_device();
            }

            if (nm_client == null || eth_device == null) {
                set_toggled(false);
                subtitle.set_text(_("Unavailable"));
                icon.set_from_icon_name("network-wired-offline-symbolic");
                return;
            }

            if (!nm_client.networking_enabled) {
                set_toggled(false);
                subtitle.set_text(_("Disabled"));
                icon.set_from_icon_name("network-wired-offline-symbolic");
                return;
            }

            var state = eth_device.state;
            bool carrier = eth_device.carrier;

            if (!carrier) {
                set_toggled(false);
                subtitle.set_text(_("Unplugged"));
                icon.set_from_icon_name("network-wired-offline-symbolic");
                return;
            }

            switch (state) {
                case NM.DeviceState.ACTIVATED:
                    set_toggled(true);
                    string ip_str = get_ip4_address();
                    subtitle.set_text(ip_str != "" ? ip_str : _("Connected"));
                    icon.set_from_icon_name("network-wired-symbolic");
                    break;
                case NM.DeviceState.PREPARE:
                case NM.DeviceState.CONFIG:
                case NM.DeviceState.IP_CONFIG:
                case NM.DeviceState.IP_CHECK:
                    set_toggled(true);
                    subtitle.set_text(_("Connecting..."));
                    icon.set_from_icon_name("network-wired-acquiring-symbolic");
                    break;
                default:
                    set_toggled(false);
                    subtitle.set_text(_("Disconnected"));
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

                    var state_label = new Label(eth.state == NM.DeviceState.ACTIVATED ? _("Connected") : (eth.carrier ? _("Ready") : _("No Cable")));
                    if (eth.state == NM.DeviceState.ACTIVATED) {
                        state_label.add_css_class("active-icon-activated");
                    }

                    header_row.append(dev_icon);
                    header_row.append(iface_label);
                    header_row.append(state_label);
                    item_box.append(header_row);

                    var details_box = new Box(Orientation.VERTICAL, 2);
                    details_box.margin_start = 24;

                    if (eth.speed > 0) {
                        var speed_label = new Label(_("Speed: %u Mb/s").printf(eth.speed));
                        speed_label.halign = Align.START;
                        speed_label.add_css_class("dim-label");
                        details_box.append(speed_label);
                    }

                    string hw_addr = eth.hw_address;
                    if (hw_addr != null && hw_addr != "") {
                        var mac_label = new Label(_("MAC: %s").printf(hw_addr));
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
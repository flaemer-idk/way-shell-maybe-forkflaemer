using Gtk;
using GLib;
using NM;

namespace WayShell.QS {

    public class WifiButton : GridButton {
        public MenuWidget wifi_menu;
        public Spinner menu_spinner;
        public NM.Client? nm_client = null;
        private NM.DeviceWifi? wifi_device = null;
        private bool ui_locked = false;
        private bool is_scanning = false;

        // Строковый трекер активного подключения для точной отрисовки спиннеров
        public string? connecting_ssid = null;

        public WifiButton() {
            // Создаем меню для модуля Wi-Fi
            var menu = new MenuWidget("Wi-Fi Networks", "network-wireless-signal-excellent-symbolic", true);
            menu.set_size_request(-1, 420);

            // Инициализируем базовый GridButton
            base(ButtonType.WIFI, "Wi-Fi", "Offline", "network-wireless-offline-symbolic", menu);
            this.wifi_menu = menu;

            // Настройка баннера ошибок в шапке меню
            var failure_banner_container = new Box(Orientation.HORIZONTAL, 0);
            failure_banner_container.add_css_class("failure-banner");
            
            var failure_label = new Label("Failed to connect to network");
            failure_label.hexpand = true;

            var dismiss_btn = new Button();
            dismiss_btn.set_child(failure_label);
            dismiss_btn.clicked.connect(() => {
                wifi_menu.banner.set_reveal_child(false);
                var qs = Drawer.get_global();
                qs.shrink();
            });
            failure_banner_container.append(dismiss_btn);
            wifi_menu.banner.set_child(failure_banner_container);

            // Инициализируем спиннер загрузки в шапке списка сетей
            menu_spinner = new Spinner();
            menu_spinner.visible = false;
            wifi_menu.title_container.append(menu_spinner);

            // Кнопка обновления списка сетей в шапке списка
            var refresh_btn = new Button.from_icon_name("view-refresh-symbolic");
            refresh_btn.valign = Align.CENTER;
            refresh_btn.halign = Align.END;
            refresh_btn.hexpand = true;
            refresh_btn.clicked.connect(() => {
                trigger_scan.begin();
            });
            wifi_menu.title_container.append(refresh_btn);

            // Находим сетевое устройство беспроводной связи Wi-Fi
            try {
                nm_client = new NM.Client(null);
                foreach (var dev in nm_client.get_devices()) {
                    if (dev.device_type == NM.DeviceType.WIFI) {
                        wifi_device = (NM.DeviceWifi) dev;
                        break;
                    }
                }
            } catch (Error e) {
                warning("WifiButton: Failed to connect to NetworkManager: %s", e.message);
            }

            if (wifi_device != null) {
                // Подписываемся на изменения состояния подключения
                wifi_device.notify["state"].connect(() => {
                    update_active_ap_status();
                    refresh_wifi_list(); // <--- ОБНОВЛЯЕМ СПИСОК СЕТЕЙ ДЛЯ СВОЕВРЕМЕННОГО ТУШЕНИЯ СПИННЕРОВ И ВКЛЮЧЕНИЯ ГАЛОЧЕК
                });
                wifi_device.notify["active-access-point"].connect(() => {
                    update_active_ap_status();
                    refresh_wifi_list();
                });
            }

            toggle.clicked.connect(on_toggle_clicked);
            reveal_changed.connect((is_revealed) => {
                if (is_revealed) {
                    trigger_scan.begin();
                }
            });

            // Первичный опрос и запуск таймера обновления
            update_active_ap_status();
            GLib.Timeout.add(2000, () => {
                update_active_ap_status();
                return true;
            });
        }

        private void on_toggle_clicked() {
            if (nm_client == null) return;
            try {
                bool is_enabled = nm_client.wireless_enabled;
                nm_client.wireless_enabled = !is_enabled;

                if (is_enabled) {
                    set_toggled(false);
                    subtitle.set_text("Offline");
                    icon.set_from_icon_name("network-wireless-offline-symbolic");
                } else {
                    ui_locked = true;
                    set_toggled(true);
                    subtitle.set_text("Connecting...");
                    icon.set_from_icon_name("network-wireless-acquiring-symbolic");
                    
                    GLib.Timeout.add_seconds(3, () => {
                        ui_locked = false;
                        update_active_ap_status();
                        return false;
                    });
                }
            } catch (Error e) {
                warning("WifiButton: Failed to toggle wireless: %s", e.message);
            }
        }

        private void update_active_ap_status() {
            if (ui_locked || nm_client == null || wifi_device == null) return;

            // Если Wi-Fi выключен глобально в системе
            if (!nm_client.wireless_enabled) {
                set_toggled(false);
                subtitle.set_text("Offline");
                icon.set_from_icon_name("network-wireless-offline-symbolic");
                return;
            }

            string name = "Offline";
            string icon_name = "network-wireless-offline-symbolic";
            bool preparing = false;

            var state = wifi_device.state;

            switch (state) {
                case NM.DeviceState.UNKNOWN:
                case NM.DeviceState.UNMANAGED:
                case NM.DeviceState.UNAVAILABLE:
                case NM.DeviceState.DISCONNECTED:
                case NM.DeviceState.FAILED:
                case NM.DeviceState.DEACTIVATING:
                    set_toggled(false);
                    icon_name = "network-wireless-offline-symbolic";
                    name = "Offline";
                    break;
                case NM.DeviceState.PREPARE:
                case NM.DeviceState.CONFIG:
                case NM.DeviceState.NEED_AUTH:
                case NM.DeviceState.IP_CONFIG:
                case NM.DeviceState.IP_CHECK:
                case NM.DeviceState.SECONDARIES:
                    set_toggled(true);
                    preparing = true;
                    icon_name = "network-wireless-acquiring-symbolic";
                    name = "Connecting...";
                    break;
                case NM.DeviceState.ACTIVATED:
                    set_toggled(true);
                    name = "Connected";
                    icon_name = "network-wireless-signal-excellent-symbolic";

                    // Пытаемся гарантированно получить SSID имя из активного профиля (активного соединения)
                    var active_conn = wifi_device.active_connection;
                    if (active_conn != null) {
                        name = active_conn.id;
                    }
                    break;
                default:
                    set_toggled(true);
                    break;
            }

            var ap = wifi_device.active_access_point;
            if (ap != null) {
                string ap_ssid = ap_to_name(ap);
                if (ap_ssid != "Offline" && ap_ssid != "Unknown Network" && ap_ssid != "") {
                    name = ap_ssid;
                }
                uint8 strength = ap.strength;
                if (!preparing) {
                    icon_name = Services.NetworkManagerService.ap_strength_to_icon_name(strength);
                }
            }

            subtitle.set_text(name);
            icon.set_from_icon_name(icon_name);
        }

        private async void trigger_scan() {
            if (is_scanning || wifi_device == null) return;
            is_scanning = true;

            menu_spinner.visible = true;
            menu_spinner.start();

            try {
                yield wifi_device.request_scan_async(null);
                
                GLib.Timeout.add_seconds(1, () => {
                    refresh_wifi_list();
                    return false;
                });
            } catch (Error e) {
                warning("WifiButton: Scan failed: %s", e.message);
            }

            menu_spinner.stop();
            menu_spinner.visible = false;
            is_scanning = false;
        }

        public void refresh_wifi_list() {
            if (wifi_device == null) return;

            Widget? child;
            while ((child = wifi_menu.options.get_first_child()) != null) {
                wifi_menu.options.remove(child);
            }

            var aps = wifi_device.get_access_points();
            if (aps == null || aps.length == 0) return;

            var active_ap = wifi_device.active_access_point;
            var best_aps = new HashTable<string, NM.AccessPoint>(str_hash, str_equal);

            for (int i = 0; i < aps.length; i++) {
                var ap = aps[i];
                string ssid_name = ap_to_name(ap);
                if (ssid_name == "Unknown Network" || ssid_name == "") continue;

                var seen = best_aps.lookup(ssid_name);
                if (seen != null) {
                    if (ap.strength > seen.strength) {
                        best_aps.replace(ssid_name, ap);
                    }
                } else {
                    best_aps.insert(ssid_name, ap);
                }
            }

            WifiMenuOption? active_option = null;

            foreach (var ap in best_aps.get_values()) {
                var opt = new WifiMenuOption(wifi_device, ap, this);
                string ap_name = ap_to_name(ap);
                string active_name = active_ap != null ? ap_to_name(active_ap) : "";

                if (active_ap != null && ap_name == active_name) {
                    active_option = opt;
                    continue;
                }
                wifi_menu.options.append(opt);
            }

            if (active_option != null) {
                wifi_menu.options.prepend(active_option);
            }
        }

        public void collapse_all_password_entries(WifiMenuOption active_option) {
            Widget? child = wifi_menu.options.get_first_child();
            while (child != null) {
                if (child is WifiMenuOption && child != active_option) {
                    ((WifiMenuOption) child).revealer.set_reveal_child(false);
                }
                child = child.get_next_sibling();
            }
        }

        public static string ap_to_name(NM.AccessPoint ap) {
            var ssid = ap.get_ssid();
            if (ssid == null) return "Unknown Network";
            unowned uint8[] data = ssid.get_data();
            char[] chars = new char[data.length + 1];
            for (int i = 0; i < data.length; i++) {
                chars[i] = (char)data[i];
            }
            chars[data.length] = '\0';
            return (string)chars;
        }
    }

    // --- Класс строки-опции выбора точки доступа ---

    public class WifiMenuOption : Box {
        private NM.DeviceWifi dev;
        private NM.AccessPoint ap;
        private WifiButton parent_button;

        private Button button;
        private Image strength_icon;
        private Image sec_icon;
        private Label ssid_label;
        private Image active_icon;
        private Spinner spinner;

        public Revealer revealer { get; private set; }
        private PasswordEntry password_entry;
        private bool has_sec = false;

        public WifiMenuOption(NM.DeviceWifi dev, NM.AccessPoint ap, WifiButton parent) {
            GLib.Object(orientation: Orientation.VERTICAL, spacing: 0); 
            this.dev = dev;
            this.ap = ap;
            this.parent_button = parent;

            init_layout();
            update_status();
        }

        private void init_layout() {
            var row = new Box(Orientation.HORIZONTAL, 0);

            strength_icon = new Image();
            sec_icon = new Image();
            sec_icon.pixel_size = 10;

            active_icon = new Image.from_icon_name("object-select-symbolic");
            active_icon.visible = false;

            spinner = new Spinner();
            spinner.visible = false;

            ssid_label = new Label("");
            ssid_label.halign = Align.START;
            ssid_label.hexpand = true;
            ssid_label.xalign = 0.0f;
            ssid_label.ellipsize = Pango.EllipsizeMode.END;

            row.append(strength_icon);
            row.append(sec_icon);
            row.append(ssid_label);
            row.append(active_icon);
            row.append(spinner);

            button = new Button();
            button.set_child(row);
            this.append(button);

            var password_entry_container = new Box(Orientation.HORIZONTAL, 0);
            password_entry_container.add_css_class("quick-settings-menu-option-wifi-password-entry-container");

            var password_icon = new Image.from_icon_name("dialog-password-symbolic");
            password_entry_container.append(password_icon);

            password_entry = new PasswordEntry();
            password_entry.hexpand = true;
            password_entry.show_peek_icon = true;
            password_entry_container.append(password_entry);

            revealer = new Revealer();
            revealer.transition_type = RevealerTransitionType.SWING_DOWN;
            revealer.transition_duration = 350;
            revealer.set_child(password_entry_container);
            this.append(revealer);

            button.clicked.connect(on_row_clicked);
            password_entry.activate.connect(on_password_submitted);
        }

        private void update_status() {
            NM.DeviceState state = dev.state;
            var active_ap = dev.active_access_point;
            bool is_active_ap = (active_ap != null && WifiButton.ap_to_name(active_ap) == WifiButton.ap_to_name(ap));
            string option_ssid = WifiButton.ap_to_name(ap);

            // Проверяем, идет ли сейчас подключение именно к этой сети
            bool is_connecting_this = (parent_button.connecting_ssid != null && parent_button.connecting_ssid == option_ssid);

            has_sec = (ap.wpa_flags != 0 || ap.rsn_flags != 0);

            if (has_sec) {
                sec_icon.set_from_icon_name("network-wireless-encrypted-symbolic");
            } else {
                sec_icon.set_from_icon_name(null);
            }

            ssid_label.set_text(option_ssid);
            strength_icon.set_from_icon_name(Services.NetworkManagerService.ap_strength_to_icon_name(ap.strength));

            if (is_active_ap || is_connecting_this) {
                if (state == NM.DeviceState.ACTIVATED && !is_connecting_this) {
                    active_icon.visible = true;
                    spinner.stop();
                    spinner.visible = false;
                } else if (state == NM.DeviceState.FAILED) {
                    active_icon.visible = false;
                    spinner.stop();
                    spinner.visible = false;
                } else {
                    active_icon.visible = false;
                    spinner.visible = true;
                    spinner.start();
                }
            } else {
                active_icon.visible = false;
                spinner.stop();
                spinner.visible = false;
            }
        }

        // Проверяет, сохранен ли пароль для этой сети в системе NetworkManager
        private NM.Connection? find_existing_connection(string ssid) {
            if (parent_button.nm_client == null) return null;
            try {
                var connections = parent_button.nm_client.get_connections();
                for (int i = 0; i < connections.length; i++) {
                    var conn = connections[i];
                    var setting = conn.get_setting_by_name("802-11-wireless") as NM.SettingWireless;
                    if (setting != null) {
                        var conn_ssid = setting.get_ssid();
                        if (conn_ssid != null) {
                            unowned uint8[] data = conn_ssid.get_data();
                            char[] chars = new char[data.length + 1];
                            for (int j = 0; j < data.length; j++) {
                                chars[j] = (char)data[j];
                            }
                            chars[data.length] = '\0';
                            string conn_ssid_str = (string)chars;
                            if (conn_ssid_str == ssid) {
                                return conn;
                            }
                        }
                    }
                }
            } catch (Error e) {
                // Игнорируем
            }
            return null;
        }

        private void on_row_clicked() {
            string ssid = WifiButton.ap_to_name(ap);
            var existing_connection = find_existing_connection(ssid);

            if (existing_connection != null) {
                connect_to_existing_ap.begin(existing_connection);
            } else if (has_sec) {
                bool is_visible = revealer.get_reveal_child();
                if (is_visible) {
                    revealer.set_reveal_child(false);
                } else {
                    parent_button.collapse_all_password_entries(this);
                    revealer.set_reveal_child(true);
                    password_entry.grab_focus();
                }
            } else {
                connect_to_ap.begin(null);
            }
        }

        private void on_password_submitted() {
            string password = password_entry.get_text();
            password_entry.set_text("");
            revealer.set_reveal_child(false);

            connect_to_ap.begin(password);
        }

        // Асинхронное нативное подключение по сохраненному профилю libnm
        private async void connect_to_existing_ap(NM.Connection existing_connection) {
            if (parent_button.nm_client == null) return;
            
            string ssid = WifiButton.ap_to_name(ap);
            parent_button.connecting_ssid = ssid; // Устанавливаем трекер подключения
            parent_button.refresh_wifi_list();

            try {
                yield parent_button.nm_client.activate_connection_async(existing_connection, dev, ap.get_path(), null);
                parent_button.wifi_menu.banner.set_reveal_child(false);
            } catch (Error e) {
                warning("WifiModule: Failed to activate existing connection %s: %s", ssid, e.message);
                parent_button.collapse_all_password_entries(this);
                revealer.set_reveal_child(true);
                password_entry.grab_focus();
                parent_button.wifi_menu.banner.set_reveal_child(true);
            }

            parent_button.connecting_ssid = null; // Сбрасываем трекер
            parent_button.refresh_wifi_list();
        }

        // Асинхронное нативное создание профиля и его активация в libnm
        private async void connect_to_ap(string? password) {
            if (parent_button.nm_client == null) return;
            
            string ssid = WifiButton.ap_to_name(ap);
            parent_button.connecting_ssid = ssid; // Устанавливаем трекер подключения
            parent_button.refresh_wifi_list();

            try {
                var connection = (NM.SimpleConnection) GLib.Object.new (typeof (NM.SimpleConnection));

                // 1. Connection setting
                var s_con = new NM.SettingConnection();
                s_con.set_property("id", ssid);
                s_con.set_property("type", "802-11-wireless");
                connection.add_setting(s_con);

                // 2. Wireless setting
                var s_wifi = new NM.SettingWireless();
                s_wifi.set_property("ssid", ap.get_ssid());
                s_wifi.set_property("mode", "infrastructure");
                connection.add_setting(s_wifi);

                // 3. Security setting (WPA/WPA2/RSN PSK)
                if (has_sec && password != null) {
                    var s_wsec = new NM.SettingWirelessSecurity();
                    s_wsec.set_property("key-mgmt", "wpa-psk");
                    s_wsec.set_property("psk", password);
                    connection.add_setting(s_wsec);
                }

                // 4. IP Configurations
                var s_ip4 = new NM.SettingIP4Config();
                s_ip4.set_property("method", "auto");
                connection.add_setting(s_ip4);

                var s_ip6 = new NM.SettingIP6Config();
                s_ip6.set_property("method", "auto");
                connection.add_setting(s_ip6);

                yield parent_button.nm_client.add_and_activate_connection_async(connection, dev, ap.get_path(), null);
                parent_button.wifi_menu.banner.set_reveal_child(false);

            } catch (Error e) {
                warning("WifiModule: Failed to connect and save connection to %s: %s", ssid, e.message);
                parent_button.wifi_menu.banner.set_reveal_child(true);
            }

            parent_button.connecting_ssid = null; // Сбрасываем трекер
            parent_button.refresh_wifi_list();
        }
    }
}
using Gtk;
using GLib;

namespace WayShell.QS {

    [DBus (name = "org.bluez.Adapter1")]
    interface BluezAdapter : GLib.Object {
        [DBus (name = "StartDiscovery")]
        public abstract async void start_discovery () throws GLib.Error;
        [DBus (name = "StopDiscovery")]
        public abstract async void stop_discovery () throws GLib.Error;
        public abstract bool powered { get; set; }
        public abstract bool discovering { get; }
    }

    [DBus (name = "org.bluez.Device1")]
    interface BluezDevice : GLib.Object {
        [DBus (name = "Connect")]
        public abstract async void connect_device () throws GLib.Error;
        [DBus (name = "Disconnect")]
        public abstract async void disconnect_device () throws GLib.Error;
        public abstract string name { owned get; }
        public abstract string alias { owned get; }
        public abstract string address { owned get; }
        public abstract bool connected { get; }
    }

    [DBus (name = "org.freedesktop.DBus.ObjectManager")]
    interface BluezObjectManager : GLib.Object {
        [DBus (name = "GetManagedObjects")]
        public abstract HashTable<string, HashTable<string, HashTable<string, Variant>>> get_managed_objects () throws GLib.Error;
    }

    public class BluetoothButton : GridButton {
        private MenuWidget bt_menu;
        private Button scan_btn;
        private bool is_scanning = false;

        public BluetoothButton() {
            // Создаем меню для этого модуля
            var menu = new MenuWidget("Bluetooth Devices", "bluetooth-active-symbolic", true);
            menu.set_size_request(-1, 250);

            // Инициализируем базовый GridButton
            base(ButtonType.BLUETOOTH, "Bluetooth", "Off", "bluetooth-active-symbolic", menu);
            this.bt_menu = menu;

            // Кнопка запуска сканирования в шапке списка устройств
            scan_btn = new Button.from_icon_name("view-refresh-symbolic");
            scan_btn.valign = Align.CENTER;
            scan_btn.halign = Align.END;
            scan_btn.hexpand = true;
            scan_btn.clicked.connect(() => {
                trigger_scan.begin();
            });
            bt_menu.title_container.append(scan_btn);

            toggle.clicked.connect(on_bluetooth_toggle);
            reveal_changed.connect((is_revealed) => {
                if (is_revealed) refresh_bluetooth_devices();
            });

            // Запускаем мягкий таймер опроса состояния
            GLib.Timeout.add(1000, () => {
                return update_bluetooth_status();
            });
        }

        private BluezAdapter? get_adapter(out string adapter_path) {
            adapter_path = "/org/bluez/hci0";
            try {
                var manager = Bus.get_proxy_sync<BluezObjectManager> (BusType.SYSTEM, "org.bluez", "/");
                var objects = manager.get_managed_objects ();
                foreach (var path in objects.get_keys ()) {
                    var interfaces = objects.lookup (path);
                    if (interfaces.contains ("org.bluez.Adapter1")) {
                        adapter_path = path;
                        break;
                    }
                }
                return Bus.get_proxy_sync<BluezAdapter> (BusType.SYSTEM, "org.bluez", adapter_path);
            } catch (Error e) {
                warning ("BlueZ: Failed to find adapter: %s", e.message);
                return null;
            }
        }

        private void on_bluetooth_toggle() {
            string path;
            var adapter = get_adapter(out path);
            if (adapter != null) {
                try {
                    adapter.powered = !adapter.powered;
                } catch (Error e) {
                    critical("BlueZ: Failed to toggle power state: %s", e.message);
                }
            }
        }

        private bool update_bluetooth_status() {
            string path;
            var adapter = get_adapter(out path);
            if (adapter != null) {
                try {
                    bool is_powered = adapter.powered;
                    set_toggled(is_powered);
                    subtitle.set_text(is_powered ? "On" : "Off");
                } catch (Error e) {
                    set_toggled(false);
                    subtitle.set_text("Off");
                }
            } else {
                set_toggled(false);
                subtitle.set_text("Off");
            }
            return true; 
        }

        private async void trigger_scan() {
            if (is_scanning) return;
            is_scanning = true;

            string path;
            var adapter = get_adapter(out path);
            if (adapter == null) {
                is_scanning = false;
                return;
            }

            try {
                scan_btn.set_icon_name("process-working-symbolic");
                yield adapter.start_discovery();

                uint timer_id = GLib.Timeout.add(2000, () => {
                    refresh_bluetooth_devices();
                    return is_scanning;
                });

                GLib.Timeout.add_seconds(10, () => {
                    stop_scan.begin(adapter);
                    GLib.Source.remove(timer_id);
                    return false;
                });

            } catch (Error e) {
                warning("BlueZ: Failed to start discovery: %s", e.message);
                is_scanning = false;
                scan_btn.set_icon_name("view-refresh-symbolic");
            }
        }

        private async void stop_scan(BluezAdapter adapter) {
            try {
                yield adapter.stop_discovery();
            } catch (Error e) {
                // Игнорируем
            }
            is_scanning = false;
            scan_btn.set_icon_name("view-refresh-symbolic");
            refresh_bluetooth_devices();
        }

        private void refresh_bluetooth_devices() {
            try {
                Widget? child;
                while ((child = bt_menu.options.get_first_child()) != null) {
                    bt_menu.options.remove(child);
                }

                var manager = Bus.get_proxy_sync<BluezObjectManager> (BusType.SYSTEM, "org.bluez", "/");
                var objects = manager.get_managed_objects ();

                foreach (var path in objects.get_keys()) {
                    var interfaces = objects.lookup(path);
                    if (interfaces.contains("org.bluez.Device1")) {
                        var dev_props = interfaces.lookup("org.bluez.Device1");
                        if (dev_props == null) continue;

                        string name = "Unknown Device";
                        var alias_var = dev_props.lookup("Alias");
                        if (alias_var != null) {
                            name = alias_var.get_string();
                        } else {
                            var name_var = dev_props.lookup("Name");
                            if (name_var != null) name = name_var.get_string();
                        }

                        bool connected = false;
                        var conn_var = dev_props.lookup("Connected");
                        if (conn_var != null) {
                            connected = conn_var.get_boolean();
                        }

                        int battery_percent = -1;
                        if (interfaces.contains("org.bluez.Battery1")) {
                            var bat_props = interfaces.lookup("org.bluez.Battery1");
                            if (bat_props != null) {
                                var pct_var = bat_props.lookup("Percentage");
                                if (pct_var != null) {
                                    battery_percent = (int) pct_var.get_byte();
                                }
                            }
                        }

                        string device_path = path;

                        var dev_btn = new Button();
                        dev_btn.add_css_class("quick-settings-menu-option");

                        var btn_box = new Box(Orientation.HORIZONTAL, 12);
                        btn_box.hexpand = true;

                        var name_lbl = new Label(name);
                        name_lbl.halign = Align.START;
                        name_lbl.hexpand = true;
                        name_lbl.xalign = 0.0f;
                        btn_box.append(name_lbl);

                        if (connected) {
                            string status_text = "Connected";
                            if (battery_percent != -1) {
                                status_text += @" ($(battery_percent)%)";
                            }
                            var status_lbl = new Label(status_text);
                            status_lbl.halign = Align.END;
                            status_lbl.add_css_class("active-icon-activated");
                            btn_box.append(status_lbl);
                        }

                        dev_btn.set_child(btn_box);

                        dev_btn.clicked.connect(() => {
                            toggle_device_connection.begin(device_path, connected, name);
                        });

                        bt_menu.options.append(dev_btn);
                    }
                }
            } catch (Error e) {
                warning("BlueZ: Failed to list devices: %s", e.message);
            }
        }

        private async void toggle_device_connection(string path, bool is_connected, string name) {
            try {
                var device = yield Bus.get_proxy<BluezDevice> (BusType.SYSTEM, "org.bluez", path);
                if (is_connected) {
                    yield device.disconnect_device();
                } else {
                    yield device.connect_device();
                }
                refresh_bluetooth_devices();
            } catch (Error err) {
                warning("BlueZ: Failed to toggle connection for %s: %s", name, err.message);
            }
        }
    }
}
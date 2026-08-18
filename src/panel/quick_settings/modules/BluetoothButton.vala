// Путь: src/panel/quick_settings/modules/BluetoothButton.vala
using Gtk;
using GLib;

namespace WayShell.QS {

    [DBus (name = "org.bluez.Adapter1")]
    interface BluezAdapter : GLib.Object {
        [DBus (name = "StartDiscovery")]
        public abstract async void start_discovery () throws GLib.Error;
        [DBus (name = "StopDiscovery")]
        public abstract async void stop_discovery () throws GLib.Error;
        [DBus (name = "RemoveDevice")]
        public abstract async void remove_device (ObjectPath device) throws GLib.Error;
        public abstract bool powered { get; set; }
        public abstract bool discovering { get; }
    }

    [DBus (name = "org.bluez.Device1")]
    interface BluezDevice : GLib.Object {
        [DBus (name = "Connect")]
        public abstract async void connect_device () throws GLib.Error;
        [DBus (name = "Disconnect")]
        public abstract async void disconnect_device () throws GLib.Error;
        [DBus (name = "Pair")]
        public abstract async void pair_device () throws GLib.Error;
        public abstract string name { owned get; }
        public abstract string alias { owned get; }
        public abstract string address { owned get; }
        public abstract string icon { owned get; }
        public abstract bool paired { get; }
        public abstract bool connected { get; }
    }

    [DBus (name = "org.freedesktop.DBus.ObjectManager")]
    interface BluezObjectManager : GLib.Object {
        [DBus (name = "GetManagedObjects")]
        public abstract HashTable<string, HashTable<string, HashTable<string, Variant>>> get_managed_objects () throws GLib.Error;
    }

    public class BluetoothButton : GridButton {
        private MenuWidget bt_menu;
        private Gtk.Stack stack;
        private Gtk.StackSwitcher stack_switcher;

        private Box paired_list_box;
        private Box discover_list_box;
        private Spinner scan_spinner;
        private Button scan_btn;

        private bool is_scanning = false;
        private string? connecting_path = null;

        public static bool has_bluetooth_hardware() {
            var dir = File.new_for_path("/sys/class/bluetooth");
            if (!dir.query_exists()) return false;
            try {
                var enumerator = dir.enumerate_children(FileAttribute.STANDARD_NAME, FileQueryInfoFlags.NONE);
                if (enumerator.next_file() != null) {
                    return true;
                }
            } catch (Error e) {}
            return false;
        }

        public BluetoothButton() {
            var menu = new MenuWidget("Bluetooth", "bluetooth-active-symbolic", false);
            menu.set_size_request(-1, 340);

            base(ButtonType.BLUETOOTH, "Bluetooth", "Off", "bluetooth-active-symbolic", menu);
            this.bt_menu = menu;

            scan_spinner = new Spinner();
            scan_spinner.visible = false;
            bt_menu.title_container.append(scan_spinner);

            scan_btn = new Button.from_icon_name("view-refresh-symbolic");
            scan_btn.valign = Align.CENTER;
            scan_btn.halign = Align.END;
            scan_btn.hexpand = true;
            scan_btn.clicked.connect(() => {
                trigger_scan.begin();
            });
            bt_menu.title_container.append(scan_btn);

            stack = new Gtk.Stack();
            stack.transition_type = StackTransitionType.SLIDE_LEFT_RIGHT;
            stack.transition_duration = 200;

            stack_switcher = new Gtk.StackSwitcher();
            stack_switcher.set_stack(stack);
            stack_switcher.halign = Align.CENTER;
            stack_switcher.margin_bottom = 6;
            bt_menu.options.append(stack_switcher);

            var paired_scroll = new ScrolledWindow();
            paired_scroll.vexpand = true;
            paired_scroll.set_policy(PolicyType.NEVER, PolicyType.AUTOMATIC);
            paired_list_box = new Box(Orientation.VERTICAL, 4);
            paired_scroll.set_child(paired_list_box);
            stack.add_titled(paired_scroll, "paired", "My Devices");

            var discover_scroll = new ScrolledWindow();
            discover_scroll.vexpand = true;
            discover_scroll.set_policy(PolicyType.NEVER, PolicyType.AUTOMATIC);
            discover_list_box = new Box(Orientation.VERTICAL, 4);
            discover_scroll.set_child(discover_list_box);
            stack.add_titled(discover_scroll, "discover", "Search");

            bt_menu.options.append(stack);

            stack.notify["visible-child-name"].connect(() => {
                if (stack.visible_child_name == "discover") {
                    trigger_scan.begin();
                }
            });

            toggle.clicked.connect(on_bluetooth_toggle);
            reveal_changed.connect((is_revealed) => {
                if (is_revealed) {
                    refresh_devices();
                    if (stack.visible_child_name == "discover") {
                        trigger_scan.begin();
                    }
                }
            });

            update_bluetooth_status();
            GLib.Timeout.add_seconds(3, () => {
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
                return null;
            }
        }

        private void on_bluetooth_toggle() {
            string path;
            var adapter = get_adapter(out path);
            bool current_powered = (adapter != null && adapter.powered);
            bool next_state = !current_powered;

            if (next_state) {
                Process.spawn_command_line_async("rfkill unblock bluetooth");
                Process.spawn_command_line_async("bluetoothctl power on");
                if (adapter != null) {
                    try { adapter.powered = true; } catch (Error e) {}
                }
            } else {
                Process.spawn_command_line_async("bluetoothctl power off");
                if (adapter != null) {
                    try { adapter.powered = false; } catch (Error e) {}
                }
            }

            set_toggled(next_state);
            subtitle.set_text(next_state ? "Ready" : "Off");
            icon.set_from_icon_name(next_state ? "bluetooth-active-symbolic" : "bluetooth-disabled-symbolic");

            GLib.Timeout.add(500, () => {
                update_bluetooth_status();
                refresh_devices();
                return false;
            });
        }

        private bool update_bluetooth_status() {
            string path;
            var adapter = get_adapter(out path);
            if (adapter == null) {
                set_toggled(false);
                subtitle.set_text("Off");
                icon.set_from_icon_name("bluetooth-disabled-symbolic");
                return true;
            }

            try {
                bool is_powered = adapter.powered;
                set_toggled(is_powered);

                if (!is_powered) {
                    subtitle.set_text("Off");
                    icon.set_from_icon_name("bluetooth-disabled-symbolic");
                    return true;
                }

                var manager = Bus.get_proxy_sync<BluezObjectManager> (BusType.SYSTEM, "org.bluez", "/");
                var objects = manager.get_managed_objects ();
                string? connected_name = null;
                int connected_battery = -1;

                foreach (var dev_path in objects.get_keys()) {
                    var ifaces = objects.lookup(dev_path);
                    if (ifaces.contains("org.bluez.Device1")) {
                        var dev_props = ifaces.lookup("org.bluez.Device1");
                        var conn_var = dev_props.lookup("Connected");
                        if (conn_var != null && conn_var.get_boolean()) {
                            var alias_var = dev_props.lookup("Alias") ?? dev_props.lookup("Name");
                            connected_name = alias_var != null ? alias_var.get_string() : "Connected";

                            if (ifaces.contains("org.bluez.Battery1")) {
                                var bat_props = ifaces.lookup("org.bluez.Battery1");
                                var pct_var = bat_props.lookup("Percentage");
                                if (pct_var != null) connected_battery = (int) pct_var.get_byte();
                            }
                            break;
                        }
                    }
                }

                if (connected_name != null) {
                    if (connected_battery >= 0) {
                        subtitle.set_text(@"$connected_name ($connected_battery%)");
                    } else {
                        subtitle.set_text(connected_name);
                    }
                    icon.set_from_icon_name("bluetooth-active-symbolic");
                } else {
                    subtitle.set_text("Ready");
                    icon.set_from_icon_name("bluetooth-active-symbolic");
                }
            } catch (Error e) {
                set_toggled(false);
                subtitle.set_text("Off");
            }
            return true;
        }

        private async void trigger_scan() {
            if (is_scanning) return;
            string path;
            var adapter = get_adapter(out path);
            if (adapter == null || !adapter.powered) return;

            is_scanning = true;
            scan_spinner.visible = true;
            scan_spinner.start();
            scan_btn.sensitive = false;

            try {
                yield adapter.start_discovery();
                
                uint poll_id = GLib.Timeout.add_seconds(2, () => {
                    refresh_devices();
                    return is_scanning;
                });

                GLib.Timeout.add_seconds(15, () => {
                    stop_scan.begin(adapter);
                    GLib.Source.remove(poll_id);
                    return false;
                });
            } catch (Error e) {
                is_scanning = false;
                scan_spinner.stop();
                scan_spinner.visible = false;
                scan_btn.sensitive = true;
            }
        }

        private async void stop_scan(BluezAdapter adapter) {
            try {
                yield adapter.stop_discovery();
            } catch (Error e) {}

            is_scanning = false;
            scan_spinner.stop();
            scan_spinner.visible = false;
            scan_btn.sensitive = true;
            refresh_devices();
        }

        public void refresh_devices() {
            Widget? child;
            while ((child = paired_list_box.get_first_child()) != null) paired_list_box.remove(child);
            while ((child = discover_list_box.get_first_child()) != null) discover_list_box.remove(child);

            try {
                var manager = Bus.get_proxy_sync<BluezObjectManager> (BusType.SYSTEM, "org.bluez", "/");
                var objects = manager.get_managed_objects ();

                int paired_count = 0;
                int discover_count = 0;

                foreach (var path in objects.get_keys()) {
                    var interfaces = objects.lookup(path);
                    if (!interfaces.contains("org.bluez.Device1")) continue;

                    var dev_props = interfaces.lookup("org.bluez.Device1");
                    if (dev_props == null) continue;

                    string name = "Unknown Device";
                    var alias_var = dev_props.lookup("Alias") ?? dev_props.lookup("Name");
                    if (alias_var != null) name = alias_var.get_string();

                    bool paired = false;
                    var paired_var = dev_props.lookup("Paired");
                    if (paired_var != null) paired = paired_var.get_boolean();

                    bool connected = false;
                    var conn_var = dev_props.lookup("Connected");
                    if (conn_var != null) connected = conn_var.get_boolean();

                    int battery_percent = -1;
                    if (interfaces.contains("org.bluez.Battery1")) {
                        var bat_props = interfaces.lookup("org.bluez.Battery1");
                        var pct_var = bat_props.lookup("Percentage");
                        if (pct_var != null) battery_percent = (int) pct_var.get_byte();
                    }

                    string icon_type = "bluetooth-active-symbolic";
                    var icon_var = dev_props.lookup("Icon");
                    if (icon_var != null) {
                        icon_type = map_device_icon(icon_var.get_string());
                    }

                    string device_path = path;

                    if (paired) {
                        paired_count++;
                        paired_list_box.append(create_paired_row(device_path, name, icon_type, connected, battery_percent));
                    } else {
                        if (name != "Unknown Device" && name != "") {
                            discover_count++;
                            discover_list_box.append(create_discover_row(device_path, name, icon_type));
                        }
                    }
                }

                if (paired_count == 0) {
                    var empty_lbl = new Label("No paired devices");
                    empty_lbl.add_css_class("dim-label");
                    empty_lbl.margin_top = 20;
                    paired_list_box.append(empty_lbl);
                }

                if (discover_count == 0) {
                    var empty_lbl = new Label(is_scanning ? "Searching for devices..." : "No devices found");
                    empty_lbl.add_css_class("dim-label");
                    empty_lbl.margin_top = 20;
                    discover_list_box.append(empty_lbl);
                }

            } catch (Error e) {
                warning("BlueZ: Failed to populate devices: %s", e.message);
            }
        }

        private Widget create_paired_row(string path, string name, string icon_name, bool connected, int battery) {
            var row = new Box(Orientation.HORIZONTAL, 8);
            row.add_css_class("quick-settings-menu-option");

            var icon_img = new Image.from_icon_name(icon_name);
            icon_img.pixel_size = 18;

            var name_lbl = new Label(name);
            name_lbl.halign = Align.START;
            name_lbl.hexpand = true;
            name_lbl.xalign = 0.0f;
            name_lbl.ellipsize = Pango.EllipsizeMode.END;

            row.append(icon_img);
            row.append(name_lbl);

            if (battery >= 0) {
                var bat_lbl = new Label(@"$(battery)%");
                bat_lbl.add_css_class("dim-label");
                row.append(bat_lbl);
            }

            bool is_connecting_this = (connecting_path != null && connecting_path == path);

            var status_lbl = new Label("");
            if (is_connecting_this) {
                status_lbl.set_text("Connecting...");
                status_lbl.add_css_class("dim-label");
                row.append(status_lbl);

                var spinner = new Spinner();
                spinner.visible = true;
                spinner.start();
                row.append(spinner);
            } else {
                status_lbl.set_text(connected ? "Connected" : "Disconnected");
                if (connected) status_lbl.add_css_class("active-icon-activated");
                else status_lbl.add_css_class("dim-label");
                row.append(status_lbl);
            }

            var btn = new Button();
            btn.set_child(row);
            if (is_connecting_this) btn.sensitive = false;

            btn.clicked.connect(() => {
                connecting_path = path;
                refresh_devices();
                toggle_connection.begin(path, connected, name, (obj, res) => {
                    connecting_path = null;
                    refresh_devices();
                });
            });

            var container = new Box(Orientation.HORIZONTAL, 4);
            container.append(btn);
            btn.hexpand = true;

            var unpair_btn = new Button.from_icon_name("user-trash-symbolic");
            unpair_btn.add_css_class("circular");
            unpair_btn.add_css_class("flat");
            unpair_btn.set_tooltip_text("Unpair device");
            unpair_btn.clicked.connect(() => {
                unpair_device.begin(path);
            });
            container.append(unpair_btn);

            return container;
        }

        private Widget create_discover_row(string path, string name, string icon_name) {
            var btn = new Button();
            btn.add_css_class("quick-settings-menu-option");

            var row = new Box(Orientation.HORIZONTAL, 8);
            var icon_img = new Image.from_icon_name(icon_name);
            icon_img.pixel_size = 18;

            var name_lbl = new Label(name);
            name_lbl.halign = Align.START;
            name_lbl.hexpand = true;
            name_lbl.xalign = 0.0f;
            name_lbl.ellipsize = Pango.EllipsizeMode.END;

            bool is_connecting_this = (connecting_path != null && connecting_path == path);

            var pair_lbl = new Label(is_connecting_this ? "Pairing..." : "Pair");
            if (is_connecting_this) pair_lbl.add_css_class("dim-label");
            else pair_lbl.add_css_class("active-icon-activated");

            row.append(icon_img);
            row.append(name_lbl);
            row.append(pair_lbl);

            if (is_connecting_this) {
                var spinner = new Spinner();
                spinner.visible = true;
                spinner.start();
                row.append(spinner);
                btn.sensitive = false;
            }

            btn.set_child(row);

            btn.clicked.connect(() => {
                connecting_path = path;
                refresh_devices();
                pair_and_connect.begin(path, name, (obj, res) => {
                    connecting_path = null;
                    refresh_devices();
                });
            });

            return btn;
        }

        private async void toggle_connection(string path, bool is_connected, string name) {
            try {
                var device = yield Bus.get_proxy<BluezDevice> (BusType.SYSTEM, "org.bluez", path);
                if (is_connected) {
                    yield device.disconnect_device();
                } else {
                    yield device.connect_device();
                }
                update_bluetooth_status();
            } catch (Error e) {
                warning("BlueZ: Failed to toggle connection for %s: %s", name, e.message);
            }
        }

        private async void pair_and_connect(string path, string name) {
            try {
                var device = yield Bus.get_proxy<BluezDevice> (BusType.SYSTEM, "org.bluez", path);
                yield device.pair_device();
                yield device.connect_device();
                stack.set_visible_child_name("paired");
                update_bluetooth_status();
            } catch (Error e) {
                warning("BlueZ: Failed to pair %s: %s", name, e.message);
            }
        }

        private async void unpair_device(string device_path) {
            string adapter_path;
            var adapter = get_adapter(out adapter_path);
            if (adapter != null) {
                try {
                    yield adapter.remove_device(new ObjectPath(device_path));
                    refresh_devices();
                    update_bluetooth_status();
                } catch (Error e) {
                    warning("BlueZ: Failed to remove device: %s", e.message);
                }
            }
        }

        private string map_device_icon(string bluez_icon) {
            switch (bluez_icon) {
                case "audio-card":
                case "audio-headphones":
                case "audio-headset":
                    return "audio-headphones-symbolic";
                case "input-gaming":
                    return "input-gaming-symbolic";
                case "input-keyboard":
                    return "input-keyboard-symbolic";
                case "input-mouse":
                    return "input-mouse-symbolic";
                case "phone":
                    return "phone-symbolic";
                default:
                    return "bluetooth-active-symbolic";
            }
        }
    }
}
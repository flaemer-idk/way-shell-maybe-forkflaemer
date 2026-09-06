using Gtk;
using GLib;
using WayShell.Services;

namespace WayShell.QS {

    public class BluetoothButton : GridButton {
        private MenuWidget bt_menu;
        private Gtk.Stack stack;
        private Gtk.StackSwitcher stack_switcher;

        private Box paired_list_box;
        private Box discover_list_box;
        private Spinner scan_spinner;
        private Button scan_btn;

        private BluetoothService bt;
        private string? busy_path = null;
        private uint scan_stop_id = 0;

        public signal void state_changed();

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
            var menu = new MenuWidget(_("Bluetooth"), "bluetooth-active-symbolic", false);
            menu.set_size_request(-1, 340);

            base(ButtonType.BLUETOOTH, _("Bluetooth"), _("Off"), "bluetooth-active-symbolic", menu);
            this.bt_menu = menu;
            this.bt = BluetoothService.get_global();

            scan_spinner = new Spinner();
            scan_spinner.visible = false;
            bt_menu.title_container.append(scan_spinner);

            scan_btn = new Button.from_icon_name("view-refresh-symbolic");
            scan_btn.valign = Align.CENTER;
            scan_btn.halign = Align.END;
            scan_btn.hexpand = true;
            scan_btn.tooltip_text = _("Search for devices");
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
            stack.add_titled(paired_scroll, "paired", _("My Devices"));

            var discover_scroll = new ScrolledWindow();
            discover_scroll.vexpand = true;
            discover_scroll.set_policy(PolicyType.NEVER, PolicyType.AUTOMATIC);
            discover_list_box = new Box(Orientation.VERTICAL, 4);
            discover_scroll.set_child(discover_list_box);
            stack.add_titled(discover_scroll, "discover", _("Search"));

            bt_menu.options.append(stack);

            stack.notify["visible-child-name"].connect(() => {
                if (stack.visible_child_name == "discover") {
                    trigger_scan.begin();
                } else if (bt.discovering) {
                    stop_scan.begin();
                }
            });

            // Состояние приходит сигналами BlueZ. Таймера на 3 секунды с
            // синхронным GetManagedObjects в UI-потоке больше нет.
            bt.changed.connect(update_bluetooth_status);
            bt.devices_changed.connect(refresh_devices);
            bt.notify["discovering"].connect(sync_scan_ui);
            // Grid слушает state_changed, чтобы пересобрать раскладку кнопок.
            // Дёргать его на каждое свойство BlueZ незачем — состав кнопок
            // меняется только вместе с появлением адаптера.
            bt.notify["has-adapter"].connect(() => { state_changed(); });

            toggle.clicked.connect(on_bluetooth_toggle);
            reveal_changed.connect((is_revealed) => {
                if (is_revealed) {
                    refresh_devices();
                    if (stack.visible_child_name == "discover") {
                        trigger_scan.begin();
                    }
                } else if (bt.discovering) {
                    // Сканирование жрёт радио и батарею — гасим вместе с меню.
                    stop_scan.begin();
                }
            });

            update_bluetooth_status();
            refresh_devices();
        }

        private void on_bluetooth_toggle() {
            bool next_state = !bt.powered;

            // Оптимистичный UI: BlueZ ответит своим PropertiesChanged, и
            // update_bluetooth_status() приведёт вид к реальному состоянию.
            set_toggled(next_state);
            subtitle.set_text(next_state ? _("Ready") : _("Off"));
            icon.set_from_icon_name(next_state ? "bluetooth-active-symbolic" : "bluetooth-disabled-symbolic");

            bt.request_powered(next_state);
        }

        public void update_bluetooth_status() {
            if (!bt.has_adapter || !bt.powered) {
                set_toggled(false);
                subtitle.set_text(_("Off"));
                icon.set_from_icon_name("bluetooth-disabled-symbolic");
                return;
            }

            set_toggled(true);
            icon.set_from_icon_name("bluetooth-active-symbolic");

            var dev = bt.get_connected_device();
            if (dev == null) {
                subtitle.set_text(_("Ready"));
                return;
            }

            string name = dev.alias == "" ? _("Connected") : dev.alias;
            if (dev.battery >= 0) {
                subtitle.set_text(@"$name ($(dev.battery)%)");
            } else {
                subtitle.set_text(name);
            }
        }

        private void sync_scan_ui() {
            scan_spinner.visible = bt.discovering;
            if (bt.discovering) scan_spinner.start();
            else scan_spinner.stop();
            scan_btn.sensitive = !bt.discovering;
            refresh_devices();
        }

        private async void trigger_scan() {
            if (bt.discovering || !bt.powered) return;

            try {
                yield bt.start_discovery();
            } catch (Error e) {
                warning("BlueZ: сканирование не началось: %s", e.message);
                return;
            }

            // Автостоп через 15 секунд. Раньше рядом жил ещё таймер на 2 секунды,
            // перерисовывавший список вслепую; теперь список обновляют
            // InterfacesAdded/PropertiesChanged.
            if (scan_stop_id != 0) Source.remove(scan_stop_id);
            scan_stop_id = Timeout.add_seconds(15, () => {
                scan_stop_id = 0;
                stop_scan.begin();
                return false;
            });
        }

        private async void stop_scan() {
            if (scan_stop_id != 0) {
                Source.remove(scan_stop_id);
                scan_stop_id = 0;
            }
            try {
                yield bt.stop_discovery();
            } catch (Error e) {
                // Discovery мог остановиться сам (адаптер выключили) — не шумим.
                debug("BlueZ: остановка сканирования: %s", e.message);
            }
        }

        public void refresh_devices() {
            Widget? child;
            while ((child = paired_list_box.get_first_child()) != null) paired_list_box.remove(child);
            while ((child = discover_list_box.get_first_child()) != null) discover_list_box.remove(child);

            int paired_count = 0;
            int discover_count = 0;

            foreach (var dev in bt.get_devices()) {
                string name = dev.alias;
                string icon_type = map_device_icon(dev.icon);

                if (dev.paired) {
                    paired_count++;
                    if (name == "") name = _("Unknown Device");
                    paired_list_box.append(create_paired_row(dev.path, name, icon_type,
                                                             dev.connected, dev.battery));
                } else if (name != "") {
                    // Безымянные устройства при сканировании — это чужие
                    // телефоны и наушники в радиусе, толку от них в списке нет.
                    discover_count++;
                    discover_list_box.append(create_discover_row(dev.path, name, icon_type));
                }
            }

            if (paired_count == 0) {
                var empty_lbl = new Label(_("No paired devices"));
                empty_lbl.add_css_class("dim-label");
                empty_lbl.margin_top = 20;
                paired_list_box.append(empty_lbl);
            }

            if (discover_count == 0) {
                var empty_lbl = new Label(bt.discovering ? _("Searching for devices...") : _("No devices found"));
                empty_lbl.add_css_class("dim-label");
                empty_lbl.margin_top = 20;
                discover_list_box.append(empty_lbl);
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

            bool is_busy_this = (busy_path != null && busy_path == path);

            var status_lbl = new Label("");
            if (is_busy_this) {
                status_lbl.set_text(connected ? _("Disconnecting...") : _("Connecting..."));
                status_lbl.add_css_class("dim-label");
                row.append(status_lbl);

                var spinner = new Spinner();
                spinner.visible = true;
                spinner.start();
                row.append(spinner);
            } else {
                status_lbl.set_text(connected ? _("Connected") : _("Disconnected"));
                if (connected) status_lbl.add_css_class("active-icon-activated");
                else status_lbl.add_css_class("dim-label");
                row.append(status_lbl);
            }

            var btn = new Button();
            btn.set_child(row);
            btn.tooltip_text = connected ? _("Disconnect %s").printf(name) : _("Connect %s").printf(name);
            if (is_busy_this) btn.sensitive = false;

            btn.clicked.connect(() => {
                busy_path = path;
                refresh_devices();
                toggle_connection.begin(path, connected, name, (obj, res) => {
                    busy_path = null;
                    refresh_devices();
                });
            });

            var container = new Box(Orientation.HORIZONTAL, 4);
            container.append(btn);
            btn.hexpand = true;

            var unpair_btn = new Button.from_icon_name("user-trash-symbolic");
            unpair_btn.add_css_class("circular");
            unpair_btn.add_css_class("flat");
            unpair_btn.set_tooltip_text(_("Unpair device"));
            unpair_btn.update_property(Gtk.AccessibleProperty.LABEL, _("Unpair device"), -1);
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

            bool is_busy_this = (busy_path != null && busy_path == path);

            var pair_lbl = new Label(is_busy_this ? _("Pairing...") : _("Pair"));
            if (is_busy_this) pair_lbl.add_css_class("dim-label");
            else pair_lbl.add_css_class("active-icon-activated");

            row.append(icon_img);
            row.append(name_lbl);
            row.append(pair_lbl);

            if (is_busy_this) {
                var spinner = new Spinner();
                spinner.visible = true;
                spinner.start();
                row.append(spinner);
                btn.sensitive = false;
            }

            btn.set_child(row);
            btn.tooltip_text = _("Pair %s").printf(name);

            btn.clicked.connect(() => {
                busy_path = path;
                refresh_devices();
                pair_and_connect.begin(path, name, (obj, res) => {
                    busy_path = null;
                    refresh_devices();
                });
            });

            return btn;
        }

        private async void toggle_connection(string path, bool is_connected, string name) {
            try {
                if (is_connected) {
                    yield bt.disconnect_device(path);
                } else {
                    yield bt.connect_device(path);
                }
            } catch (Error e) {
                warning("BlueZ: Failed to toggle connection for %s: %s", name, e.message);
            }
        }

        private async void pair_and_connect(string path, string name) {
            try {
                yield bt.pair_device(path);
                yield bt.connect_device(path);
                stack.set_visible_child_name("paired");
            } catch (Error e) {
                warning("BlueZ: Failed to pair %s: %s", name, e.message);
            }
        }

        private async void unpair_device(string device_path) {
            try {
                yield bt.remove_device(device_path);
            } catch (Error e) {
                warning("BlueZ: Failed to remove device: %s", e.message);
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

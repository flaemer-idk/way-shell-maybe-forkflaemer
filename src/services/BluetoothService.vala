using GLib;

namespace WayShell.Services {

    // Одно устройство BlueZ в кэше сервиса.
    public class BluetoothDevice : GLib.Object {
        public string path;
        public string alias = "";
        public string icon = "";
        public bool paired = false;
        public bool connected = false;
        public int battery = -1; // -1 — BlueZ не сообщает заряд

        public BluetoothDevice (string path) {
            this.path = path;
        }
    }

    // Единственная точка общения с BlueZ.
    //
    // Раньше BluetoothButton держал Bus.get_proxy_sync + GetManagedObjects в
    // таймере на 3 секунды прямо в UI-потоке: любое подвисание BlueZ вешало всю
    // оболочку. Здесь всё асинхронно, а состояние живёт в кэше, который
    // обновляют сигналы BlueZ — InterfacesAdded/InterfacesRemoved на
    // ObjectManager и PropertiesChanged на всех объектах org.bluez.
    // Поллинга нет.
    public class BluetoothService : GLib.Object {
        private const string BLUEZ = "org.bluez";
        private const string ADAPTER_IFACE = "org.bluez.Adapter1";
        private const string DEVICE_IFACE = "org.bluez.Device1";
        private const string BATTERY_IFACE = "org.bluez.Battery1";
        private const string PROPS_IFACE = "org.freedesktop.DBus.Properties";
        private const string OM_IFACE = "org.freedesktop.DBus.ObjectManager";

        // Connect/Pair на BlueZ идут долго: дефолтные 25 секунд GDBus реально
        // не хватает на сопряжение с наушниками.
        private const int OP_TIMEOUT_MS = 60000;

        private static BluetoothService? global = null;

        private DBusConnection? conn = null;
        private string? adapter_path = null;
        private HashTable<string, BluetoothDevice> devices;

        private uint name_watch = 0;
        private uint sub_added = 0;
        private uint sub_removed = 0;
        private uint sub_props = 0;

        // Есть ли у BlueZ адаптер. Не путать с наличием железа: пока bluetoothd
        // не поднялся, адаптера нет, а железо есть.
        public bool has_adapter { get; private set; default = false; }
        public bool powered { get; private set; default = false; }
        public bool discovering { get; private set; default = false; }

        // Состояние адаптера или подключённого устройства (для заголовка кнопки).
        public signal void changed ();
        // Состав или отображаемые свойства устройств (для списка в меню).
        public signal void devices_changed ();

        public static BluetoothService get_global () {
            if (global == null) global = new BluetoothService ();
            return global;
        }

        private BluetoothService () {
            devices = new HashTable<string, BluetoothDevice> (str_hash, str_equal);

            Bus.get.begin (BusType.SYSTEM, null, (obj, res) => {
                try {
                    conn = Bus.get.end (res);
                } catch (Error e) {
                    warning ("BluetoothService: нет системной шины: %s", e.message);
                    return;
                }
                subscribe ();
                // BlueZ может подняться позже нас и умереть раньше — следим за именем.
                name_watch = Bus.watch_name_on_connection (conn, BLUEZ,
                                                           BusNameWatcherFlags.NONE,
                                                           on_bluez_appeared,
                                                           on_bluez_vanished);
            });
        }

        ~BluetoothService () {
            if (conn == null) return;
            if (sub_added != 0) conn.signal_unsubscribe (sub_added);
            if (sub_removed != 0) conn.signal_unsubscribe (sub_removed);
            if (sub_props != 0) conn.signal_unsubscribe (sub_props);
            if (name_watch != 0) Bus.unwatch_name (name_watch);
        }

        private void subscribe () {
            sub_added = conn.signal_subscribe (BLUEZ, OM_IFACE, "InterfacesAdded",
                                              null, null, DBusSignalFlags.NONE,
                                              on_interfaces_added);
            sub_removed = conn.signal_subscribe (BLUEZ, OM_IFACE, "InterfacesRemoved",
                                                 null, null, DBusSignalFlags.NONE,
                                                 on_interfaces_removed);
            // object_path == null: свойства нужны и от адаптера, и от каждого
            // устройства, а путей заранее не знаем.
            sub_props = conn.signal_subscribe (BLUEZ, PROPS_IFACE, "PropertiesChanged",
                                               null, null, DBusSignalFlags.NONE,
                                               on_properties_changed);
        }

        private void on_bluez_appeared (DBusConnection c, string name, string owner) {
            reload_objects ();
        }

        private void on_bluez_vanished (DBusConnection c, string name) {
            devices.remove_all ();
            adapter_path = null;
            has_adapter = false;
            powered = false;
            discovering = false;
            changed ();
            devices_changed ();
        }

        // Полная перевычитка дерева объектов. Дорогая, поэтому только на
        // появление bluetoothd — дальше состояние держится сигналами.
        private void reload_objects () {
            if (conn == null) return;
            conn.call.begin (BLUEZ, "/", OM_IFACE, "GetManagedObjects", null,
                             new VariantType ("(a{oa{sa{sv}}})"),
                             DBusCallFlags.NONE, -1, null, (obj, res) => {
                Variant reply;
                try {
                    reply = conn.call.end (res);
                } catch (Error e) {
                    warning ("BluetoothService: GetManagedObjects: %s", e.message);
                    return;
                }

                devices.remove_all ();
                adapter_path = null;
                has_adapter = false;
                powered = false;
                discovering = false;

                var objects = reply.get_child_value (0);
                uint n = (uint) objects.n_children ();
                for (uint i = 0; i < n; i++) {
                    var entry = objects.get_child_value (i);
                    ingest (entry.get_child_value (0).get_string (),
                            entry.get_child_value (1));
                }

                changed ();
                devices_changed ();
            });
        }

        // Разбирает a{sa{sv}} — набор интерфейсов одного объекта.
        private void ingest (string path, Variant ifaces) {
            uint n = (uint) ifaces.n_children ();
            for (uint i = 0; i < n; i++) {
                var entry = ifaces.get_child_value (i);
                var iface = entry.get_child_value (0).get_string ();
                var props = entry.get_child_value (1);

                if (iface == ADAPTER_IFACE) {
                    // Первый найденный адаптер и есть наш: у BlueZ hci0 в
                    // подавляющем большинстве случаев один.
                    if (adapter_path == null) adapter_path = path;
                    if (adapter_path == path) {
                        has_adapter = true;
                        apply_adapter_props (props);
                    }
                } else if (iface == DEVICE_IFACE) {
                    apply_device_props (ensure_device (path), props);
                } else if (iface == BATTERY_IFACE) {
                    // Battery1 может прийти в том же словаре раньше Device1.
                    apply_battery_props (ensure_device (path), props);
                }
            }
        }

        private BluetoothDevice ensure_device (string path) {
            var dev = devices.lookup (path);
            if (dev == null) {
                dev = new BluetoothDevice (path);
                devices.insert (path, dev);
            }
            return dev;
        }

        private bool apply_adapter_props (Variant props) {
            bool dirty = false;

            var v = props.lookup_value ("Powered", VariantType.BOOLEAN);
            if (v != null && v.get_boolean () != powered) {
                powered = v.get_boolean ();
                dirty = true;
            }

            v = props.lookup_value ("Discovering", VariantType.BOOLEAN);
            if (v != null && v.get_boolean () != discovering) {
                discovering = v.get_boolean ();
                dirty = true;
            }

            return dirty;
        }

        // true, если изменилось что-то из показываемого. RSSI и прочий шум
        // BlueZ во время сканирования сюда не попадает, и UI не перерисовывается.
        private bool apply_device_props (BluetoothDevice dev, Variant props) {
            bool dirty = false;

            var v = props.lookup_value ("Alias", VariantType.STRING);
            if (v == null) v = props.lookup_value ("Name", VariantType.STRING);
            if (v != null && v.get_string () != dev.alias) {
                dev.alias = v.get_string ();
                dirty = true;
            }

            v = props.lookup_value ("Icon", VariantType.STRING);
            if (v != null && v.get_string () != dev.icon) {
                dev.icon = v.get_string ();
                dirty = true;
            }

            v = props.lookup_value ("Paired", VariantType.BOOLEAN);
            if (v != null && v.get_boolean () != dev.paired) {
                dev.paired = v.get_boolean ();
                dirty = true;
            }

            v = props.lookup_value ("Connected", VariantType.BOOLEAN);
            if (v != null && v.get_boolean () != dev.connected) {
                dev.connected = v.get_boolean ();
                dirty = true;
            }

            return dirty;
        }

        private bool apply_battery_props (BluetoothDevice dev, Variant props) {
            var v = props.lookup_value ("Percentage", VariantType.BYTE);
            if (v == null) return false;
            int pct = (int) v.get_byte ();
            if (pct == dev.battery) return false;
            dev.battery = pct;
            return true;
        }

        private void on_interfaces_added (DBusConnection c, string? sender, string path,
                                          string iface, string signal_name, Variant parameters) {
            var obj_path = parameters.get_child_value (0).get_string ();
            ingest (obj_path, parameters.get_child_value (1));
            changed ();
            devices_changed ();
        }

        private void on_interfaces_removed (DBusConnection c, string? sender, string path,
                                            string iface, string signal_name, Variant parameters) {
            var obj_path = parameters.get_child_value (0).get_string ();
            string[] removed = parameters.get_child_value (1).dup_strv ();

            bool state_dirty = false;
            bool list_dirty = false;

            foreach (var name in removed) {
                if (name == ADAPTER_IFACE && obj_path == adapter_path) {
                    adapter_path = null;
                    has_adapter = false;
                    powered = false;
                    discovering = false;
                    state_dirty = true;
                } else if (name == DEVICE_IFACE) {
                    if (devices.remove (obj_path)) {
                        state_dirty = true;
                        list_dirty = true;
                    }
                } else if (name == BATTERY_IFACE) {
                    var dev = devices.lookup (obj_path);
                    if (dev != null && dev.battery != -1) {
                        dev.battery = -1;
                        state_dirty = true;
                        list_dirty = true;
                    }
                }
            }

            if (state_dirty) changed ();
            if (list_dirty) devices_changed ();
        }

        private void on_properties_changed (DBusConnection c, string? sender, string path,
                                             string iface, string signal_name, Variant parameters) {
            var changed_iface = parameters.get_child_value (0).get_string ();
            var props = parameters.get_child_value (1);

            if (changed_iface == ADAPTER_IFACE) {
                if (path != adapter_path) return;
                if (apply_adapter_props (props)) changed ();
                return;
            }

            if (changed_iface == DEVICE_IFACE) {
                var dev = devices.lookup (path);
                if (dev == null) return;
                if (apply_device_props (dev, props)) {
                    changed ();
                    devices_changed ();
                }
                return;
            }

            if (changed_iface == BATTERY_IFACE) {
                var dev = devices.lookup (path);
                if (dev == null) return;
                if (apply_battery_props (dev, props)) {
                    changed ();
                    devices_changed ();
                }
            }
        }

        // Устройства, отсортированные по имени: HashTable отдаёт их в
        // произвольном порядке, и список в меню прыгал бы при каждом обновлении.
        public List<BluetoothDevice> get_devices () {
            var list = new List<BluetoothDevice> ();
            foreach (var dev in devices.get_values ()) {
                list.append (dev);
            }
            list.sort ((a, b) => {
                return a.alias.collate (b.alias);
            });
            return list;
        }

        public BluetoothDevice? get_connected_device () {
            foreach (var dev in devices.get_values ()) {
                if (dev.connected) return dev;
            }
            return null;
        }

        // Не set_powered: у свойства powered уже есть сгенерированный сеттер.
        public void request_powered (bool enable) {
            if (conn == null || adapter_path == null) return;
            apply_powered (enable, true);
        }

        private void apply_powered (bool enable, bool allow_unblock) {
            conn.call.begin (BLUEZ, adapter_path, PROPS_IFACE, "Set",
                             new Variant ("(ssv)", ADAPTER_IFACE, "Powered",
                                          new Variant.boolean (enable)),
                             null, DBusCallFlags.NONE, -1, null, (obj, res) => {
                try {
                    conn.call.end (res);
                } catch (Error e) {
                    // Софт-блок rfkill: BlueZ отвечает org.bluez.Error.Blocked и
                    // сам включиться не может, снять блок умеет только rfkill.
                    // Во всех остальных случаях D-Bus достаточно — раньше здесь
                    // безусловно спавнились и rfkill, и bluetoothctl.
                    if (enable && allow_unblock && "Blocked" in e.message) {
                        unblock_rfkill ();
                        Timeout.add (500, () => {
                            apply_powered (true, false);
                            return false;
                        });
                        return;
                    }
                    warning ("BluetoothService: Powered=%s не выставился: %s",
                             enable.to_string (), e.message);
                }
            });
        }

        private void unblock_rfkill () {
            try {
                Process.spawn_async (null, { "rfkill", "unblock", "bluetooth" }, null,
                                     SpawnFlags.SEARCH_PATH
                                     | SpawnFlags.STDOUT_TO_DEV_NULL
                                     | SpawnFlags.STDERR_TO_DEV_NULL,
                                     null, null);
            } catch (SpawnError e) {
                warning ("BluetoothService: rfkill не запустился: %s", e.message);
            }
        }

        private async void call_adapter (string method, int timeout_ms = -1) throws Error {
            if (conn == null || adapter_path == null) {
                throw new IOError.NOT_FOUND ("BlueZ: адаптер не найден");
            }
            yield conn.call (BLUEZ, adapter_path, ADAPTER_IFACE, method, null, null,
                             DBusCallFlags.NONE, timeout_ms, null);
        }

        private async void call_device (string path, string method, int timeout_ms) throws Error {
            if (conn == null) throw new IOError.NOT_CONNECTED ("BlueZ: нет системной шины");
            yield conn.call (BLUEZ, path, DEVICE_IFACE, method, null, null,
                             DBusCallFlags.NONE, timeout_ms, null);
        }

        public async void start_discovery () throws Error {
            yield call_adapter ("StartDiscovery");
        }

        public async void stop_discovery () throws Error {
            yield call_adapter ("StopDiscovery");
        }

        public async void connect_device (string path) throws Error {
            yield call_device (path, "Connect", OP_TIMEOUT_MS);
        }

        public async void disconnect_device (string path) throws Error {
            yield call_device (path, "Disconnect", OP_TIMEOUT_MS);
        }

        public async void pair_device (string path) throws Error {
            yield call_device (path, "Pair", OP_TIMEOUT_MS);
        }

        public async void remove_device (string path) throws Error {
            if (conn == null || adapter_path == null) {
                throw new IOError.NOT_FOUND ("BlueZ: адаптер не найден");
            }
            yield conn.call (BLUEZ, adapter_path, ADAPTER_IFACE, "RemoveDevice",
                             new Variant ("(o)", path), null,
                             DBusCallFlags.NONE, -1, null);
        }
    }
}

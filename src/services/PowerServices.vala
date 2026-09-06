using GLib;

namespace WayShell.Services {

    // Состояние батареи, приведённое к одному виду. UPower и sysfs описывают
    // его по-разному: у UPower это org.freedesktop.UPower.Device.State
    // (1 charging, 2 discharging, 4 fully charged), у sysfs — строка в
    // `status`. Раньше в коде жили сырые числа sysfs-конвенции, из-за чего
    // сравнения вида `state == 2` означали в разных файлах разное.
    public enum BatteryState {
        UNKNOWN,
        CHARGING,
        DISCHARGING,
        FULL
    }

    // Батарея. Один экземпляр на процесс, живёт в UPowerService.
    //
    // Данные приходят из UPower по PropertiesChanged. sysfs остался
    // резервным путём на случай, если upowerd не запущен: тогда и только
    // тогда включается опрос раз в 5 секунд.
    public class UpDevice : GLib.Object {
        private string bat_dir = "";
        private uint poll_id = 0;

        public double percentage { get; private set; default = 0.0; }
        public BatteryState state { get; private set; default = BatteryState.UNKNOWN; }
        public bool present { get; private set; default = false; }
        // Секунды до разряда/заряда. 0 — UPower не смог оценить.
        // Из sysfs не читаются: там это не время, а сила тока.
        public int64 time_to_empty { get; private set; default = 0; }
        public int64 time_to_full { get; private set; default = 0; }

        // Одно событие на пакет изменений. Раньше каждый из трёх виджетов
        // (StatusBar.PowerButton, QS.BatteryButton, QS.BatteryMenu) подписывался
        // на пять notify[...] по отдельности — то есть один PropertiesChanged
        // от UPower перерисовывал каждый виджет до пяти раз подряд.
        public signal void changed ();

        public UpDevice () {
            // Синхронное чтение sysfs один раз: UI строится сразу после
            // get_global(), а данные от UPower приедут асинхронно позже.
            // StatusBar.PowerButton при present == false скрывается навсегда,
            // поэтому первый снимок состояния обязан быть готов здесь.
            find_battery ();
            read_sysfs ();
        }

        ~UpDevice () {
            stop_polling ();
        }

        // --- UPower ---

        public void apply_upower_props (Variant props) {
            var v = props.lookup_value ("IsPresent", VariantType.BOOLEAN);
            if (v != null) present = v.get_boolean ();

            v = props.lookup_value ("Percentage", VariantType.DOUBLE);
            if (v != null) percentage = v.get_double ();

            v = props.lookup_value ("State", VariantType.UINT32);
            if (v != null) state = upower_state_to_battery_state (v.get_uint32 ());

            v = props.lookup_value ("TimeToEmpty", VariantType.INT64);
            if (v != null) time_to_empty = v.get_int64 ();

            v = props.lookup_value ("TimeToFull", VariantType.INT64);
            if (v != null) time_to_full = v.get_int64 ();

            // Type == 2 (Battery) и IsPresent == false вместе значат «батареи
            // нет»: на десктопе DisplayDevice существует, но пустой.
            v = props.lookup_value ("Type", VariantType.UINT32);
            if (v != null && v.get_uint32 () != 2) present = false;

            changed ();
        }

        private static BatteryState upower_state_to_battery_state (uint32 s) {
            switch (s) {
                case 1: // Charging
                case 5: // Pending charge
                    return BatteryState.CHARGING;
                case 2: // Discharging
                case 3: // Empty
                case 6: // Pending discharge
                    return BatteryState.DISCHARGING;
                case 4: // Fully charged
                    return BatteryState.FULL;
                default:
                    return BatteryState.UNKNOWN;
            }
        }

        // --- sysfs (резерв) ---

        public void start_polling () {
            if (poll_id != 0) return;
            refresh_sysfs ();
            // id таймера сохраняется: раньше UpDevice создавался на каждый
            // вызов get_primary_device(), и каждый оставлял вечный таймер.
            poll_id = Timeout.add_seconds (5, () => {
                refresh_sysfs ();
                return true;
            });
        }

        // find_battery() + read_sysfs() всегда идут парой: первый находит
        // батарею и правит present, второй читает значения. changed() эмитится
        // здесь, а не в read_sysfs(): тот выходит досрочно при present == false,
        // и об исчезновении батареи никто бы не узнал.
        private void refresh_sysfs () {
            find_battery ();
            read_sysfs ();
            changed ();
        }

        public void stop_polling () {
            if (poll_id == 0) return;
            Source.remove (poll_id);
            poll_id = 0;
        }

        private void find_battery () {
            for (int i = 0; i < 4; i++) {
                string path = "/sys/class/power_supply/BAT%d".printf (i);
                if (!FileUtils.test (path, FileTest.EXISTS | FileTest.IS_DIR)) continue;

                string type_content;
                try {
                    if (FileUtils.get_contents (Path.build_filename (path, "type"), out type_content)
                        && type_content.strip ().down () != "battery") {
                        continue;
                    }
                } catch (FileError e) {
                    // Файла type нет — считаем, что это батарея.
                }

                bat_dir = path;
                try {
                    string content;
                    FileUtils.get_contents (Path.build_filename (path, "present"), out content);
                    present = (content.strip () == "1");
                } catch (FileError e) {
                    // Ядро не экспортирует present, но каталог есть.
                    present = true;
                }
                return;
            }

            bat_dir = "";
            present = false;
        }

        private void read_sysfs () {
            if (!present || bat_dir == "") return;

            try {
                string content;
                FileUtils.get_contents (Path.build_filename (bat_dir, "capacity"), out content);
                percentage = double.parse (content.strip ());
            } catch (FileError e) {
                percentage = 0.0;
            }

            try {
                string content;
                FileUtils.get_contents (Path.build_filename (bat_dir, "status"), out content);
                switch (content.strip ().down ()) {
                    case "charging":
                        state = BatteryState.CHARGING;
                        break;
                    case "discharging":
                        state = BatteryState.DISCHARGING;
                        break;
                    case "full":
                        state = BatteryState.FULL;
                        break;
                    default:
                        // "not charging" — воткнут кабель, но заряд остановлен
                        // порогом. Ни заряд, ни разряд.
                        state = BatteryState.UNKNOWN;
                        break;
                }
            } catch (FileError e) {
                state = BatteryState.UNKNOWN;
            }
        }

        // --- Для UI ---

        // "73%". Формат один на три виджета: раньше каждый печатал сам.
        public string get_percent_text () {
            return "%.0f%%".printf (percentage);
        }

        public string get_status_text () {
            switch (state) {
                case BatteryState.CHARGING: return _("Charging");
                case BatteryState.DISCHARGING: return _("Discharging");
                case BatteryState.FULL: return _("Fully Charged");
                default: return _("On AC");
            }
        }

        // "1 h 24 min until empty" или пустая строка, если оценки нет.
        public string get_time_text () {
            int64 secs = 0;
            bool discharging = false;

            if (state == BatteryState.DISCHARGING && time_to_empty > 0) {
                secs = time_to_empty;
                discharging = true;
            } else if (state == BatteryState.CHARGING && time_to_full > 0) {
                secs = time_to_full;
            }

            if (secs <= 0) return "";

            int64 hours = secs / 3600;
            int64 mins = (secs % 3600) / 60;

            // Целые фразы, а не склейка из чисел и суффикса: в русском
            // склейка давала бы неверные падежи.
            if (discharging) {
                if (hours > 0) return _("%lld h %lld min until empty").printf (hours, mins);
                return _("%lld min until empty").printf (mins);
            }

            if (hours > 0) return _("%lld h %lld min until full").printf (hours, mins);
            return _("%lld min until full").printf (mins);
        }

        // Имя иконки для текущего состояния. Живёт здесь, а не в UPowerService,
        // чтобы виджетам был нужен только UpDevice.
        public string get_icon_name () {
            int step = ((int) percentage + 5) / 10 * 10;
            step = int.max (0, int.min (step, 100));

            if (state == BatteryState.CHARGING) {
                if (step == 100) return "battery-level-100-charged-symbolic";
                return "battery-level-%d-charging-symbolic".printf (step);
            }

            return "battery-level-%d-symbolic".printf (step);
        }

        // Готовый тултип: состояние плюс оценка времени, если она есть.
        public string get_summary_text () {
            string time_text = get_time_text ();
            if (time_text == "") return get_status_text ();
            return @"$(get_status_text ()), $time_text";
        }
    }

    public class UPowerService : GLib.Object {
        private const string UPOWER = "org.freedesktop.UPower";
        private const string UPOWER_PATH = "/org/freedesktop/UPower";
        private const string DEVICE_IFACE = "org.freedesktop.UPower.Device";
        private const string PROPS_IFACE = "org.freedesktop.DBus.Properties";

        private static UPowerService? global = null;

        private DBusConnection? conn = null;
        private string? display_path = null;
        private uint props_sub = 0;
        private uint name_watch = 0;
        private UpDevice device;

        public static UPowerService get_global () {
            if (global == null) {
                global = new UPowerService ();
            }
            return global;
        }

        private UPowerService () {
            device = new UpDevice ();

            Bus.get.begin (BusType.SYSTEM, null, (obj, res) => {
                try {
                    conn = Bus.get.end (res);
                } catch (Error e) {
                    warning ("UPowerService: нет системной шины: %s", e.message);
                    device.start_polling ();
                    return;
                }
                name_watch = Bus.watch_name_on_connection (conn, UPOWER,
                                                           BusNameWatcherFlags.NONE,
                                                           on_upower_appeared,
                                                           on_upower_vanished);
            });
        }

        ~UPowerService () {
            if (conn != null && props_sub != 0) conn.signal_unsubscribe (props_sub);
            if (name_watch != 0) Bus.unwatch_name (name_watch);
        }

        // Один UpDevice на процесс. Раньше здесь был `new UpDevice()`, а
        // конструктор заводил таймер — каждый из трёх вызовов утекал навсегда.
        public UpDevice get_primary_device () {
            return device;
        }

        private void on_upower_appeared (DBusConnection c, string name, string owner) {
            // DisplayDevice — агрегат всех батарей, который UPower считает сам.
            conn.call.begin (UPOWER, UPOWER_PATH, UPOWER, "GetDisplayDevice", null,
                             new VariantType ("(o)"), DBusCallFlags.NONE, -1, null, (obj, res) => {
                try {
                    var reply = conn.call.end (res);
                    display_path = reply.get_child_value (0).get_string ();
                    debug ("UPowerService: DisplayDevice = %s", display_path);
                } catch (Error e) {
                    warning ("UPowerService: GetDisplayDevice: %s", e.message);
                    device.start_polling ();
                    return;
                }

                if (props_sub != 0) conn.signal_unsubscribe (props_sub);
                props_sub = conn.signal_subscribe (UPOWER, PROPS_IFACE, "PropertiesChanged",
                                                   display_path, null, DBusSignalFlags.NONE,
                                                   on_properties_changed);
                refresh_all_props ();
            });
        }

        private void on_upower_vanished (DBusConnection c, string name) {
            if (props_sub != 0) {
                conn.signal_unsubscribe (props_sub);
                props_sub = 0;
            }
            display_path = null;
            // upowerd умер или не установлен — дальше только sysfs.
            device.start_polling ();
        }

        private void refresh_all_props () {
            conn.call.begin (UPOWER, display_path, PROPS_IFACE, "GetAll",
                             new Variant ("(s)", DEVICE_IFACE),
                             new VariantType ("(a{sv})"), DBusCallFlags.NONE, -1, null, (obj, res) => {
                try {
                    var reply = conn.call.end (res);
                    device.apply_upower_props (reply.get_child_value (0));
                    // UPower отвечает — опрос sysfs больше не нужен.
                    device.stop_polling ();
                    debug ("UPowerService: свойства приняты от UPower, опрос sysfs выключен");
                } catch (Error e) {
                    warning ("UPowerService: GetAll: %s", e.message);
                    device.start_polling ();
                }
            });
        }

        private void on_properties_changed (DBusConnection c, string? sender, string path,
                                            string iface, string signal_name, Variant parameters) {
            device.apply_upower_props (parameters.get_child_value (1));
        }
    }

    public class LogindService : GLib.Object {
        private const string LOGIN1 = "org.freedesktop.login1";
        private const string LOGIN1_PATH = "/org/freedesktop/login1";
        private const string MANAGER_IFACE = "org.freedesktop.login1.Manager";

        private static LogindService? global = null;

        private DBusConnection? conn = null;
        // Настоящий инхибитор — это открытый файловый дескриптор, полученный от
        // logind. Пока он открыт, простой подавлен; закрытие снимает блокировку.
        // Раньше здесь просто переключался bool, и кнопка в панели врала.
        private int inhibit_fd = -1;
        private bool pending = false;

        public signal void idle_inhibitor_changed (bool inhibited);

        public static LogindService get_global () {
            if (global == null) {
                global = new LogindService ();
            }
            return global;
        }

        private LogindService () {
            Bus.get.begin (BusType.SYSTEM, null, (obj, res) => {
                try {
                    conn = Bus.get.end (res);
                } catch (Error e) {
                    warning ("LogindService: нет системной шины: %s", e.message);
                }
            });
        }

        ~LogindService () {
            release_inhibit ();
        }

        public bool get_idle_inhibit () {
            return inhibit_fd >= 0;
        }

        public void set_idle_inhibit (bool enable) {
            if (enable == (inhibit_fd >= 0)) return;
            if (enable) {
                take_inhibit.begin ();
            } else {
                release_inhibit ();
            }
        }

        public void toggle_idle_inhibit () {
            set_idle_inhibit (inhibit_fd < 0);
        }

        private async void take_inhibit () {
            if (conn == null || pending || inhibit_fd >= 0) return;
            pending = true;

            try {
                UnixFDList fd_list;
                var reply = yield conn.call_with_unix_fd_list (
                    LOGIN1, LOGIN1_PATH, MANAGER_IFACE, "Inhibit",
                    new Variant ("(ssss)", "idle", "way-shell",
                                 "Idle inhibited from way-shell", "block"),
                    new VariantType ("(h)"), DBusCallFlags.NONE, -1, null, null, out fd_list);

                // В теле сообщения приезжает индекс в списке дескрипторов,
                // сам дескриптор — во вспомогательных данных сокета.
                int idx = reply.get_child_value (0).get_handle ();
                inhibit_fd = fd_list.get (idx);
            } catch (Error e) {
                warning ("LogindService: Inhibit не выдан: %s", e.message);
                pending = false;
                return;
            }

            pending = false;
            idle_inhibitor_changed (true);
        }

        private void release_inhibit () {
            if (inhibit_fd < 0) return;
            Posix.close (inhibit_fd);
            inhibit_fd = -1;
            idle_inhibitor_changed (false);
        }
    }
}

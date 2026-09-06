namespace WayShell.Services {
    public class BrightnessService : GLib.Object {
        private static BrightnessService? global = null;

        private const string LOGIN1 = "org.freedesktop.login1";
        private const string SESSION_IFACE = "org.freedesktop.login1.Session";

        private Settings settings;
        private File backlight_path;
        private File keyboard_path;
        private FileMonitor backlight_monitor;
        private FileMonitor keyboard_monitor;

        private DBusConnection? system_bus = null;
        // Путь нашей сессии login1. /session/auto разыменовывается logind’ом
        // в сессию вызывающего, так что искать идентификатор вручную не надо.
        private const string SESSION_PATH = "/org/freedesktop/login1/session/auto";

        public uint32 backlight_brightness { get; private set; }
        public uint32 max_backlight_brightness { get; private set; }
        public uint32 keyboard_brightness { get; private set; }
        public uint32 max_keyboard_brightness { get; private set; }

        private bool has_backlight = false;
        private bool has_keyboard = false;

        public signal void brightness_changed(float percent);
        public signal void keyboard_brightness_changed(uint val);

        public static BrightnessService get_global() {
            if (global == null) {
                global = new BrightnessService();
            }
            return global;
        }

        private BrightnessService() {
            settings = new Settings("org.flaemer.way-shell.system");

            settings.changed["backlight-directory"].connect(setup_backlight);
            settings.changed["keyboard-backlight-directory"].connect(setup_keyboard);

            // Системная шина нужна для logind SetBrightness. Асинхронно:
            // до её появления запись падает на sysfs, как и раньше.
            Bus.get.begin(BusType.SYSTEM, null, (obj, res) => {
                try {
                    system_bus = Bus.get.end(res);
                } catch (Error e) {
                    warning("BrightnessService: нет системной шины: %s", e.message);
                }
            });

            setup_backlight();
            setup_keyboard();
        }

        // Установка яркости в долях единицы.
        public void set_backlight_percent (double percent) {
            if (!has_backlight) return;

            // Превращаем дробный процент в точное целое число лимита яркости
            double calc = percent * (double) max_backlight_brightness;
            uint32 target = (uint32) (calc + 0.5);
            target = uint32.min (uint32.max (target, 0), max_backlight_brightness);
            write_sysfs_value ("brightness", target);
        }
        private void setup_backlight() {
            string dir = settings.get_string("backlight-directory");
            if (dir == "") {
                has_backlight = false;
                return;
            }

            backlight_path = File.new_for_path(Path.build_filename("/sys/class/backlight", dir));
            if (!backlight_path.query_exists()) {
                has_backlight = false;
                return;
            }
            has_backlight = true;

            try {
                uint8[] max_bytes;
                var max_file = backlight_path.get_child("max_brightness");
                max_file.load_contents(null, out max_bytes, null);
                string max_str = (string) max_bytes;
                max_backlight_brightness = (uint32)uint64.parse(max_str.strip());

                read_backlight();

                backlight_monitor = backlight_path.get_child("brightness").monitor(FileMonitorFlags.NONE, null);
                backlight_monitor.changed.connect((file, other, event) => {
                    uint32 prev = backlight_brightness;
                    read_backlight();
                    // FileMonitor шлёт и CHANGED, и CHANGES_DONE_HINT — на одну запись
                    // два события. Сравнение с прежним значением гасит второе,
                    // иначе OSD и слайдер обновляются дважды на каждый шаг.
                    if (backlight_brightness == prev) return;
                    brightness_changed(get_backlight_percent());
                });
            } catch (Error e) {
                warning("BrightnessService: Failed to setup backlight: %s", e.message);
            }
        }

        private void read_backlight() {
            try {
                uint8[] cur_bytes;
                backlight_path.get_child("brightness").load_contents(null, out cur_bytes, null);
                string cur_str = (string) cur_bytes;
                backlight_brightness = (uint32)uint64.parse(cur_str.strip());
            } catch (Error e) {
                warning("BrightnessService: Failed to read brightness: %s", e.message);
            }
        }

        public float get_backlight_percent() {
            if (max_backlight_brightness == 0) return 0.0f;
            return (float)backlight_brightness / (float)max_backlight_brightness;
        }

        public bool has_backlight_brightness() { return has_backlight; }
        public bool has_keyboard_brightness() { return has_keyboard; }
        public uint get_keyboard_max() { return max_keyboard_brightness; }
        public string map_icon() { return "display-brightness-symbolic"; }

        private void setup_keyboard() {
            string dir = settings.get_string("keyboard-backlight-directory");
            if (dir == "") {
                has_keyboard = false;
                return;
            }

            keyboard_path = File.new_for_path(Path.build_filename("/sys/class/leds", dir));
            if (!keyboard_path.query_exists()) {
                has_keyboard = false;
                return;
            }
            has_keyboard = true;

            try {
                uint8[] max_bytes;
                var max_file = keyboard_path.get_child("max_brightness");
                max_file.load_contents(null, out max_bytes, null);
                string max_str = (string) max_bytes;
                max_keyboard_brightness = (uint32)uint64.parse(max_str.strip());

                read_keyboard();

                keyboard_monitor = keyboard_path.get_child("brightness").monitor(FileMonitorFlags.NONE, null);
                keyboard_monitor.changed.connect((file, other, event) => {
                    uint32 prev = keyboard_brightness;
                    read_keyboard();
                    if (keyboard_brightness == prev) return;
                    keyboard_brightness_changed(keyboard_brightness);
                });
            } catch (Error e) {
                warning("BrightnessService: Failed to setup keyboard light: %s", e.message);
            }
        }

        private void read_keyboard() {
            try {
                uint8[] cur_bytes;
                keyboard_path.get_child("brightness").load_contents(null, out cur_bytes, null);
                string cur_str = (string) cur_bytes;
                keyboard_brightness = (uint32)uint64.parse(cur_str.strip());
            } catch (Error e) {
                warning("BrightnessService: Failed to read keyboard brightness: %s", e.message);
            }
        }

        public void backlight_up () {
            if (!has_backlight) return;
            uint32 step = uint32.max (max_backlight_brightness / 20, 1);
            uint32 target = uint32.min (backlight_brightness + step, max_backlight_brightness);
            write_sysfs_value ("brightness", target);
        }

        public void backlight_down () {
            if (!has_backlight) return;
            uint32 step = uint32.max (max_backlight_brightness / 20, 1);
            // Беззнаковое вычитание: при brightness < step uint32.max(a-b, 0)
            // давало ~4.29e9 вместо нуля.
            uint32 target = backlight_brightness > step ? backlight_brightness - step : 0;
            write_sysfs_value ("brightness", target);
        }

        // sysfs требует обычной записи в открытый дескриптор.
        // replace_contents() делает temp-файл + rename, чего sysfs не поддерживает,
        // поэтому раньше запись яркости молча не работала.
        private void write_sysfs_value (string filename, uint32 val) {
            string dir = backlight_path.get_path ();
            if (dir == null) return;

            var stream = FileStream.open (Path.build_filename (dir, filename), "w");
            if (stream != null) {
                stream.printf ("%u", val);
                stream.flush ();
                return;
            }

            // Нет прав на sysfs — типичный случай без udev-правила
            // (`/sys/class/backlight/*/brightness` обычно root:root 0644).
            // logind умеет писать туда за нас: метод Session.SetBrightness
            // разрешён владельцу активной сессии без polkit-диалога.
            if (set_brightness_via_logind (Path.get_basename (dir), val)) return;

            // Последний шанс — brightnessctl со своим setuid/udev.
            try {
                Process.spawn_async (null,
                    { "brightnessctl", "--device", Path.get_basename (dir),
                      "set", "%u".printf (val) },
                    null,
                    SpawnFlags.SEARCH_PATH | SpawnFlags.STDOUT_TO_DEV_NULL | SpawnFlags.STDERR_TO_DEV_NULL,
                    null, null);
            } catch (SpawnError e) {
                warning ("BrightnessService: не удалось выставить яркость: %s", e.message);
            }
        }

        // Вызов без ожидания ответа: яркость тянут слайдером, и блокировать
        // UI-поток на каждый шаг нельзя. Подтверждение придёт через FileMonitor
        // на том же файле — проверено, событие changed приходит и при записи
        // со стороны logind.
        private bool set_brightness_via_logind (string device, uint32 val) {
            if (system_bus == null) return false;

            system_bus.call.begin (LOGIN1, SESSION_PATH, SESSION_IFACE, "SetBrightness",
                                   new Variant ("(ssu)", "backlight", device, val),
                                   null, DBusCallFlags.NO_AUTO_START, -1, null,
                                   (obj, res) => {
                try {
                    system_bus.call.end (res);
                } catch (Error e) {
                    warning ("BrightnessService: logind SetBrightness отказал: %s", e.message);
                }
            });
            return true;
        }
    }
}
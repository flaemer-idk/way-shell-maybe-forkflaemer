namespace WayShell.Services {
    public class BrightnessService : GLib.Object {
        private static BrightnessService? global = null;

        private Settings settings;
        private File backlight_path;
        private File keyboard_path;
        private FileMonitor backlight_monitor;
        private FileMonitor keyboard_monitor;

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

            setup_backlight();
            setup_keyboard();
        }
        
// Чистый нативный метод установки яркости напрямую в sysfs без спавна сторонних процессов
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
                    read_backlight();
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
                    read_keyboard();
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
            uint32 step = max_backlight_brightness / 20; // 5%
            uint32 target = uint32.min (backlight_brightness + step, max_backlight_brightness);
            write_sysfs_value ("brightness", target);
        }

        public void backlight_down () {
            if (!has_backlight) return;
            uint32 step = max_backlight_brightness / 20; // 5%
            uint32 target = uint32.max (backlight_brightness - step, 0);
            write_sysfs_value ("brightness", target);
        }

        // Асинхронная неблокирующая запись в файлы sysfs (не тормозит главный поток при перетаскивании)
// Возвращаем надежную синхронную запись. Так как sysfs находится в ОЗУ, 
        // задержка диска равна 0, а асинхронные вызовы ядром на sysfs не поддерживаются.
        private void write_sysfs_value (string filename, uint32 val) {
            try {
                var file = backlight_path.get_child (filename);
                file.replace_contents (val.to_string ().data, null, false, FileCreateFlags.NONE, null, null);
            } catch (Error e) {
                warning ("BrightnessService: Failed to write to sysfs: %s", e.message);
            }
        }
    }
}
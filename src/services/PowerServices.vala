// Путь: src/services/PowerServices.vala
using GLib;

namespace WayShell.Services {
    [DBus (name = "org.freedesktop.login1.Manager")]
    interface Login1Manager : GLib.Object {
        public abstract void reboot(bool interactive) throws IOError, DBusError;
        public abstract void power_off(bool interactive) throws IOError, DBusError;
        public abstract void suspend(bool interactive) throws IOError, DBusError;
        public abstract void hibernate(bool interactive) throws IOError, DBusError;
        public abstract string can_reboot() throws IOError, DBusError;
        public abstract string can_power_off() throws IOError, DBusError;
        public abstract string can_suspend() throws IOError, DBusError;
        public abstract string can_hibernate() throws IOError, DBusError;
    }

    public class UPowerService : GLib.Object {
        private static UPowerService? global = null;
        private DBusProxy client_proxy;

        public static UPowerService get_global() {
            if (global == null) {
                global = new UPowerService();
            }
            return global;
        }

        private UPowerService() {
            setup_upower();
        }

        private void setup_upower() {
            try {
                var conn = Bus.get_sync(BusType.SYSTEM);
                client_proxy = new DBusProxy.sync(conn, DBusProxyFlags.NONE, null,
                                                  "org.freedesktop.UPower",
                                                  "/org/freedesktop/UPower",
                                                  "org.freedesktop.UPower");
            } catch (Error e) {
                warning("UPowerService: Failed to connect to UPower: %s", e.message);
            }
        }

        public UpDevice get_primary_device() {
            return new UpDevice();
        }

        public static string device_map_icon_name(UpDevice dev) {
            double percent = dev.percentage;
            uint state = dev.state;

            // Округляем процент до ближайшего десятка
            int step = ((int) percent + 5) / 10 * 10;
            step = int.max (0, int.min (step, 100));

            // Если батарея в процессе зарядки (state == 2)
            if (state == 2) {
                if (step == 100) {
                    return "battery-level-100-charged-symbolic";
                }
                return "battery-level-%d-charging-symbolic".printf(step);
            }

            // Стандартное отображение разряда
            return "battery-level-%d-symbolic".printf(step);
        }
    }

    public class UpDevice : GLib.Object {
        private string bat_dir = "";

        // Свойства GObject с автоматическим уведомлением об изменении (notify)
        public double percentage { get; set; default = 100.0; }
        public uint state { get; set; default = 1; }
        public bool present { get; set; default = false; }

        public UpDevice() {
            // Ищем папки BAT0 или BAT1 в системной sysfs
            for (int i = 0; i < 2; i++) {
                string path = "/sys/class/power_supply/BAT%d".printf(i);
                if (FileUtils.test(path, FileTest.EXISTS | FileTest.IS_DIR)) {
                    bat_dir = path;
                    present = true;
                    break;
                }
            }
            update_status();

            // Запускаем мягкий таймер на обновление раз в 5 секунд
            GLib.Timeout.add_seconds(5, () => {
                update_status();
                return true;
            });
        }

        private void update_status() {
            if (bat_dir == "") {
                present = false;
                return;
            }

            // Читаем, присутствует ли физически батарея в слоте (для ноутбуков без АКБ или halftop)
            try {
                string content;
                FileUtils.get_contents(Path.build_filename(bat_dir, "present"), out content);
                this.present = (content.strip() == "1");
            } catch (Error e) {
                this.present = true; // Фолбек: если файла нет, но директория есть, считаем присутствующей
            }

            if (!present) {
                return;
            }

            // Читаем текущий процент заряда
            try {
                string content;
                FileUtils.get_contents(Path.build_filename(bat_dir, "capacity"), out content);
                this.percentage = double.parse(content.strip());
            } catch (Error e) {
                this.percentage = 100.0;
            }

            // Читаем статус батареи (заряжается/разряжается)
            try {
                string content;
                FileUtils.get_contents(Path.build_filename(bat_dir, "status"), out content);
                string status = content.strip().down();
                if (status == "charging") {
                    this.state = 2; // Charging
                } else if (status == "discharging") {
                    this.state = 3; // Discharging
                } else {
                    this.state = 1; // Full / Idle
                }
            } catch (Error e) {
                this.state = 1;
            }
        }
    }

    public class LogindService : GLib.Object {
        private static LogindService? global = null;
        private Login1Manager manager;
        private bool inhibited = false;

        public signal void idle_inhibitor_changed(bool inhibited);

        public static LogindService get_global() {
            if (global == null) {
                global = new LogindService();
            }
            return global;
        }

        private LogindService() {
            try {
                manager = Bus.get_proxy_sync<Login1Manager>(BusType.SYSTEM, "org.freedesktop.login1", "/org/freedesktop/login1");
            } catch (Error e) {
                warning("LogindService: Failed to get Login1 proxy: %s", e.message);
            }
        }

        public bool get_idle_inhibit() {
            return inhibited;
        }

        public void set_idle_inhibit(bool enable) {
            inhibited = enable;
            idle_inhibitor_changed(inhibited);
        }
    }
}
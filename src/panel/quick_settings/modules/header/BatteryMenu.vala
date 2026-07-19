// Путь: src/panel/quick_settings/modules/header/BatteryMenu.vala
using Gtk;
using WayShell.Services;

namespace WayShell.QS {
    public class BatteryMenu : Box {
        private MenuWidget menu;
        private ProgressBar battery_bar;
        private Label battery_time;
        private Label battery_percentage;
        private UpDevice power_dev;

        public BatteryMenu() {
            Object(orientation: Orientation.VERTICAL, spacing: 0);

            menu = new MenuWidget("Battery Status", "battery-full-symbolic", false);
            this.append(menu);

            var content = new Box(Orientation.VERTICAL, 8);
            content.name = "battery-menu";

            battery_bar = new ProgressBar();
            battery_bar.hexpand = true;
            battery_bar.add_css_class("battery-progress-bar");
            content.append(battery_bar);

            var stats_container = new Box(Orientation.HORIZONTAL, 12);
            battery_time = new Label("");
            battery_time.halign = Align.START;
            battery_time.hexpand = true;

            battery_percentage = new Label("");
            battery_percentage.halign = Align.END;

            stats_container.append(battery_time);
            stats_container.append(battery_percentage);
            content.append(stats_container);

            menu.options.append(content);

            var upower = UPowerService.get_global();
            if (upower != null) {
                power_dev = upower.get_primary_device();
                if (power_dev != null) {
                    update_status();
                    power_dev.notify["percentage"].connect(update_status);
                    power_dev.notify["state"].connect(update_status);
                }
            }
        }

        private void update_status() {
            if (power_dev == null) return;
            if (!power_dev.present) {
                battery_bar.set_fraction(1.0);
                battery_percentage.set_text("∞%");
                battery_time.set_text("AC Power (Desktop)");
                return;
            }
            double percent = power_dev.percentage;
            uint state = power_dev.state;

            battery_bar.set_fraction(percent / 100.0);
            battery_percentage.set_text("%.0f%%".printf(percent));

            string status_text = "Discharging";
            if (state == 2) {
                status_text = "Charging";
            } else if (state == 1) {
                status_text = "Fully Charged";
            }

            battery_time.set_text(status_text);
        }
    }
}
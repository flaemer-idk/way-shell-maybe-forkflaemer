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
            this.visible = false;

            menu = new MenuWidget(_("Battery Status"), "battery-full-symbolic", false);
            this.append(menu);

            var content = new Box(Orientation.VERTICAL, 8);
            content.name = "battery-menu";

            battery_bar = new ProgressBar();
            battery_bar.hexpand = true;
            battery_bar.add_css_class("battery-progress-bar");
            // У полосы нет подписи, скринридер иначе озвучит только проценты.
            battery_bar.update_property(Gtk.AccessibleProperty.LABEL, _("Battery charge"), -1);
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
                    power_dev.changed.connect(update_status);
                }
            }
        }

        private void update_status() {
            if (power_dev == null || !power_dev.present) {
                this.visible = false;
                return;
            }
            this.visible = true;

            battery_bar.set_fraction(power_dev.percentage / 100.0);
            battery_percentage.set_text(power_dev.get_percent_text());

            // UPower умеет оценивать остаток времени; если оценки нет,
            // показываем состояние.
            string time_text = power_dev.get_time_text();
            battery_time.set_text(time_text != "" ? time_text : power_dev.get_status_text());
        }
    }
}
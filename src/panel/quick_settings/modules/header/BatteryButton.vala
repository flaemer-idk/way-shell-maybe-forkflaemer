using Gtk;
using WayShell.Services;

namespace WayShell.QS {
    public class BatteryButton : Button {
        private Box box;
        private Image icon;
        private Label label;
        private UpDevice power_dev;

        public BatteryButton() {
            this.add_css_class("battery-button");

            box = new Box(Orientation.HORIZONTAL, 6);
            icon = new Image();
            label = new Label("");

            box.append(icon);
            box.append(label);
            this.set_child(box);

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
                label.set_text("∞%");
                icon.set_from_icon_name("ac-adapter-symbolic");
                return;
            }
            double percent = power_dev.percentage;
            label.set_text("%.0f%%".printf(percent));
            icon.set_from_icon_name(UPowerService.device_map_icon_name(power_dev));
        }
    }
}
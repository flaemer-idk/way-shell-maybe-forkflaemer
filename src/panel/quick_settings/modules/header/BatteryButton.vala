using Gtk;
using WayShell.Services;

namespace WayShell.QS {
    public class BatteryButton : Button {
        private Box box;
        private Image icon;
        private new Label label;
        private UpDevice power_dev;

        public BatteryButton() {
            this.add_css_class("battery-button");
            this.visible = false;

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
            label.set_text(power_dev.get_percent_text());
            icon.set_from_icon_name(power_dev.get_icon_name());

            string summary = power_dev.get_summary_text();
            this.tooltip_text = summary;
            // Внутри кнопки только иконка и проценты, так что метку задаём явно.
            this.update_property(Gtk.AccessibleProperty.LABEL,
                                 _("Battery: %s").printf(summary), -1);
        }
    }
}
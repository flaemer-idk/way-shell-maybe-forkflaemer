// Путь: src/panel/quick_settings/modules/header/UptimeWidget.vala
using Gtk;
using GLib;

namespace WayShell.QS {
    public class UptimeWidget : Box {
        private Label label;
        private Image icon;

        public UptimeWidget() {
            Object(orientation: Orientation.HORIZONTAL, spacing: 6);
            this.add_css_class("uptime-badge");
            this.valign = Align.CENTER;

            icon = new Image.from_icon_name("preferences-system-time-symbolic");
            label = new Label("");

            this.append(icon);
            this.append(label);

            // Первичное значение
            update_uptime();

            // Обновляем ТОЛЬКО при открытии шторки, без постоянных фоновых таймеров!
            var qs = Drawer.get_global();
            qs.visible.connect(update_uptime);
        }

        public void update_uptime() {
            try {
                string content;
                FileUtils.get_contents("/proc/uptime", out content);
                string[] parts = content.strip().split(" ");
                if (parts.length > 0) {
                    double total_seconds = double.parse(parts[0]);
                    int64 sec = (int64) total_seconds;
                    int64 days = sec / 86400;
                    int64 hours = (sec % 86400) / 3600;
                    int64 minutes = (sec % 3600) / 60;

                    if (days > 0) {
                        label.set_text("Uptime is %ldd %ldh %ldm".printf((long) days, (long) hours, (long) minutes));
                    } else if (hours > 0) {
                        label.set_text("Uptime is %ldh %ldm".printf((long) hours, (long) minutes));
                    } else {
                        label.set_text("Uptime is %ldm".printf((long) minutes));
                    }
                    return;
                }
            } catch (Error e) {
                warning("UptimeWidget: Failed to read /proc/uptime: %s", e.message);
            }
            label.set_text("Uptime is 0m");
        }
    }
}
using Gtk;

namespace WayShell.QS {
    public class DndButton : GridButton {
        private GLib.Settings settings;

        public DndButton() {
            // Инициализируем базовый GridButton без всплывающего меню (reveal_widget = null)
            base(ButtonType.DND, "Do Not Disturb", "Off", "notifications-disabled-symbolic");

            settings = new GLib.Settings("org.flaemer.way-shell.notifications");
            
            update_dnd_status();
            toggle.clicked.connect(on_dnd_toggle);
            
            GLib.Timeout.add(1000, () => {
                update_dnd_status();
                return true;
            });
        }

        private void on_dnd_toggle() {
            bool dnd = settings.get_boolean("do-not-disturb");
            settings.set_boolean("do-not-disturb", !dnd);
            update_dnd_status();
        }

        private void update_dnd_status() {
            bool dnd = settings.get_boolean("do-not-disturb");
            if (dnd) {
                set_toggled(true);
                subtitle.set_text("On");
            } else {
                set_toggled(false);
                subtitle.set_text("Off");
            }
        }
    }
}
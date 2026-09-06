using Gtk;

namespace WayShell.QS {
    public class DndButton : GridButton {
        private GLib.Settings settings;

        public DndButton() {
            // Инициализируем базовый GridButton без всплывающего меню (reveal_widget = null)
            base(ButtonType.DND, _("Do Not Disturb"), _("Off"), "notifications-disabled-symbolic");

            settings = new GLib.Settings("org.flaemer.way-shell.notifications");

            update_dnd_status();
            toggle.clicked.connect(on_dnd_toggle);

            // Раньше здесь был Timeout.add(1000) — поллинг GSettings с частотой 1 Гц.
            // GSettings сам шлёт changed, подписка дешевле и точнее.
            settings.changed["do-not-disturb"].connect(update_dnd_status);
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
                subtitle.set_text(_("On"));
            } else {
                set_toggled(false);
                subtitle.set_text(_("Off"));
            }
        }
    }
}
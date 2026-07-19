using Gtk;
using GLib;
using WayShell.Dialog;

namespace WayShell.QS {
    [DBus (name = "org.freedesktop.login1.Manager")]
    interface Login1Manager : GLib.Object {
        public abstract void reboot(bool interactive) throws GLib.Error;
        public abstract void power_off(bool interactive) throws GLib.Error;
        public abstract void suspend(bool interactive) throws GLib.Error;
        public abstract void hibernate(bool interactive) throws GLib.Error;
        public abstract void terminate_session(string id) throws GLib.Error;
    }

    public class PowerMenu : Box {
        private MenuWidget menu;
        private GenericArray<PowerButtonRow> rows;

        public PowerMenu() {
            Object(orientation: Orientation.VERTICAL, spacing: 0);
            rows = new GenericArray<PowerButtonRow>();

            menu = new MenuWidget("Power Off", "system-shutdown-symbolic", false);
            this.append(menu);

            var suspend_row = new PowerButtonRow(this, "Suspend", () => {
                var dialog = DialogOverlay.get_global();
                Drawer.get_global().set_hidden();
                dialog.present("Suspend?", "Are you sure you want to suspend?", () => {
                    do_suspend();
                });
            });
            menu.options.append(suspend_row);
            rows.add(suspend_row);

            var restart_row = new PowerButtonRow(this, "Restart", () => {
                var dialog = DialogOverlay.get_global();
                Drawer.get_global().set_hidden();
                dialog.present("Restart?", "Are you sure you want to restart?", () => {
                    do_reboot();
                });
            });
            menu.options.append(restart_row);
            rows.add(restart_row);

            var poweroff_row = new PowerButtonRow(this, "Power Off", () => {
                var dialog = DialogOverlay.get_global();
                Drawer.get_global().set_hidden();
                dialog.present("Power Off?", "Are you sure you want to power off?", () => {
                    do_power_off();
                });
            });
            menu.options.append(poweroff_row);
            rows.add(poweroff_row);

            var logout_row = new PowerButtonRow(this, "Log Out...", () => {
                var dialog = DialogOverlay.get_global();
                Drawer.get_global().set_hidden();
                dialog.present("Log Out?", "Are you sure you want to log out?", () => {
                    do_logout();
                });
            });
            menu.options.append(logout_row);
            rows.add(logout_row);
        }

        public void collapse_all_confirmations() {
            for (int i = 0; i < rows.length; i++) {
                rows[i].revealer.set_reveal_child(false);
            }
        }

        private void do_suspend() {
            try {
                var manager = Bus.get_proxy_sync<Login1Manager>(BusType.SYSTEM, "org.freedesktop.login1", "/org/freedesktop/login1");
                manager.suspend(false);
            } catch (Error e) {
                warning("PowerMenu: Failed to suspend: %s", e.message);
            }
        }

        private void do_reboot() {
            try {
                var manager = Bus.get_proxy_sync<Login1Manager>(BusType.SYSTEM, "org.freedesktop.login1", "/org/freedesktop/login1");
                manager.reboot(false);
            } catch (Error e) {
                warning("PowerMenu: Failed to reboot: %s", e.message);
            }
        }

        private void do_power_off() {
            try {
                var manager = Bus.get_proxy_sync<Login1Manager>(BusType.SYSTEM, "org.freedesktop.login1", "/org/freedesktop/login1");
                manager.power_off(false);
            } catch (Error e) {
                warning("PowerMenu: Failed to power off: %s", e.message);
            }
        }

        private void do_logout() {
            try {
                string? session_id = Environment.get_variable("XDG_SESSION_ID");
                if (session_id != null && session_id != "") {
                    var manager = Bus.get_proxy_sync<Login1Manager>(BusType.SYSTEM, "org.freedesktop.login1", "/org/freedesktop/login1");
                    manager.terminate_session(session_id);
                } else {
                    warning("PowerMenu: XDG_SESSION_ID is not set, falling back to loginctl spawn");
                    Process.spawn_command_line_async("loginctl terminate-session self");
                }
            } catch (Error e) {
                warning("PowerMenu: Failed to logout natively: %s", e.message);
            }
        }
    }

    public class PowerButtonRow : Box {
        private PowerMenu parent_menu;
        public Button button;
        public Revealer revealer;
        public Button confirm_button;

        public delegate void PowerAction();

        public PowerButtonRow(PowerMenu parent, string title, owned PowerAction action) {
            Object(orientation: Orientation.VERTICAL, spacing: 0);
            this.parent_menu = parent;

            button = new Button.with_label(title);
            var label = (Label) button.get_child();
            if (label != null) label.xalign = 0.0f;
            button.hexpand = true;
            this.append(button);

            revealer = new Revealer();
            revealer.transition_type = RevealerTransitionType.SWING_DOWN;
            revealer.transition_duration = 250;
            revealer.hexpand = true;

            confirm_button = new Button.with_label("Confirm");
            confirm_button.add_css_class("confirm-button");
            confirm_button.hexpand = true;
            confirm_button.clicked.connect((owned) action);

            revealer.set_child(confirm_button);
            this.append(revealer);

            button.clicked.connect(() => {
                bool state = revealer.get_reveal_child();
                parent_menu.collapse_all_confirmations();
                revealer.set_reveal_child(!state);
            });
        }
    }
}
namespace WayShell.Services {
    public class WaylandGammaControlService : GLib.Object {
        private static WaylandGammaControlService? global = null;
        private bool is_enabled = false;

        public signal void gamma_control_enabled ();
        public signal void gamma_control_disabled ();

        public static WaylandGammaControlService get_global () {
            if (global == null) {
                global = new WaylandGammaControlService ();
            }
            return global;
        }

        private WaylandGammaControlService () {}

        public bool enabled () {
            return is_enabled;
        }

        public void set_enabled (bool val) {
            is_enabled = val;
            if (is_enabled) {
                gamma_control_enabled ();
            } else {
                gamma_control_disabled ();
            }
        }
    }
}
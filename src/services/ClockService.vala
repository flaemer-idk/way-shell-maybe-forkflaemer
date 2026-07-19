namespace WayShell.Services {
    public class ClockService : GLib.Object {
        private static ClockService? global = null;
        public bool enabled { get; set; default = true; }

        public signal void tick(DateTime now);

        public static ClockService get_global() {
            if (global == null) {
                global = new ClockService();
            }
            return global;
        }

        private ClockService() {
            emit_tick();
            GLib.Timeout.add(500, tick_sync);
        }

        private bool emit_tick() {
            var now = new DateTime.now_local();
            tick(now);
            return enabled;
        }

        private bool tick_sync() {
            var now = new DateTime.now_local();
            if (now.get_second() != 0) {
                return enabled;
            }
            // Как только поймали 00 секунд, переключаемся на тики раз в 60 секунд
            GLib.Timeout.add_seconds(60, emit_tick);
            debug("ClockService: synchronized on minute boundary");
            return false;
        }
    }
}

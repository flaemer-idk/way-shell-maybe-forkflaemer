using GLib;
using WayShell.Panel; 

namespace WayShell.Services {
    public class IpcService : GLib.Object {
        private static IpcService? global = null;
        private SocketListener listener;

        public static IpcService get_global() {
            if (global == null) {
                global = new IpcService();
            }
            return global;
        }

        private IpcService() {
            setup_socket.begin();
        }

        private async void setup_socket() {
            string? runtime_dir = Environment.get_variable("XDG_RUNTIME_DIR");
            if (runtime_dir == null) {
                critical("IpcService: XDG_RUNTIME_DIR is not set");
                return;
            }

            string sock_path = Path.build_filename(runtime_dir, "way-shell.sock");
            var socket_file = File.new_for_path(sock_path);
            try {
                if (socket_file.query_exists()) {
                    socket_file.delete();
                }
            } catch (Error e) {
                warning("IpcService: Failed to delete stale socket: %s", e.message);
            }

            listener = new SocketListener();
            try {
                var address = new UnixSocketAddress(sock_path);
                // Добавлен недостающий out аргумент для корректного связывания адреса в Vala
                SocketAddress effective_address;
                // Использован SocketType.STREAM вместо SocketType.DATAGRAM для корректной работы SocketListener и SocketClient
                listener.add_address(address, SocketType.STREAM, SocketProtocol.DEFAULT, null, out effective_address);
                accept_connections.begin();
            } catch (Error e) {
                critical("IpcService: Failed to bind socket: %s", e.message);
            }
        }

        private async void accept_connections() {
            while (true) {
                try {
                    var conn = yield listener.accept_async();
                    handle_connection.begin(conn);
                } catch (Error e) {
                    warning("IpcService: Connection error: %s", e.message);
                }
            }
        }

        private async void handle_connection(SocketConnection conn) {
            try {
                var input = new DataInputStream(conn.input_stream);
                string? line = yield input.read_line_async(Priority.DEFAULT);
                if (line != null) {
                    bool success = execute_command(line);
                    
                    var output = new DataOutputStream(conn.output_stream);
                    output.put_string(success ? "true\n" : "false\n");
                }
            } catch (Error e) {
                warning("IpcService: Failed to handle connection: %s", e.message);
            }
        }

        private bool execute_command(string cmd) {
            switch (cmd) {
                case "message-profile-open":
                case "message-tray-open":
                    var mt = WayShell.Panel.MessageTray.get_global();
                    if (mt != null) mt.set_visible();
                    return true;
                case "volume-up":
                    var wp = WirePlumberService.get_global();
                    if (wp != null) {
                        var sink = wp.get_default_sink();
                        wp.volume_up(sink);
                    }
                    return true;
                case "volume-down":
                    var wp_down = WirePlumberService.get_global();
                    if (wp_down != null) {
                        var sink = wp_down.get_default_sink();
                        wp_down.volume_down(sink);
                    }
                    return true;
                case "brightness-up":
                    var bs = BrightnessService.get_global();
                    if (bs != null) bs.backlight_up();
                    return true;
                case "brightness-down":
                    var bs_down = BrightnessService.get_global();
                    if (bs_down != null) bs_down.backlight_down();
                    return true;
                default:
                    return false;
            }
        }
    }
}
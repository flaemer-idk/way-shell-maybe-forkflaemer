using GLib;
using Json;

namespace WayShell.Services {
    public class NiriClient : GLib.Object {
        private static NiriClient? global = null;

        private SocketConnection? conn;
        private string socket_path;
        public GenericArray<WMWorkspace> workspaces { get; private set; }

        public signal void workspaces_changed(GenericArray<WMWorkspace> workspaces);

        public static NiriClient get_global() {
            if (global == null) {
                global = new NiriClient();
            }
            return global;
        }

        private NiriClient() {
            workspaces = new GenericArray<WMWorkspace>();
            socket_path = Environment.get_variable("NIRI_SOCKET") ?? "";
            if (socket_path != "") {
                connect_to_niri.begin();
            } else {
                warning("NiriClient: NIRI_SOCKET environment variable not set");
            }
        }

        private async void connect_to_niri() {
            try {
                var client = new SocketClient();
                var address = new UnixSocketAddress(socket_path);
                conn = yield client.connect_async(address);
                
                send_command.begin("\"Workspaces\"");
                send_command.begin("\"EventStream\"");
                listen_to_events.begin();
            } catch (Error e) {
                critical("NiriClient: Failed to connect to Niri: %s", e.message);
            }
        }

        private async void send_command(string cmd) {
            if (conn == null) return;
            try {
                var output = new DataOutputStream(conn.output_stream);
                output.put_string(cmd + "\n");
            } catch (Error e) {
                warning("NiriClient: Failed to write command: %s", e.message);
            }
        }

        private async void listen_to_events() {
            if (conn == null) return;
            var input = new DataInputStream(conn.input_stream);
            while (true) {
                try {
                    string? line = yield input.read_line_async(Priority.DEFAULT);
                    if (line == null) break;

                    parse_event(line);
                } catch (Error e) {
                    warning("NiriClient: Event stream read error: %s", e.message);
                    break;
                }
            }
        }

        private void parse_event(string json_str) {
            var parser = new Parser();
            try {
                parser.load_from_data(json_str);
                var root = parser.get_root().get_object();

                if (root.has_member("Workspaces") || root.has_member("WorkspaceActivated") || root.has_member("WorkspacesChanged")) {
                    request_workspaces_update();
                }
            } catch (Error e) {
                // Игнорируем ошибки парсинга для нецелевых событий
            }
        }

        private void request_workspaces_update() {
            workspaces_changed(workspaces);
        }

        public void focus_workspace(WMWorkspace ws) {
            string ref_str = ws.name.ascii_down().contains("index") ? "Index" : "Name";
            send_command.begin("{\"Action\":{\"FocusWorkspace\":{\"reference\":{\"%s\":\"%s\"}}}}".printf(ref_str, ws.name));
        }
    }
}
using GLib;
using WayShell.Panel;

namespace WayShell.Services {
    public class IpcService : GLib.Object {
        // Сколько подряд идущих ошибок accept() терпим, прежде чем считать
        // сокет мёртвым и выйти из цикла. Раньше цикл был безусловным: при
        // устойчивой ошибке он крутился на 100% CPU и писал warning на каждой
        // итерации.
        private const int MAX_ACCEPT_ERRORS = 5;

        private static IpcService? global = null;
        private SocketListener? listener = null;
        private string? sock_path = null;
        private int accept_errors = 0;

        public static IpcService get_global() {
            if (global == null) {
                global = new IpcService();
            }
            return global;
        }

        private IpcService() {
            setup_socket.begin();
        }

        ~IpcService() {
            // Не оставляем за собой файл сокета: следующий запуск иначе
            // считает его протухшим и удаляет вслепую.
            if (listener != null) listener.close();
            if (sock_path != null) FileUtils.unlink(sock_path);
        }

        private async void setup_socket() {
            string? runtime_dir = Environment.get_variable("XDG_RUNTIME_DIR");
            if (runtime_dir == null) {
                critical("IpcService: XDG_RUNTIME_DIR is not set");
                return;
            }

            string path = Path.build_filename(runtime_dir, "way-shell.sock");

            if (FileUtils.test(path, FileTest.EXISTS)) {
                if (yield socket_is_alive(path)) {
                    // Раньше файл удалялся безусловно — второй запуск отбирал
                    // сокет у уже работающего экземпляра.
                    warning("IpcService: %s уже слушает другой экземпляр way-shell, IPC отключён", path);
                    return;
                }
                if (FileUtils.unlink(path) != 0) {
                    warning("IpcService: не удалось удалить протухший сокет %s", path);
                    return;
                }
            }

            listener = new SocketListener();
            try {
                var address = new UnixSocketAddress(path);
                SocketAddress effective_address;
                listener.add_address(address, SocketType.STREAM, SocketProtocol.DEFAULT,
                                     null, out effective_address);
            } catch (Error e) {
                critical("IpcService: Failed to bind socket: %s", e.message);
                listener = null;
                return;
            }

            sock_path = path;

            // XDG_RUNTIME_DIR обычно 0700, но полагаться на права родительского
            // каталога — плохая привычка: права на сам сокет выставляем сами.
            if (FileUtils.chmod(path, 0600) != 0) {
                warning("IpcService: не удалось выставить 0600 на %s", path);
            }

            accept_connections.begin();
        }

        // Живой ли сокет: если connect проходит, на другом конце кто-то есть.
        private async bool socket_is_alive(string path) {
            var client = new SocketClient();
            client.timeout = 1;
            try {
                var conn = yield client.connect_async(new UnixSocketAddress(path), null);
                conn.close();
                return true;
            } catch (Error e) {
                // ECONNREFUSED/ENOENT — файл остался от упавшего процесса.
                return false;
            }
        }

        private async void accept_connections() {
            while (listener != null) {
                SocketConnection conn;
                try {
                    conn = yield listener.accept_async();
                } catch (Error e) {
                    accept_errors++;
                    warning("IpcService: Connection error (%d/%d): %s",
                            accept_errors, MAX_ACCEPT_ERRORS, e.message);
                    if (accept_errors >= MAX_ACCEPT_ERRORS) {
                        critical("IpcService: слишком много ошибок accept(), слушатель остановлен");
                        listener.close();
                        listener = null;
                        return;
                    }
                    // Пауза, чтобы не жечь CPU, пока ошибка не разошлась.
                    Timeout.add(200, () => {
                        accept_connections.callback();
                        return false;
                    });
                    yield;
                    continue;
                }

                accept_errors = 0;
                handle_connection.begin(conn);
            }
        }

        // Только процессы того же пользователя. Unix-сокет наследует права
        // каталога, но SO_PEERCRED — проверка по самому соединению, а не по
        // тому, кто когда-то мог до файла добраться.
        private bool peer_is_trusted(SocketConnection conn) {
            try {
                var creds = conn.socket.get_credentials();
                uid_t peer_uid = (uid_t) creds.get_unix_user();
                if (peer_uid == Posix.getuid()) return true;
                warning("IpcService: соединение от uid %u отклонено", (uint) peer_uid);
                return false;
            } catch (Error e) {
                warning("IpcService: не удалось прочитать SO_PEERCRED: %s", e.message);
                return false;
            }
        }

        private async void handle_connection(SocketConnection conn) {
            try {
                if (!peer_is_trusted(conn)) {
                    conn.close();
                    return;
                }

                var input = new DataInputStream(conn.input_stream);
                string? line = yield input.read_line_async(Priority.DEFAULT);
                if (line != null) {
                    bool success = execute_command(line.strip());

                    var output = new DataOutputStream(conn.output_stream);
                    output.put_string(success ? "true\n" : "false\n");
                    output.flush();
                }
                conn.close();
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
                // Инхибитор простоя иначе недостижим: индикатор в статус-баре
                // лежит внутри общей кнопки, которая открывает шторку, и своего
                // клика у него нет.
                case "idle-inhibit-toggle":
                    LogindService.get_global().toggle_idle_inhibit();
                    return true;
                case "idle-inhibit-on":
                    LogindService.get_global().set_idle_inhibit(true);
                    return true;
                case "idle-inhibit-off":
                    LogindService.get_global().set_idle_inhibit(false);
                    return true;
                default:
                    return false;
            }
        }
    }
}

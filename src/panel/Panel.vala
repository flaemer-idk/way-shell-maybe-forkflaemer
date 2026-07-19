using Gtk;
using Adw;
using WayShell.Services;

namespace WayShell.Panel {
    public class Panel : GLib.Object {
        private static HashTable<Gdk.Monitor, Panel> panels = null;
        private static GenericArray<Gdk.Monitor> monitors = null;
        private static Mediator mediator;

        public Gtk.Window win;
        public Gdk.Monitor monitor;
        public CenterBox container;
        public Box left;
        public Box center;
        public Box right;

        public Clock clock;
        public StatusBar status_bar;
        public IndicatorBar? indicator_bar;

        public Button media_btn;
        public Box media_box;
        public Image media_icon;
        public Label media_label;
        public Image webcam_icon;

        private string? current_player_name = null;
        private int64 last_scroll_time = 0;

        public static HashTable<Gdk.Monitor, Panel> get_all_panels() {
            return panels;
        }

        public Panel() {
            init_layout();
        }

        private void init_layout() {
            win = new Gtk.Window();
            Gtk4LayerShell.init_for_window(win);
            Gtk4LayerShell.set_namespace(win, "way-shell-panel");
            Gtk4LayerShell.set_layer(win, Gtk4LayerShell.Layer.TOP);
            Gtk4LayerShell.auto_exclusive_zone_enable(win);
            
            Gtk4LayerShell.set_anchor(win, Gtk4LayerShell.Edge.TOP, true);
            Gtk4LayerShell.set_anchor(win, Gtk4LayerShell.Edge.LEFT, true);
            Gtk4LayerShell.set_anchor(win, Gtk4LayerShell.Edge.RIGHT, true);
            Gtk4LayerShell.set_anchor(win, Gtk4LayerShell.Edge.BOTTOM, false);
            win.set_size_request(-1, 30);

            container = new CenterBox();
            container.name = "panel";

            left = new Box(Orientation.HORIZONTAL, 0);
            center = new Box(Orientation.HORIZONTAL, 0);
            right = new Box(Orientation.HORIZONTAL, 0);

            container.set_start_widget(left);
            container.set_center_widget(center);
            container.set_end_widget(right);

            // Кнопка плеера в панели
            media_btn = new Button();
            media_btn.add_css_class("panel-button");
            media_btn.visible = false;

            media_box = new Box(Orientation.HORIZONTAL, 6);
            media_icon = new Image.from_icon_name("audio-x-generic-symbolic");
            media_label = new Label("");
            media_label.add_css_class("panel-button-label");

            media_box.append(media_icon);
            media_box.append(media_label);
            media_btn.set_child(media_box);

            var scroll_ctrl = new EventControllerScroll(EventControllerScrollFlags.VERTICAL);
            scroll_ctrl.scroll.connect(on_media_scroll);
            media_btn.add_controller(scroll_ctrl);
            media_btn.clicked.connect(on_media_clicked);

            center.append(media_btn);

            // Индикатор веб-камеры
            webcam_icon = new Image.from_icon_name("camera-web-symbolic");
            webcam_icon.add_css_class("webcam-active");
            webcam_icon.visible = false;
            right.append(webcam_icon);

            start_playerctl_monitor();
            GLib.Timeout.add(1000, check_webcam_status);

            win.set_child(container); 
        }

        public void attach_to_monitor(Gdk.Monitor mon) {
            this.monitor = mon;
            Gtk4LayerShell.set_monitor(win, mon);
            panels.insert(mon, this);
            win.present();

            status_bar = new StatusBar();
            status_bar.panel = this;
            left.append(status_bar);

            var settings = new GLib.Settings("org.flaemer.way-shell.panel");
            if (settings.get_boolean("enable-tray-icons")) {
                indicator_bar = new IndicatorBar();
                indicator_bar.panel = this;
                left.append(indicator_bar);
            }

            clock = new Clock();
            clock.panel = this;
            right.append(clock);
        }

        private void start_playerctl_monitor() {
            try {
                string[] spawn_args = {"playerctl", "--follow", "metadata", "--format", "{{playerName}}|{{ artist }} - {{ title }}"};
                int stdout_fd;
                Process.spawn_async_with_pipes(null, spawn_args, null, SpawnFlags.SEARCH_PATH, null, null, null, out stdout_fd, null);
                
                var channel = new IOChannel.unix_new(stdout_fd);
                channel.set_encoding("UTF-8");
                channel.add_watch(IOCondition.IN | IOCondition.HUP, (source, cond) => {
                    if ((cond & IOCondition.HUP) != 0) return false;
                    
                    string line;
                    size_t length, term_pos;
                    if (source.read_line(out line, out length, out term_pos) == IOStatus.NORMAL) {
                        line = line.strip();
                        string[] parts = line.split("|", 2);
                        if (parts.length >= 2 && parts[1] != "" && parts[1] != "-" && parts[1] != " - ") {
                            current_player_name = parts[0].strip();
                            media_label.set_text(parts[1].strip());
                            media_btn.visible = true;
                        } else {
                            media_btn.visible = false;
                        }
                    }
                    return true;
                });
            } catch (Error e) {
                warning("Failed to start playerctl monitor: %s", e.message);
            }
        }

        private bool on_media_scroll(EventControllerScroll ctrl, double dx, double dy) {
            int64 now = get_monotonic_time();
            if (now - last_scroll_time < 400000) return true;
            
            string action = (dy < 0) ? "next" : "previous";
            try {
                Process.spawn_command_line_async("playerctl %s -p %s".printf(action, current_player_name ?? ""));
                last_scroll_time = now;
            } catch (Error e) {
                warning("Failed to dispatch playerctl action: %s", e.message);
            }
            return true;
        }

        private void on_media_clicked() {
            try {
                Process.spawn_command_line_async("playerctl play-pause -p %s".printf(current_player_name ?? ""));
            } catch (Error e) {
                warning("Failed to toggle playback: %s", e.message);
            }
        }

        private bool check_webcam_status() {
            var file = File.new_for_path("/dev/video0");
            if (!file.query_exists()) {
                webcam_icon.visible = false;
                return true;
            }

            try {
                var stream = file.read();
                stream.close();
                webcam_icon.visible = false;
            } catch (GLib.IOError.BUSY e) {
                // Если файл занят другим процессом, значит веб-камера активна
                webcam_icon.visible = true;
            } catch (GLib.Error e) {
                webcam_icon.visible = false;
            }
            return true;
        }

        public Gdk.Monitor get_monitor() { return monitor; }
        public void on_msg_tray_visible() { clock.set_toggled(true); }
        public void on_msg_tray_hidden() { clock.set_toggled(false); }
        public void on_qs_visible() { status_bar.set_toggled(true); }
        public void on_qs_hidden() { status_bar.set_toggled(false); }

        public static void activate_subsystem(Adw.Application app) {
            mediator = Mediator.get_global();
            panels = new HashTable<Gdk.Monitor, Panel>(direct_hash, direct_equal);
            monitors = new GenericArray<Gdk.Monitor>();

            var seat = Gdk.Display.get_default().get_default_seat();
            var display = seat.get_display();
            var monitors_model = display.get_monitors();

            for (uint i = 0; i < monitors_model.get_n_items(); i++) {
                var mon = (Gdk.Monitor)monitors_model.get_item(i);
                on_monitor_added(mon, i);
            }

            monitors_model.items_changed.connect((position, removed, added) => {
                if (added > 0) on_monitor_added((Gdk.Monitor)monitors_model.get_item(position), position);
                if (removed > 0) on_monitor_removed(position);
            });
        }

        private static void on_monitor_added(Gdk.Monitor mon, uint pos) {
            if (!mon.is_valid()) return;
            monitors.insert((int) pos, mon);
            var panel = new Panel();
            panel.attach_to_monitor(mon);
        }

        private static void on_monitor_removed(uint pos) {
            var removed = monitors.get(pos);
            if (removed == null) return;
            monitors.remove_index(pos);
            var panel = panels.lookup(removed);
            if (panel != null) {
                panel.win.destroy();
                panels.remove(removed);
            }
        }
    }
}
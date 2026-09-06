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

        private int64 last_scroll_time = 0;

        public static HashTable<Gdk.Monitor, Panel> get_all_panels() {
            return panels;
        }

        // Монитор, с которым юзер взаимодействовал последним. Синглтон-окна
        // (шторка, трей, OSD, баннер) — по одному на процесс, и без явного
        // gtk_layer_set_monitor компози́тор сам решает, где их показать: клик по
        // панели монитора A мог открыть шторку на мониторе B.
        private static Gdk.Monitor? active_monitor = null;

        public static Gdk.Monitor? get_active_monitor() {
            if (active_monitor != null && active_monitor.is_valid()) return active_monitor;
            if (monitors == null || monitors.length == 0) return null;
            active_monitor = monitors.get(0);
            return active_monitor;
        }

        public static void set_active_monitor(Gdk.Monitor? mon) {
            if (mon != null && mon.is_valid()) active_monitor = mon;
        }

        // true, если окно уже на активном мониторе. Нужно, чтобы различать «клик
        // по той же панели» (закрыть) и «клик по панели другого монитора» (перенести).
        public static bool is_on_active_monitor(Gtk.Window win) {
            var mon = get_active_monitor();
            if (mon == null) return true;
            var current = Gtk4LayerShell.get_monitor(win);
            return current == null || current == mon;
        }

        // Ставит layer-shell окно на монитор, с которым юзер работает сейчас.
        // gtk_layer_set_monitor на показанном окне пересоздаёт surface, поэтому
        // вызываем его до present() и только когда монитор действительно меняется.
        public static void place_on_active_monitor(Gtk.Window win) {
            var mon = get_active_monitor();
            if (mon == null) return;
            if (Gtk4LayerShell.get_monitor(win) == mon) return;
            Gtk4LayerShell.set_monitor(win, mon);
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
            media_btn.tooltip_text = _("Player: click to play or pause, scroll to change track");

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

            var media = MediaPlayerService.get_global();
            media.changed.connect(update_media);
            update_media();

            win.set_child(container); 
        }

        // Вызывается при отключении монитора.
        public void shutdown() {
            win.destroy();
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

        // Панель только рисует: всю работу с MPRIS делает MediaPlayerService,
        // один на процесс независимо от числа мониторов.
        private void update_media() {
            var media = MediaPlayerService.get_global();
            if (!media.available) {
                media_btn.visible = false;
                return;
            }

            string text = media.get_display_text();
            if (text == "") {
                media_btn.visible = false;
                return;
            }

            media_label.set_text(text);
            media_btn.visible = true;
            media_icon.set_from_icon_name(media.playing
                ? "media-playback-start-symbolic"
                : "media-playback-pause-symbolic");
            media_btn.update_property(Gtk.AccessibleProperty.LABEL,
                                      media.playing
                                          ? _("Player, playing: %s").printf(text)
                                          : _("Player, paused: %s").printf(text), -1);
        }

        private bool on_media_scroll(EventControllerScroll ctrl, double dx, double dy) {
            int64 now = get_monotonic_time();
            if (now - last_scroll_time < 400000) return true;

            var media = MediaPlayerService.get_global();
            if (!media.available) return true;

            if (dy < 0) {
                media.next();
            } else {
                media.previous();
            }
            last_scroll_time = now;
            return true;
        }

        private void on_media_clicked() {
            MediaPlayerService.get_global().play_pause();
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
                on_monitor_added(mon);
            }

            // Обрабатываем все элементы, а не только первый: при added=2 вторая
            // панель не создавалась. И не полагаемся на индексы для удаления —
            // они рассинхронизировывались с локальной копией и убивали не ту панель.
            monitors_model.items_changed.connect((position, removed, added) => {
                sync_monitors(monitors_model);
            });
        }

        // Сверяет живые панели с актуальным списком мониторов по самим объектам
        // Gdk.Monitor, а не по позициям в модели.
        private static void sync_monitors(GLib.ListModel model) {
            var current = new GenericArray<Gdk.Monitor>();
            for (uint i = 0; i < model.get_n_items(); i++) {
                var mon = (Gdk.Monitor) model.get_item(i);
                if (mon != null && mon.is_valid()) current.add(mon);
            }

            // Удаляем панели мониторов, которых больше нет.
            var stale = new GenericArray<Gdk.Monitor>();
            foreach (var known in panels.get_keys()) {
                bool still_there = false;
                for (int i = 0; i < current.length; i++) {
                    if (current.get(i) == known) { still_there = true; break; }
                }
                if (!still_there) stale.add(known);
            }
            for (int i = 0; i < stale.length; i++) {
                on_monitor_removed(stale.get(i));
            }

            // Добавляем панели для новых мониторов.
            for (int i = 0; i < current.length; i++) {
                if (panels.lookup(current.get(i)) == null) {
                    on_monitor_added(current.get(i));
                }
            }
        }

        private static void on_monitor_added(Gdk.Monitor mon) {
            if (!mon.is_valid()) return;
            if (panels.lookup(mon) != null) return;
            monitors.add(mon);
            if (active_monitor == null) active_monitor = mon;
            var panel = new Panel();
            panel.attach_to_monitor(mon);
        }

        private static void on_monitor_removed(Gdk.Monitor mon) {
            var panel = panels.lookup(mon);
            if (panel != null) {
                panel.shutdown();
                panels.remove(mon);
            }
            for (int i = 0; i < monitors.length; i++) {
                if (monitors.get(i) == mon) {
                    monitors.remove_index(i);
                    break;
                }
            }
            if (active_monitor == mon) {
                active_monitor = (monitors.length > 0) ? monitors.get(0) : null;
            }
        }
    }
}
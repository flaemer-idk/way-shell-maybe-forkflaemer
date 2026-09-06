using Gtk;
using Adw;

namespace WayShell.QS {
    // Кто именно раскрывает подменю. Нужно, чтобы шапка и сетка гасили друг
    // друга и на экране не оказывалось два раскрытых подменю сразу.
    public enum SubmenuOwner {
        HEADER, GRID
    }

    public class Drawer : GLib.Object {
        private static Drawer? global = null;

        public Gtk.Window win;
        public Box container;
        public Grid qs_grid;

        public signal void will_show();
        public signal void visible();
        public signal void hidden();
        // Эмитится перед раскрытием любого подменю. Слушатели закрывают своё,
        // если владелец не они.
        public signal void submenu_will_open(SubmenuOwner owner);

        public static Drawer get_global() {
            if (global == null) {
                global = new Drawer();
            }
            return global;
        }

        private Drawer() {
            global = this;
            init_layout();
        }

        private void init_layout() {
            win = new Gtk.Window();
            // Блокируем уничтожение вместо пересборки layout — иначе каждое
            // закрытие создавало новое окно и новый набор подписок на сервисы.
            win.close_request.connect(() => {
                set_hidden();
                return true;
            });

            Gtk4LayerShell.init_for_window(win);
            Gtk4LayerShell.set_namespace(win, "way-shell-quick-settings");
            Gtk4LayerShell.set_layer(win, Gtk4LayerShell.Layer.OVERLAY);
            Gtk4LayerShell.set_anchor(win, Gtk4LayerShell.Edge.TOP, true);
            Gtk4LayerShell.set_anchor(win, Gtk4LayerShell.Edge.LEFT, true);
            Gtk4LayerShell.set_margin(win, Gtk4LayerShell.Edge.TOP, 8);
            Gtk4LayerShell.set_margin(win, Gtk4LayerShell.Edge.LEFT, 20);
            
            Gtk4LayerShell.set_keyboard_mode(win, Gtk4LayerShell.KeyboardMode.NONE);
            win.name = "quick-settings";

            container = new Box(Orientation.VERTICAL, 0);
            container.set_size_request(400, -1);

            var header = new Header();
            container.append(header);

            // --- Добавляем наши новые слайдеры Scales ---
            var scales = new Scales();
            container.append(scales);

            qs_grid = new Grid();
            container.append(qs_grid);

            win.set_child(container);
        }
        
        public void set_visible() {
            will_show();
            if (qs_grid != null) {
                qs_grid.refresh_grid_layout();
            }
            // Шторка одна на весь процесс — привязываем к монитору кликнутой панели,
            // иначе компози́тор выбирает выход сам.
            WayShell.Panel.Panel.place_on_active_monitor(win);
            win.set_opacity(1.0);
            win.present();
            visible();
        }

        public void set_hidden() {
            win.set_visible(false);
            hidden();
            set_focused(false);
            shrink();
        }

        public void toggle() {
            if (!win.get_visible()) {
                set_visible();
                return;
            }
            // Окно одно на процесс: клик по панели другого монитора должен перенести
            // шторку туда, а не просто закрыть её.
            if (WayShell.Panel.Panel.is_on_active_monitor(win)) {
                set_hidden();
            } else {
                // Скрываем без сигнала hidden(): Mediator на нём гасит подсветку
                // кнопок панели, а мы тут же показываемся снова.
                win.set_visible(false);
                set_visible();
            }
        }

        public void shrink() {
            container.set_size_request(400, -1);
            win.set_default_size(400, 1);
            win.queue_resize();
        }

        public void set_focused(bool focus) {
            if (focus) {
                win.add_css_class("focused");
            } else {
                win.remove_css_class("focused");
            }
        }
    }
}
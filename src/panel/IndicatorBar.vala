using Gtk;
using WayShell.Services;

namespace WayShell.Panel {
    public class IndicatorWidget : Box {
        public Box box;
        public Image icon;
        public Button button;
        public PopoverMenu menu;
        public StatusNotifierItem sni;

        public IndicatorWidget(StatusNotifierItem sni) {
            Object(orientation: Orientation.HORIZONTAL, spacing: 0);
            this.sni = sni;
            this.name = "panel-indicator-bar-widget";

            box = new Box(Orientation.HORIZONTAL, 0);
            box.add_css_class("panel-indicator-bar-widget-box");

            icon = new Image.from_icon_name("image-missing");
            button = new Button();
            button.set_child(icon);

            box.append(button);
            this.append(box);

            update_icon();

            if (sni.menu_model != null) {
                menu = new PopoverMenu.from_model_full(sni.menu_model, PopoverMenuFlags.NESTED);
                menu.set_parent(button);
                menu.insert_action_group("sni", sni.action_group);
                button.clicked.connect(() => {
                    menu.popup();
                    sni.about_to_show(0);
                });
            } else {
                button.clicked.connect(() => {
                    try {
                        sni.proxy.activate(0, 0);
                    } catch (Error e) {
                        warning("Failed to activate SNI: %s", e.message);
                    }
                });
            }

            var s = StatusNotifierService.get_global();
            s.status_notifier_item_properties_changed.connect((item) => {
                if (item == sni) update_icon();
            });
            s.status_notifier_item_menu_updated.connect((item) => {
                if (item == sni && menu != null) {
                    menu.set_menu_model(sni.menu_model);
                }
            });
        }

        private void update_icon() {
            if (sni.icon_pixmap_from_theme != null) {
                // Изменено на новый конструктор GTK4
                var t =  Gdk.Texture.for_pixbuf(sni.icon_pixmap_from_theme);
                icon.set_from_paintable(t);
            } else if (sni.icon_name != null && sni.icon_name != "") {
                icon.set_from_icon_name(sni.icon_name);
            } else if (sni.icon_pixmap != null) {
                // Изменено на новый конструктор GTK4
                var t =  Gdk.Texture.for_pixbuf(sni.icon_pixmap);
                icon.set_from_paintable(t);
            } else {
                icon.set_from_icon_name("image-missing");
            }
        }
    }

    public class IndicatorBar : Box {
        public weak Panel panel;
        public Box list;
        private HashTable<string, IndicatorWidget> indicators;

        public IndicatorBar() {
            Object(orientation: Orientation.HORIZONTAL, spacing: 0);
            this.name = "panel-indicator-bar";
            indicators = new HashTable<string, IndicatorWidget>(str_hash, str_equal);

            list = new Box(Orientation.HORIZONTAL, 0);
            list.add_css_class("panel-indicator-bar-list");
            this.append(list);

            var sn = StatusNotifierService.get_global();
            if (sn == null) return;

            sn.status_notifier_item_added.connect(on_item_added);
            sn.status_notifier_item_removed.connect(on_item_removed);

            foreach (var sni in sn.get_items().get_values()) {
                on_item_added(sn.get_items(), sni);
            }
        }

        private void on_item_added(HashTable<string, StatusNotifierItem> items, StatusNotifierItem sni) {
            var widget = new IndicatorWidget(sni);
            indicators.insert(sni.bus_name, widget);
            list.append(widget);
        }

        private void on_item_removed(HashTable<string, StatusNotifierItem> items, StatusNotifierItem sni) {
            var widget = indicators.lookup(sni.bus_name);
            if (widget != null) {
                list.remove(widget);
                indicators.remove(sni.bus_name);
            }
        }
    }
}
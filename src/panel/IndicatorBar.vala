// Путь: src/panel/IndicatorBar.vala
//
// Виджет системного трея. Данные берёт из StatusNotifierService, который
// работает watcher'ом org.kde.StatusNotifierWatcher.
using Gtk;
using WayShell.Services;

namespace WayShell.Panel {
    public class IndicatorWidget : Box {
        public Image icon;
        public Button button;
        public PopoverMenu? menu = null;
        public StatusNotifierItem sni;

        private ulong updated_handler = 0;
        private ulong menu_handler = 0;

        public IndicatorWidget(StatusNotifierItem sni) {
            Object(orientation: Orientation.HORIZONTAL, spacing: 0);
            this.sni = sni;
            this.name = "panel-indicator-bar-widget";

            icon = new Image.from_icon_name("image-missing");
            button = new Button();
            button.add_css_class("panel-button");
            button.set_child(icon);
            this.append(button);

            // Правая кнопка — контекстное меню, как в любой панели. Левая по
            // спецификации активирует приложение, но если ItemIsMenu, то меню
            // должно открываться и левой.
            var right_click = new GestureClick();
            right_click.button = Gdk.BUTTON_SECONDARY;
            right_click.pressed.connect(() => { popup_menu(); });
            button.add_controller(right_click);

            var middle_click = new GestureClick();
            middle_click.button = Gdk.BUTTON_MIDDLE;
            middle_click.pressed.connect(() => { sni.secondary_activate(0, 0); });
            button.add_controller(middle_click);

            var scroll = new EventControllerScroll(EventControllerScrollFlags.BOTH_AXES);
            scroll.scroll.connect(on_scroll);
            button.add_controller(scroll);

            button.clicked.connect(() => {
                if (sni.item_is_menu && menu != null) {
                    popup_menu();
                } else {
                    sni.activate_item(0, 0);
                }
            });

            updated_handler = sni.updated.connect(update_from_item);
            menu_handler = sni.menu_updated.connect(rebuild_menu);

            update_from_item();
            rebuild_menu();
        }

        // Поповер с set_parent() не входит в дерево детей и сам не убирается:
        // без unparent() GTK ругается при уничтожении родителя. Подписки снимаем
        // тут же: сигналы живут на sni, а он не наш объект.
        public override void dispose() {
            if (updated_handler != 0) {
                sni.disconnect(updated_handler);
                updated_handler = 0;
            }
            if (menu_handler != 0) {
                sni.disconnect(menu_handler);
                menu_handler = 0;
            }
            if (menu != null) {
                menu.unparent();
                menu = null;
            }
            base.dispose();
        }

        private void popup_menu() {
            if (menu == null) return;
            sni.about_to_show();
            menu.popup();
        }

        private bool on_scroll(EventControllerScroll ctrl, double dx, double dy) {
            // Значки регуляторов громкости и яркости ждут именно этого.
            if (dy != 0) sni.scroll((int) (dy * 120), "vertical");
            if (dx != 0) sni.scroll((int) (dx * 120), "horizontal");
            return true;
        }

        private void rebuild_menu() {
            if (sni.menu_model == null) {
                if (menu != null) {
                    menu.unparent();
                    menu = null;
                }
                return;
            }

            if (menu == null) {
                menu = new PopoverMenu.from_model_full(sni.menu_model, PopoverMenuFlags.NESTED);
                menu.set_parent(button);
                menu.has_arrow = false;
            } else {
                menu.set_menu_model(sni.menu_model);
            }

            if (sni.action_group != null) {
                menu.insert_action_group(DbusMenu.ACTION_PREFIX, sni.action_group);
            }
        }

        private void update_from_item() {
            // Passive по спецификации значит «скрыть значок».
            this.visible = (sni.status != "Passive");

            if (sni.icon_name != "") {
                icon.set_from_icon_name(sni.icon_name);
            } else if (sni.icon_paintable != null) {
                icon.set_from_paintable(sni.icon_paintable);
            } else {
                icon.set_from_icon_name("image-missing");
            }

            if (sni.status == "NeedsAttention") {
                button.add_css_class("needs-attention");
            } else {
                button.remove_css_class("needs-attention");
            }

            string label = (sni.tooltip != "") ? sni.tooltip
                         : (sni.title != "") ? sni.title : sni.id;
            button.tooltip_text = label;
            button.update_property(Gtk.AccessibleProperty.LABEL, label, -1);
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

            list = new Box(Orientation.HORIZONTAL, 2);
            list.add_css_class("panel-indicator-bar-list");
            this.append(list);

            var sn = StatusNotifierService.get_global();
            if (sn == null) return;

            sn.item_added.connect(on_item_added);
            sn.item_removed.connect(on_item_removed);

            foreach (var sni in sn.get_items().get_values()) {
                on_item_added(sni);
            }
        }

        private void on_item_added(StatusNotifierItem sni) {
            if (indicators.contains(sni.key)) return;
            var widget = new IndicatorWidget(sni);
            indicators.insert(sni.key, widget);
            list.append(widget);
        }

        private void on_item_removed(StatusNotifierItem sni) {
            var widget = indicators.lookup(sni.key);
            if (widget != null) {
                list.remove(widget);
                indicators.remove(sni.key);
            }
        }
    }
}

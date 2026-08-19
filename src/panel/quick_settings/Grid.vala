// Путь: src/panel/quick_settings/Grid.vala
using Gtk;

namespace WayShell.QS {
    public class Grid : Box {
        private GenericArray<GridCluster> clusters;
        private bool compacting = false;

        public WifiButton wifi_button;
        public EthernetButton eth_button;
        public BluetoothButton bt_button;
        public DndButton dnd_button;

        public Grid() {
            Object(orientation: Orientation.VERTICAL, spacing: 0);
            this.name = "quick-settings-grid";
            this.hexpand = true;
            this.vexpand = true;

            clusters = new GenericArray<GridCluster>();

            // Создаем экземпляры модулей
            wifi_button = new WifiButton();
            eth_button = new EthernetButton();
            bt_button = new BluetoothButton();
            dnd_button = new DndButton();

            // Подписываемся на динамические изменения состояний железа
            eth_button.state_changed.connect(refresh_grid_layout);
            wifi_button.state_changed.connect(refresh_grid_layout);
            bt_button.state_changed.connect(refresh_grid_layout);

            var qs = Drawer.get_global();
            qs.will_show.connect(refresh_grid_layout);

            refresh_grid_layout();
        }

        public void refresh_grid_layout() {
            var desired_buttons = new GenericArray<GridButton>();

            // 1. Wi-Fi (если физически есть чип)
            if (WifiButton.has_wireless_hardware()) {
                desired_buttons.add(wifi_button);
            }

            // 2. Ethernet (Умный показ: подключен кабель -> всегда, отключен кабель -> только на ПК без Wi-Fi)
            if (eth_button.should_be_visible()) {
                desired_buttons.add(eth_button);
            }

            // 3. Bluetooth (если физически есть адаптер/донгл)
            if (BluetoothButton.has_bluetooth_hardware()) {
                desired_buttons.add(bt_button);
            }

            // 4. Do Not Disturb (всегда)
            desired_buttons.add(dnd_button);

            // Проверяем, изменился ли состав кнопок
            if (!needs_rebuild(desired_buttons)) {
                return;
            }

            rebuild_clusters(desired_buttons);
        }

        private GenericArray<GridButton> get_current_buttons() {
            var list = new GenericArray<GridButton>();
            for (int i = 0; i < clusters.length; i++) {
                var c = clusters.get(i);
                if (c.left != c.dummy_left) {
                    list.add(c.left);
                }
                if (c.right != c.dummy_right) {
                    list.add(c.right);
                }
            }
            return list;
        }

        private bool needs_rebuild(GenericArray<GridButton> desired) {
            var current = get_current_buttons();
            if (current.length != desired.length) return true;
            for (int i = 0; i < current.length; i++) {
                if (current.get(i) != desired.get(i)) return true;
            }
            return false;
        }

        private void detach_button(GridButton button) {
            var p = button.get_parent();
            if (p != null) {
                if (p is CenterBox) {
                    var cb = (CenterBox) p;
                    if (cb.get_start_widget() == button) cb.set_start_widget(null);
                    if (cb.get_end_widget() == button) cb.set_end_widget(null);
                    if (cb.get_center_widget() == button) cb.set_center_widget(null);
                } else if (p is Box) {
                    ((Box) p).remove(button);
                }
            }
            if (button.revealer != null && button.revealer.get_parent() != null) {
                var rev_p = button.revealer.get_parent();
                if (rev_p is Box) {
                    ((Box) rev_p).remove(button.revealer);
                }
            }
        }

        private void rebuild_clusters(GenericArray<GridButton> buttons) {
            hide_all_revealers();

            // Очищаем старые контейнеры
            Widget? child;
            while ((child = this.get_first_child()) != null) {
                this.remove(child);
            }
            clusters.remove_range(0, clusters.length);

            // Добавляем актуальные кнопки
            for (int i = 0; i < buttons.length; i++) {
                var btn = buttons.get(i);
                detach_button(btn);
                add_button(btn);
            }
        }

        public void hide_all_revealers() {
            for (int i = 0; i < clusters.length; i++) {
                var c = clusters.get(i);
                c.hide_all();
            }
            var qs = Drawer.get_global();
            qs.shrink();
            qs.set_focused(false);
        }

        public void add_button(GridButton button) {
            GridCluster? target_cluster = null;
            ClusterSide side = ClusterSide.NONE;

            for (int i = 0; i < clusters.length; i++) {
                var c = clusters.get(i);
                if (!c.is_full()) {
                    target_cluster = c;
                    side = c.vacant_side();
                    break;
                }
            }

            if (target_cluster == null) {
                target_cluster = new GridCluster();
                target_cluster.will_reveal_button.connect(on_cluster_will_reveal);
                target_cluster.removed.connect((side) => {
                    compact_grid(target_cluster, side);
                });
                side = ClusterSide.LEFT;
                this.append(target_cluster);
                clusters.add(target_cluster);
            }

            target_cluster.add_button(side, button);
        }

        private void on_cluster_will_reveal(GridButton button) {
            for (int i = 0; i < clusters.length; i++) {
                var c = clusters.get(i);
                if (c != button.cluster) c.hide_all();
            }
        }

        private void compact_grid(GridCluster cluster, ClusterSide side) {
            if (compacting) return;
            compacting = true;

            if (clusters.length <= 1) {
                compacting = false;
                return;
            }

            for (int i = 0; i < clusters.length - 1; i++) {
                var current = clusters.get(i);
                var next = clusters.get(i + 1);
                if (current.vacant_side() == ClusterSide.RIGHT) {
                    var next_left = next.left;
                    next.remove_button(next_left);
                    current.add_button(ClusterSide.RIGHT, next_left);
                }
            }

            for (int i = clusters.length - 1; i >= 0; i--) {
                var c = clusters.get(i);
                if (c.vacant_side() == ClusterSide.BOTH) {
                    this.remove(c);
                    clusters.remove_index(i);
                }
            }
            compacting = false;
        }
    }
}
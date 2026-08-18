// Путь: src/panel/quick_settings/Grid.vala
using Gtk;

namespace WayShell.QS {
    public class Grid : Box {
        private GenericArray<GridCluster> clusters;
        private bool compacting = false;

        public Grid() {
            Object(orientation: Orientation.VERTICAL, spacing: 0);
            this.name = "quick-settings-grid";
            this.hexpand = true;
            this.vexpand = true;

            clusters = new GenericArray<GridCluster>();
            setup_grid_layout();
        }

        private void setup_grid_layout() {
            // Wi-Fi (только если есть чип)
            if (WifiButton.has_wireless_hardware()) {
                add_button(new WifiButton());
            }

            // Ethernet
            add_button(new EthernetButton());

            // Bluetooth (только если есть адаптер)
            if (BluetoothButton.has_bluetooth_hardware()) {
                add_button(new BluetoothButton());
            }

            // Не беспокоить
            add_button(new DndButton());
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
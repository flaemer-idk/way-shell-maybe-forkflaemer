// Путь: src/panel/quick_settings/GridCluster.vala
using Gtk;

namespace WayShell.QS {
    public enum ClusterSide {
        NONE, BOTH, LEFT, RIGHT
    }

    public class GridCluster : Box {
        public CenterBox center_box;
        public GridButton left;
        public GridButton right;
        public GridButton dummy_left;
        public GridButton dummy_right;

        public signal void empty();
        public signal void removed(ClusterSide side);
        public signal void will_reveal_button(GridButton button);

        public GridCluster() {
            Object(orientation: Orientation.VERTICAL, spacing: 0);

            center_box = new CenterBox();
            this.append(center_box);

            dummy_left = new GridButton(ButtonType.GENERIC, "dummy", "dummy", "image-missing");
            dummy_left.add_css_class("quick-settings-grid-button-transparent");
            dummy_right = new GridButton(ButtonType.GENERIC, "dummy", "dummy", "image-missing");
            dummy_right.add_css_class("quick-settings-grid-button-transparent");

            left = dummy_left;
            right = dummy_right;

            center_box.set_start_widget(dummy_left);
            center_box.set_end_widget(dummy_right);

            var qs = Drawer.get_global();
            qs.hidden.connect(hide_all);
        }

        public void hide_all() {
            if (left.revealer != null) left.revealer.set_reveal_child(false);
            if (right.revealer != null) right.revealer.set_reveal_child(false);
        }

        public void will_reveal(GridButton button) {
            will_reveal_button(button);
            if (button == right && left.revealer != null) {
                left.revealer.set_reveal_child(false);
            }
            if (button == left && right.revealer != null) {
                right.revealer.set_reveal_child(false);
            }
        }

        public void add_button(ClusterSide side, GridButton button) {
            if (side == ClusterSide.NONE) return;
            button.cluster = this;

            if (side == ClusterSide.LEFT) {
                center_box.set_start_widget(button);
                left = button;
            } else {
                center_box.set_end_widget(button);
                right = button;
            }

            if (button.revealer != null) {
                if (button.revealer.get_parent() != null) {
                    var p = button.revealer.get_parent();
                    if (p is Box) {
                        ((Box) p).remove(button.revealer);
                    }
                }
                this.append(button.revealer);
            }
        }

        public void slide_left() {
            if (right == dummy_right) return;
            center_box.set_end_widget(dummy_right);
            center_box.set_start_widget(right);
            left = right;
            right = dummy_right;
        }

        public void remove_button(GridButton button) {
            ClusterSide side = ClusterSide.NONE;

            if (left == button) {
                side = ClusterSide.LEFT;
                center_box.set_start_widget(dummy_left);
                left = dummy_left;
                slide_left();
            } else if (right == button) {
                side = ClusterSide.RIGHT;
                center_box.set_end_widget(dummy_right);
                right = dummy_right;
            }

            if (button.revealer != null && button.revealer.get_parent() == this) {
                this.remove(button.revealer);
            }

            removed(side);
        }

        public bool is_full() {
            return left != dummy_left && right != dummy_right;
        }

        public ClusterSide vacant_side() {
            if (left == dummy_left && right == dummy_right) return ClusterSide.BOTH;
            if (left == dummy_left) return ClusterSide.LEFT;
            if (right == dummy_right) return ClusterSide.RIGHT;
            return ClusterSide.NONE;
        }
    }
}
using Gtk;
using Adw;

namespace WayShell.Dialog {
    // Делегат для безопасного выполнения отложенного подтверждения действия
    public delegate void ConfirmCallback();

    public class DialogOverlay : GLib.Object {
        private static DialogOverlay? global = null;

        public Gtk.Window win;
        public Box dialog;
        public Label heading;
        public Label body;
        public Button confirm;
        public Button cancel;
        private ConfirmCallback? pending_cb = null;

        public static DialogOverlay get_global() {
            if (global == null) {
                global = new DialogOverlay();
            }
            return global;
        }

        private DialogOverlay() {
            init_layout();
        }

        private void init_layout() {
            win = new Gtk.Window();
            win.name = "dialog-overlay";

            Gtk4LayerShell.init_for_window(win);
            Gtk4LayerShell.set_namespace(win, "way-shell-dialog");
            Gtk4LayerShell.set_layer(win, Gtk4LayerShell.Layer.OVERLAY);
            Gtk4LayerShell.set_anchor(win, Gtk4LayerShell.Edge.TOP, true);
            Gtk4LayerShell.set_anchor(win, Gtk4LayerShell.Edge.BOTTOM, true);
            Gtk4LayerShell.set_anchor(win, Gtk4LayerShell.Edge.LEFT, true);
            Gtk4LayerShell.set_anchor(win, Gtk4LayerShell.Edge.RIGHT, true);
            
            // Захватываем фокус клавиатуры полностью на себя
            Gtk4LayerShell.set_keyboard_mode(win, Gtk4LayerShell.KeyboardMode.EXCLUSIVE);
            win.visible = false;

            dialog = new Box(Orientation.VERTICAL, 0);
            dialog.name = "dialog-overlay-container";
            dialog.halign = Align.CENTER;
            dialog.valign = Align.CENTER;
            dialog.set_size_request(420, 200);

            heading = new Label("");
            heading.add_css_class("dialog-overlay-heading");
            heading.halign = Align.CENTER;
            heading.valign = Align.CENTER;
            heading.xalign = 0.5f;

            body = new Label("");
            body.add_css_class("dialog-overlay-body");
            body.halign = Align.CENTER;
            body.valign = Align.CENTER;
            body.xalign = 0.5f;

            var buttons_container = new CenterBox();
            buttons_container.hexpand = true;
            buttons_container.vexpand = true;

            confirm = new Button.with_label("Confirm");
            confirm.add_css_class("dialog-overlay-confirm");
            confirm.hexpand = true;

            cancel = new Button.with_label("Cancel");
            cancel.add_css_class("dialog-overlay-cancel");
            cancel.hexpand = true;

            buttons_container.set_start_widget(cancel);
            buttons_container.set_end_widget(confirm);

            confirm.clicked.connect(on_confirm_clicked);
            cancel.clicked.connect(on_cancel_clicked);

            dialog.append(heading);
            dialog.append(body);
            dialog.append(buttons_container);

            win.set_child(dialog);
        }

        private void on_confirm_clicked() {
            win.visible = false;
            if (pending_cb != null) {
                pending_cb();
                pending_cb = null;
            }
        }

        private void on_cancel_clicked() {
            win.visible = false;
            pending_cb = null;
        }

        public void present(string heading_text, string body_text, owned ConfirmCallback callback) {
            heading.set_text(heading_text);
            body.set_text(body_text);
            pending_cb = (owned) callback;
            win.visible = true;
        }
    }
}
using Gtk;

namespace WayShell.QS {
    public enum ButtonType {
        GENERIC,
        WIFI,
        BLUETOOTH,
        DND,
        NIGHT_LIGHT,
        AIRPLANE_MODE,
        KEYBOARD_BRIGHTNESS,
        VPN
    }

    public class GridButton : Box {
        public weak GridCluster cluster;
        public ButtonType button_type;
        public Button toggle;
        public Label? title;
        public Label? subtitle;
        public Image? icon;
        public Button? reveal_button;
        public Widget? reveal_widget;
        public Revealer? revealer;

        public signal void reveal_changed(bool is_revealed);

        public GridButton(ButtonType type, string? title_text, string? subtitle_text, string? icon_name, Widget? reveal_widget = null) {
            Object(orientation: Orientation.HORIZONTAL, spacing: 0);
            this.button_type = type;
            this.reveal_widget = reveal_widget;
            this.hexpand = true;
            this.set_size_request(100, 60);
            this.add_css_class("quick-settings-grid-button");

            toggle = new Button();
            toggle.add_css_class("quick-settings-grid-button-toggle");
            toggle.hexpand = true;

            var overlay = new Overlay();
            overlay.set_child(toggle);

            var button_contents = new Box(Orientation.HORIZONTAL, 0);
            button_contents.valign = Align.CENTER;

            if (icon_name != null) {
                icon = new Image.from_icon_name(icon_name);
                icon.pixel_size = 20;
                icon.add_css_class("quick-settings-grid-button-icon");
                icon.halign = Align.START;
                button_contents.append(icon);
            }

            var text_area = new Box(Orientation.VERTICAL, 0);
            toggle.add_css_class("with-subtitle");

            if (title_text != null) {
                title = new Label(title_text);
                title.ellipsize = Pango.EllipsizeMode.END;
                title.width_chars = 12;
                title.max_width_chars = 12;
                title.xalign = 0.0f;
                title.add_css_class("quick-settings-grid-button-title");
                title.halign = Align.START;
                text_area.append(title);
            }

            if (subtitle_text != null) {
                subtitle = new Label(subtitle_text);
                subtitle.ellipsize = Pango.EllipsizeMode.END;
                subtitle.width_chars = 12;
                subtitle.max_width_chars = 12;
                subtitle.xalign = 0.0f;
                subtitle.add_css_class("quick-settings-grid-button-subtitle");
                subtitle.halign = Align.START;
                text_area.append(subtitle);
            } else if (title != null) {
                title.vexpand = true;
                title.valign = Align.CENTER;
                toggle.remove_css_class("with-subtitle");
            }

            button_contents.append(text_area);
            toggle.set_child(button_contents);
            this.append(overlay);

            if (reveal_widget != null) {
                toggle.add_css_class("with-revealer");
                reveal_button = new Button.from_icon_name("go-next-symbolic");
                reveal_button.add_css_class("quick-settings-grid-button-reveal-hidden");
                reveal_button.add_css_class("quick-settings-grid-button-reveal-visible");
                reveal_button.halign = Align.END;
                // Стрелка без метки для скринридера — безымянная кнопка; берём имя
                // из заголовка самой кнопки.
                if (title_text != null) {
                    reveal_button.tooltip_text = _("%s: more").printf(title_text);
                    reveal_button.update_property(Gtk.AccessibleProperty.LABEL,
                                                 _("%s: more").printf(title_text), -1);
                }
                reveal_button.update_state(Gtk.AccessibleState.EXPANDED, false, -1);

                overlay.add_overlay(reveal_button);

                revealer = new Revealer();
                revealer.transition_type = RevealerTransitionType.SLIDE_DOWN;
                revealer.transition_duration = 350;
                revealer.set_reveal_child(false);
                revealer.add_css_class("quick-settings-grid-button-revealer");
                revealer.set_child(reveal_widget);

                reveal_button.clicked.connect(() => {
                    var qs = Drawer.get_global();
                    if (revealer.get_reveal_child()) {
                        revealer.set_reveal_child(false);
                        reveal_button.update_state(Gtk.AccessibleState.EXPANDED, false, -1);
                        qs.shrink();
                        qs.set_focused(false);
                        reveal_changed(false);
                    } else {
                        cluster.will_reveal(this);
                        qs.set_focused(true);
                        revealer.set_reveal_child(true);
                        reveal_button.update_state(Gtk.AccessibleState.EXPANDED, true, -1);
                        reveal_changed(true);
                    }
                });
            }
        }

        public void set_toggled(bool toggled) {
            if (toggled) {
                toggle.remove_css_class("off");
                if (reveal_button != null) reveal_button.remove_css_class("off");
            } else {
                toggle.add_css_class("off");
                if (reveal_button != null) reveal_button.add_css_class("off");
            }
            // Состояние выражалось только CSS-классом — для скринридера кнопка
            // выглядела одинаково во включённом и выключенном виде.
            toggle.update_state(Gtk.AccessibleState.PRESSED,
                                toggled ? Gtk.AccessibleTristate.TRUE : Gtk.AccessibleTristate.FALSE,
                                -1);
        }
    }
}
// Путь: src/panel/quick_settings/modules/header/Header.vala
using Gtk;
using GLib;

namespace WayShell.QS {
    public class Header : Box {
        public CenterBox center_box;
        
        public BatteryButton battery_button;
        public BatteryMenu battery_menu;
        public Revealer battery_revealer;

        public Button power_button;
        public PowerMenu power_menu;
        public Revealer power_revealer;

        public Button mixer_button;
        public MixerMenu mixer_menu;
        public Revealer mixer_revealer;

        public Header() {
            Object(orientation: Orientation.VERTICAL, spacing: 0);
            this.name = "quick-settings-header-container";

            center_box = new CenterBox();
            center_box.name = "quick-settings-header";
            this.append(center_box);

            // --- Левая часть: кнопка батареи ---
            battery_button = new BatteryButton();
            center_box.set_start_widget(battery_button);

            // --- Правая часть: кнопки микшера и выключения ---
            var buttons_box = new Box(Orientation.HORIZONTAL, 8);
            
            mixer_button = new Button.from_icon_name("audio-speakers-symbolic");
            mixer_button.add_css_class("circular");
            buttons_box.append(mixer_button);

            power_button = new Button.from_icon_name("system-shutdown-symbolic");
            power_button.add_css_class("circular");
            buttons_box.append(power_button);

            center_box.set_end_widget(buttons_box);

            // --- Ревелеры подменю ---
            battery_menu = new BatteryMenu();
            battery_revealer = new Revealer();
            battery_revealer.transition_type = RevealerTransitionType.SLIDE_DOWN;
            battery_revealer.transition_duration = 250;
            battery_revealer.set_child(battery_menu);
            this.append(battery_revealer);

            mixer_menu = new MixerMenu();
            mixer_revealer = new Revealer();
            mixer_revealer.transition_type = RevealerTransitionType.SLIDE_DOWN;
            mixer_revealer.transition_duration = 250;
            mixer_revealer.set_child(mixer_menu);
            this.append(mixer_revealer);

            power_menu = new PowerMenu();
            power_revealer = new Revealer();
            power_revealer.transition_type = RevealerTransitionType.SLIDE_DOWN;
            power_revealer.transition_duration = 250;
            power_revealer.set_child(power_menu);
            this.append(power_revealer);

            // --- Обработка кликов кнопок шапки ---
            battery_button.clicked.connect(on_battery_clicked);
            mixer_button.clicked.connect(on_mixer_clicked);
            power_button.clicked.connect(on_power_clicked);

            var qs = Drawer.get_global();
            qs.hidden.connect(collapse_all);
        }

        private void on_battery_clicked() {
            toggle_revealer(battery_revealer);
        }

        private void on_mixer_clicked() {
            toggle_revealer(mixer_revealer);
            if (mixer_revealer.get_reveal_child()) {
                mixer_menu.refresh_mixer_list();
            }
        }

        private void on_power_clicked() {
            toggle_revealer(power_revealer);
        }

        private void toggle_revealer(Revealer active) {
            var qs = Drawer.get_global();
            bool state = active.get_reveal_child();
            
            if (active != battery_revealer) battery_revealer.set_reveal_child(false);
            if (active != mixer_revealer) mixer_revealer.set_reveal_child(false);
            if (active != power_revealer) power_revealer.set_reveal_child(false);

            if (state) {
                active.set_reveal_child(false);
                qs.shrink();
                qs.set_focused(false);
            } else {
                qs.set_focused(true);
                active.set_reveal_child(true);
            }
        }

        public void collapse_all() {
            battery_revealer.set_reveal_child(false);
            mixer_revealer.set_reveal_child(false);
            power_revealer.set_reveal_child(false);
            power_menu.collapse_all_confirmations();
        }
    }
}
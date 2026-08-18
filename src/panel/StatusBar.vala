// Путь: src/panel/StatusBar.vala
using Gtk;
using Adw;
using Gtk4LayerShell;
using WayShell.Services;

namespace WayShell.Panel {
    public class StatusBar : Box {
        public weak Panel panel;
        public Button button;
        public Box box;
        private bool toggled = false;
        private GenericArray<Widget> buttons;

        public StatusBar() {
            Object(orientation: Orientation.HORIZONTAL, spacing: 0);
            buttons = new GenericArray<Widget>();

            button = new Button();
            button.add_css_class("panel-button");
            button.clicked.connect(() => {
                var qs = WayShell.QS.Drawer.get_global();
                if (qs != null) qs.toggle();
            });

            box = new Box(Orientation.HORIZONTAL, 4);

            var idle_btn = new IdleInhibitorButton();
            box.append(idle_btn);
            buttons.add(idle_btn);

            var night_btn = new NightLightButton();
            box.append(night_btn);
            buttons.add(night_btn);

            var vpn_btn = new VpnButton();
            box.append(vpn_btn);
            buttons.add(vpn_btn);

            var net_btn = new NetworkButton();
            box.append(net_btn);
            buttons.add(net_btn);

            var sound_btn = new SoundButton();
            box.append(sound_btn);
            buttons.add(sound_btn);

            var power_btn = new PowerButton();
            box.append(power_btn);
            buttons.add(power_btn);

            button.set_child(box);
            this.append(button);
        }

        public void set_toggled(bool val) {
            this.toggled = val;
            if (val) {
                button.add_css_class("panel-button-toggled");
            } else {
                button.remove_css_class("panel-button-toggled");
            }
        }
    }

    public class IdleInhibitorButton : Box {
        private Image icon;

        public IdleInhibitorButton() {
            Object(orientation: Orientation.HORIZONTAL, spacing: 0);
            icon = new Image.from_icon_name("radio-mixed-symbolic");
            this.append(icon);

            var logind = LogindService.get_global();
            if (logind == null) {
                this.visible = false;
                return;
            }

            this.visible = logind.get_idle_inhibit();
            logind.idle_inhibitor_changed.connect((inhibited) => {
                this.visible = inhibited;
            });
        }
    }

    public class NightLightButton : Box {
        private Image icon;

        public NightLightButton() {
            Object(orientation: Orientation.HORIZONTAL, spacing: 0);
            icon = new Image.from_icon_name("night-light-symbolic");
            this.append(icon);

            this.visible = false;
            var g = WaylandGammaControlService.get_global();
            if (g != null) {
                this.visible = g.enabled();
                g.gamma_control_enabled.connect(() => { this.visible = true; });
                g.gamma_control_disabled.connect(() => { this.visible = false; });
            }
        }
    }

    public class VpnButton : Box {
        private Image icon;

        public VpnButton() {
            Object(orientation: Orientation.HORIZONTAL, spacing: 0);
            icon = new Image.from_icon_name("network-vpn-symbolic");
            this.append(icon);

            this.visible = false;
            var nm = NetworkManagerService.get_global();
            if (nm == null) return;

            update_status(nm);
            nm.vpn_activated.connect(() => { this.visible = true; });
            nm.vpn_deactivated.connect(() => { update_status(nm); });
        }

        private void update_status(NetworkManagerService nm) {
            var conns = nm.get_active_vpn_connections();
            this.visible = (conns != null && conns.length > 0);
        }
    }

    public class NetworkButton : Box {
        private Image icon;

        public NetworkButton() {
            Object(orientation: Orientation.HORIZONTAL, spacing: 0);
            icon = new Image.from_icon_name("network-wired-symbolic");
            this.append(icon);

            var nm = NetworkManagerService.get_global();
            if (nm == null) return;

            update_status(nm);
            nm.changed.connect(() => { update_status(nm); });
        }

        private void update_status(NetworkManagerService nm) {
            if (!nm.get_networking_enabled()) {
                this.visible = false;
                return;
            }
            this.visible = true;

            bool has_wifi = nm.wifi_available();
            var dev = nm.get_primary_device();
            var state = nm.get_state();

            if (state == NM.State.DISCONNECTED || state == NM.State.DISCONNECTING) {
                icon.set_from_icon_name(has_wifi ? "network-wireless-offline-symbolic" : "network-wired-offline-symbolic");
            } else if (state == NM.State.CONNECTING) {
                icon.set_from_icon_name(has_wifi ? "network-wireless-acquiring-symbolic" : "network-wired-acquiring-symbolic");
            } else if (state == NM.State.CONNECTED_GLOBAL) {
                if (dev != null && dev.device_type == NM.DeviceType.WIFI) {
                    var wifi = (NM.DeviceWifi)dev;
                    var ap = wifi.get_active_access_point();
                    if (ap != null) {
                        icon.set_from_icon_name(NetworkManagerService.ap_strength_to_icon_name(ap.strength));
                    }
                } else {
                    icon.set_from_icon_name("network-wired-symbolic");
                }
            }
        }
    }
    
    public class SoundButton : Box {
        private Image speaker;
        private Image mic;

        public SoundButton() {
            Object(orientation: Orientation.HORIZONTAL, spacing: 2);
            speaker = new Image.from_icon_name("audio-volume-muted-symbolic");
            mic = new Image.from_icon_name("microphone-sensitivity-high-symbolic");

            this.append(mic);
            this.append(speaker);

            var wps = WirePlumberService.get_global();
            if (wps == null) return;

            update_mic(wps.is_microphone_active());
            update_speaker(wps.get_default_sink());

            wps.microphone_active.connect(update_mic);
            wps.default_sink_changed.connect(update_speaker);
        }

        private void update_mic(bool active) {
            mic.visible = active;
        }

        private void update_speaker(WirePlumberServiceNode? sink) {
            if (sink == null) return;
            if (sink.mute) {
                speaker.set_from_icon_name("audio-volume-muted-symbolic");
            } else if (sink.volume < 0.25) {
                speaker.set_from_icon_name("audio-volume-low-symbolic");
            } else if (sink.volume < 0.5) {
                speaker.set_from_icon_name("audio-volume-medium-symbolic");
            } else {
                speaker.set_from_icon_name("audio-volume-high-symbolic");
            }
        }
    }

    public class PowerButton : Box {
        private Image icon;
        private Label label;
        private UpDevice power_dev;

        public PowerButton() {
            Object(orientation: Orientation.HORIZONTAL, spacing: 4);
            this.visible = false;
            
            var upower = UPowerService.get_global();
            if (upower == null) return;

            power_dev = upower.get_primary_device();
            if (power_dev == null || !power_dev.present) {
                this.visible = false;
                return;
            }

            icon = new Image.from_icon_name(UPowerService.device_map_icon_name(power_dev));
            label = new Label("");
            
            this.append(icon);
            this.append(label);

            update_battery_status();
            power_dev.notify["percentage"].connect(update_battery_status);
            power_dev.notify["state"].connect(update_battery_status);
            power_dev.notify["present"].connect(update_battery_status);
        }

        private void update_battery_status() {
            if (power_dev == null || !power_dev.present) {
                this.visible = false;
                return;
            }
            this.visible = true;
            double percent = power_dev.percentage;
            label.set_text("%.0f%%".printf(percent));
            icon.set_from_icon_name(UPowerService.device_map_icon_name(power_dev));
        }
    }
}
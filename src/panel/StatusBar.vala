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
                // Запоминаем монитор кликнутой панели, чтобы шторка открылась здесь же,
                // а не там, куда её положит компози́тор.
                if (panel != null) Panel.set_active_monitor(panel.get_monitor());
                var qs = WayShell.QS.Drawer.get_global();
                if (qs != null) qs.toggle();
            });
            button.tooltip_text = _("Quick settings");
            // Всё содержимое — шесть иконок без текста, так что без явной метки
            // скринридер видит только «кнопка».
            button.update_property(Gtk.AccessibleProperty.LABEL, _("Quick settings"), -1);

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

            // Камера последней в ряду: индикатор редкий, и его появление не должно
            // сдвигать привычные позиции остальных иконок.
            var webcam_btn = new WebcamButton();
            box.append(webcam_btn);
            buttons.add(webcam_btn);

            button.set_child(box);
            this.append(button);

            // Индикаторы появляются и исчезают по событиям сервисов, поэтому метку
            // пересчитываем на каждое изменение видимости любого из них.
            for (int i = 0; i < buttons.length; i++) {
                buttons.get(i).notify["visible"].connect(update_accessible_label);
            }
            update_accessible_label();
        }

        // Собирает метку из тех индикаторов, что сейчас на экране.
        private void update_accessible_label() {
            var parts = new GenericArray<string>();
            for (int i = 0; i < buttons.length; i++) {
                var w = buttons.get(i);
                if (!w.visible) continue;
                string? name = indicator_name(w);
                if (name != null) parts.add(name);
            }

            if (parts.length == 0) {
                button.update_property(Gtk.AccessibleProperty.LABEL, _("Quick settings"), -1);
                return;
            }

            var sb = new StringBuilder(_("Quick settings: "));
            for (int i = 0; i < parts.length; i++) {
                if (i > 0) sb.append(", ");
                sb.append(parts.get(i));
            }
            button.update_property(Gtk.AccessibleProperty.LABEL, sb.str, -1);
        }

        private string? indicator_name(Widget w) {
            if (w is IdleInhibitorButton) return _("idle inhibited");
            if (w is NightLightButton) return _("night light");
            if (w is VpnButton) return _("VPN");
            if (w is NetworkButton) return _("network");
            if (w is SoundButton) return _("sound");
            if (w is PowerButton) return _("battery");
            if (w is WebcamButton) return _("webcam in use");
            return null;
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

    public class WebcamButton : Box {
        private Image icon;

        public WebcamButton() {
            Object(orientation: Orientation.HORIZONTAL, spacing: 0);
            // Тот же индикатор-кружок, что у активного аудиопотока в MixerMenu.
            icon = new Image.from_icon_name("media-record-symbolic");
            icon.add_css_class("webcam-active");
            this.append(icon);

            this.visible = false;
            var cam = WebcamService.get_global();
            if (cam == null || !cam.has_device) return;

            this.tooltip_text = _("Webcam in use");
            this.visible = cam.in_use;
            cam.notify["in-use"].connect(() => {
                this.visible = cam.in_use;
            });
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
                this.tooltip_text = _("Network: disconnected");
            } else if (state == NM.State.CONNECTING) {
                icon.set_from_icon_name(has_wifi ? "network-wireless-acquiring-symbolic" : "network-wired-acquiring-symbolic");
                this.tooltip_text = _("Network: connecting");
            } else if (state == NM.State.CONNECTED_GLOBAL) {
                if (dev != null && dev.device_type == NM.DeviceType.WIFI) {
                    var wifi = (NM.DeviceWifi)dev;
                    var ap = wifi.get_active_access_point();
                    if (ap != null) {
                        icon.set_from_icon_name(NetworkManagerService.ap_strength_to_icon_name(ap.strength));
                        // Имя сети в подсказке: без него по силе сигнала не понять,
                        // это своя точка, телефон или чужая соседская.
                        this.tooltip_text = _("Wi-Fi: %s (%u%%)").printf(
                            NetworkManagerService.ap_to_ssid(ap), (uint)ap.strength);
                    }
                } else {
                    icon.set_from_icon_name("network-wired-symbolic");
                    string ip = NetworkManagerService.device_ip4(dev);
                    this.tooltip_text = (ip != "")
                        ? _("Wired: %s").printf(ip)
                        : _("Wired: connected");
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

            update_speaker(wps.get_default_sink());
            update_mic(wps.get_default_source());

            wps.default_sink_changed.connect(update_speaker);
            wps.default_sink_volume_changed.connect(update_speaker);
            wps.default_source_changed.connect(update_mic);
            // Занятость микрофона видна только по появлению/исчезновению узлов
            // Stream/Input/Audio, а об этом сообщает mixer_changed.
            wps.mixer_changed.connect(() => { update_mic(wps.get_default_source()); });
        }

        // Иконка микрофона — индикатор «кем-то используется», поэтому висит на
        // наличии потока записи, а не на mute. Раньше показывалась по !mute, то
        // есть горела постоянно, пока микрофон просто включён.
        private void update_mic(WirePlumberServiceNode? source) {
            var wps = WirePlumberService.get_global();
            bool in_use = (wps != null && wps.microphone_in_use());
            mic.visible = in_use;
            if (!in_use || source == null) return;

            mic.set_from_icon_name(
                WirePlumberService.map_source_vol_icon((float)source.volume, source.mute));
            mic.tooltip_text = source.mute
                ? _("Microphone in use, muted")
                : _("Microphone in use: %s").printf(
                    WirePlumberService.format_volume(source.volume, source.mute));
        }

        private void update_speaker(WirePlumberServiceNode? sink) {
            if (sink == null) return;
            speaker.set_from_icon_name(
                WirePlumberService.map_sink_vol_icon((float)sink.volume, sink.mute));
            speaker.tooltip_text = sink.mute
                ? _("Sound: muted")
                : _("Volume: %s").printf(
                    WirePlumberService.format_volume(sink.volume, sink.mute));
        }
    }

    public class PowerButton : Box {
        private Image icon;
        private Label label;
        private UpDevice power_dev;

        public PowerButton() {
            Object(orientation: Orientation.HORIZONTAL, spacing: 4);
            this.visible = false;

            icon = new Image.from_icon_name("battery-missing-symbolic");
            label = new Label("");

            this.append(icon);
            this.append(label);

            var upower = UPowerService.get_global();
            if (upower == null) return;

            // Виджеты строятся всегда, а видимость правит present. Раньше
            // конструктор выходил до append(), если батарею не нашли сразу, и
            // подписки не навешивались — UPower мог сообщить о батарее позже,
            // но обновлять было уже нечего.
            power_dev = upower.get_primary_device();
            if (power_dev == null) return;

            update_battery_status();
            // Одна подписка вместо пяти notify[...]: UpDevice сам эмитит changed()
            // один раз на пакет изменений.
            power_dev.changed.connect(update_battery_status);
        }

        private void update_battery_status() {
            if (power_dev == null || !power_dev.present) {
                this.visible = false;
                return;
            }
            this.visible = true;
            label.set_text(power_dev.get_percent_text());
            icon.set_from_icon_name(power_dev.get_icon_name());
            this.tooltip_text = _("Battery: %s").printf(power_dev.get_summary_text());
        }
    }
}
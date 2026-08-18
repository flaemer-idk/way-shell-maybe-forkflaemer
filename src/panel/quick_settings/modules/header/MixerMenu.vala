// Путь: src/panel/quick_settings/modules/header/MixerMenu.vala
using Gtk;
using GLib;
using WayShell.Services;

namespace WayShell.QS {

    public class MixerMenu : Box {
        private MenuWidget menu;
        private Box list;
        private HashTable<uint32, MixerMenuOption> options_map;

        public MixerMenu () {
            Object (orientation: Orientation.VERTICAL, spacing: 0);
            options_map = new HashTable<uint32, MixerMenuOption> (direct_hash, direct_equal);

            var provider = new CssProvider ();
            provider.load_from_data ("""
                .stream-active-dot {
                    color: #b19cd9;
                }
                .active-icon-activated {
                    color: #26a269;
                }
                .dim-label {
                    opacity: 0.75;
                    font-size: 13px;
                }
            """.data);
            StyleContext.add_provider_for_display (Gdk.Display.get_default (), provider, Gtk.STYLE_PROVIDER_PRIORITY_APPLICATION);

            menu = new MenuWidget ("Mixer", "audio-speakers-symbolic", true);
            menu.set_size_request (-1, 350);
            this.append (menu);

            list = new Box (Orientation.VERTICAL, 6);
            menu.options.append (list);

            refresh_mixer_list ();

            var wps = WirePlumberService.get_global ();
            if (wps != null) {
                wps.mixer_changed.connect (on_mixer_changed);
            }
        }

        private void on_mixer_changed () {
            GLib.Idle.add (() => {
                if (list == null || list.get_root () == null) {
                    return false;
                }

                var wps = WirePlumberService.get_global ();
                if (wps == null) return false;

                var streams = wps.get_audio_streams ();
                var sinks = wps.get_audio_sinks ();
                var sources = wps.get_audio_sources ();

                var current_nodes = new HashTable<uint32, WirePlumberServiceNode> (direct_hash, direct_equal);
                for (int i = 0; i < streams.length; i++) current_nodes.insert (streams[i].id, streams[i]);
                for (int i = 0; i < sinks.length; i++) current_nodes.insert (sinks[i].id, sinks[i]);
                for (int i = 0; i < sources.length; i++) current_nodes.insert (sources[i].id, sources[i]);

                var keys_to_remove = new GenericArray<uint32> ();
                foreach (var id in options_map.get_keys ()) {
                    if (!current_nodes.contains (id)) {
                        keys_to_remove.add (id);
                    }
                }
                for (int i = 0; i < keys_to_remove.length; i++) {
                    uint32 id = keys_to_remove[i];
                    var opt = options_map.lookup (id);
                    if (opt != null) {
                        list.remove (opt);
                        options_map.remove (id);
                    }
                }

                for (int i = 0; i < streams.length; i++) {
                    var stream = streams[i];
                    var opt = options_map.lookup (stream.id);
                    if (opt != null) {
                        opt.update_node_values (stream);
                    } else {
                        var new_opt = new MixerMenuOption (stream, true);
                        list.prepend (new_opt);
                        options_map.insert (stream.id, new_opt);
                    }
                }

                for (int i = 0; i < sinks.length; i++) {
                    var sink = sinks[i];
                    var opt = options_map.lookup (sink.id);
                    if (opt != null) {
                        opt.update_node_values (sink);
                    } else {
                        var new_opt = new MixerMenuOption (sink, false);
                        list.append (new_opt);
                        options_map.insert (sink.id, new_opt);
                    }
                }

                for (int i = 0; i < sources.length; i++) {
                    var source = sources[i];
                    var opt = options_map.lookup (source.id);
                    if (opt != null) {
                        opt.update_node_values (source);
                    } else {
                        var new_opt = new MixerMenuOption (source, false);
                        list.append (new_opt);
                        options_map.insert (source.id, new_opt);
                    }
                }

                return false;
            });
        }

        public void refresh_mixer_list () {
            Widget? child;
            while ((child = list.get_first_child ()) != null) {
                list.remove (child);
            }
            options_map.remove_all ();

            var wps = WirePlumberService.get_global ();
            if (wps == null) return;

            var streams = wps.get_audio_streams ();
            for (int i = 0; i < streams.length; i++) {
                var opt = new MixerMenuOption (streams[i], true);
                list.append (opt);
                options_map.insert (streams[i].id, opt);
            }

            var sinks = wps.get_audio_sinks ();
            for (int i = 0; i < sinks.length; i++) {
                var opt = new MixerMenuOption (sinks[i], false);
                list.append (opt);
                options_map.insert (sinks[i].id, opt);
            }

            var sources = wps.get_audio_sources ();
            for (int i = 0; i < sources.length; i++) {
                var opt = new MixerMenuOption (sources[i], false);
                list.append (opt);
                options_map.insert (sources[i].id, opt);
            }
        }
    }

    public class MixerMenuOption : Box {
        private WirePlumberServiceNode node;
        private Button button;
        private Label name_label;
        private Image icon;
        private Scale scale;
        private Button mute_btn;
        private Button? default_btn = null;
        private Image? default_dot = null;
        private Revealer revealer;
        private bool is_stream;
        private bool is_updating = false;

        public MixerMenuOption (WirePlumberServiceNode node, bool is_stream) {
            Object (orientation: Orientation.VERTICAL, spacing: 0);
            this.node = node;
            this.is_stream = is_stream;
            this.add_css_class ("quick-settings-menu-option-mixer");

            var main_row = new Box (Orientation.HORIZONTAL, 4);
            main_row.valign = Align.CENTER;

            button = new Button ();
            button.hexpand = true;
            button.valign = Align.CENTER;
            button.add_css_class ("flat");

            var btn_contents = new Box (Orientation.HORIZONTAL, 8);
            btn_contents.valign = Align.CENTER;

            icon = new Image.from_icon_name (get_node_icon ());
            icon.valign = Align.CENTER;
            
            name_label = new Label ("");
            update_name_label ();
            name_label.halign = Align.START;
            name_label.hexpand = true;
            name_label.xalign = 0.0f;
            name_label.valign = Align.CENTER;
            name_label.ellipsize = Pango.EllipsizeMode.END;

            btn_contents.append (icon);
            btn_contents.append (name_label);
            button.set_child (btn_contents);
            main_row.append (button);

            mute_btn = new Button ();
            mute_btn.add_css_class ("circular");
            mute_btn.add_css_class ("flat");
            mute_btn.valign = Align.CENTER;
            mute_btn.icon_name = get_mute_btn_icon ();
            mute_btn.clicked.connect (() => {
                var wps = WirePlumberService.get_global ();
                if (wps != null) {
                    bool next_mute = !this.node.mute;
                    wps.set_mute (this.node, next_mute);
                    
                    mute_btn.icon_name = get_mute_btn_icon ();
                    icon.set_from_icon_name (get_node_icon ());
                }
            });
            main_row.append (mute_btn);

            if (!is_stream) {
                default_btn = new Button ();
                default_btn.css_classes = {"circular", "flat"};
                default_btn.valign = Align.CENTER;
                default_btn.halign = Align.CENTER;

                default_dot = new Image.from_icon_name ("media-record-symbolic");
                default_dot.valign = Align.CENTER;
                default_dot.halign = Align.CENTER;
                default_btn.set_child (default_dot);

                update_default_dot_state ();

                default_btn.clicked.connect (() => {
                    var wps = WirePlumberService.get_global ();
                    if (wps != null) {
                        if (node.media_class.contains ("Source")) {
                            wps.set_default_source (node.id);
                        } else {
                            wps.set_default_sink (node.id);
                        }
                    }
                });
                main_row.append (default_btn);
            } else {
                default_btn = new Button ();
                default_btn.css_classes = {"circular", "flat"};
                default_btn.valign = Align.CENTER;
                default_btn.halign = Align.CENTER;
                default_btn.sensitive = false;

                default_dot = new Image.from_icon_name ("media-record-symbolic");
                default_dot.valign = Align.CENTER;
                default_dot.halign = Align.CENTER;
                default_dot.add_css_class ("stream-active-dot");
                
                default_btn.set_child (default_dot);
                default_btn.set_tooltip_text ("Active Audio Stream");
                main_row.append (default_btn);
            }

            this.append (main_row);

            revealer = new Revealer ();
            revealer.transition_type = RevealerTransitionType.SWING_DOWN;
            revealer.transition_duration = 350;

            var rev_content = new Box (Orientation.VERTICAL, 6);
            
            scale = new Scale.with_range (Orientation.HORIZONTAL, 0.0, 1.0, 0.05);
            scale.hexpand = true;
            scale.set_value (node.volume);
            scale.margin_start = 16;
            scale.margin_end = 16;
            scale.margin_top = 4;
            scale.margin_bottom = 4;
            
            scale.value_changed.connect (() => {
                if (is_updating) return;
                if (this.scale.get_root () == null) return;

                var wps = WirePlumberService.get_global ();
                if (wps != null) {
                    wps.set_volume (this.node, scale.get_value ());
                }
            });
            rev_content.append (scale);

            // --- 1. Для приложений: перенаправление потока ---
            if (is_stream) {
                var wps = WirePlumberService.get_global ();
                if (wps != null) {
                    var routing_box = new Box (Orientation.HORIZONTAL, 0);
                    routing_box.margin_start = 16;
                    routing_box.margin_end = 16;
                    routing_box.margin_bottom = 6;
                    
                    var targets = node.media_class.contains ("Output") ? wps.get_audio_sinks () : wps.get_audio_sources ();
                    
                    string[] target_names = new string[targets.length];
                    uint32[] target_ids = new uint32[targets.length];
                    string[] target_node_names = new string[targets.length];
                    string[] target_serials = new string[targets.length];

                    uint default_selected_idx = 0;
                    var def_sink = wps.get_default_sink ();

                    for (int i = 0; i < targets.length; i++) {
                        target_names[i] = targets[i].name;
                        target_ids[i] = targets[i].id;
                        target_node_names[i] = targets[i].node_name ?? targets[i].id.to_string ();
                        target_serials[i] = targets[i].serial ?? targets[i].id.to_string ();
                        
                        if (def_sink != null && targets[i].id == def_sink.id) {
                            default_selected_idx = (uint) i;
                        }
                    }

                    if (target_names.length > 0) {
                        var dropdown = new DropDown.from_strings (target_names);
                        dropdown.hexpand = true;
                        dropdown.set_selected (default_selected_idx);

                        dropdown.notify["selected"].connect (() => {
                            uint selected_idx = dropdown.get_selected ();
                            if (selected_idx < targets.length) {
                                wps.route_stream (this.node.id, target_ids[selected_idx], target_node_names[selected_idx], target_serials[selected_idx], this.node.pulse_id);
                            }
                        });
                        routing_box.append (dropdown);
                        rev_content.append (routing_box);
                    }
                }
            }

            // --- 2. Для Bluetooth-наушников/колонок: выбор кодека ---
            if (!is_stream && node.node_name != null && node.node_name.contains ("bluez")) {
                var wps = WirePlumberService.get_global ();
                if (wps != null) {
                    var codec_info = wps.get_bluetooth_codecs (node.node_name);
                    if (codec_info != null && codec_info.display_names.length > 0) {
                        var codec_box = new Box (Orientation.HORIZONTAL, 8);
                        codec_box.margin_start = 16;
                        codec_box.margin_end = 16;
                        codec_box.margin_bottom = 6;

                        var codec_icon = new Image.from_icon_name ("audio-headphones-symbolic");
                        codec_icon.valign = Align.CENTER;
                        codec_box.append (codec_icon);

                        var codec_dropdown = new DropDown.from_strings (codec_info.display_names);
                        codec_dropdown.hexpand = true;
                        codec_dropdown.set_selected (codec_info.active_index);

                        codec_dropdown.notify["selected"].connect (() => {
                            uint selected_idx = codec_dropdown.get_selected ();
                            if (selected_idx < codec_info.profile_names.length) {
                                wps.set_bluetooth_codec (codec_info.card_name, codec_info.profile_names[selected_idx]);
                            }
                        });
                        codec_box.append (codec_dropdown);
                        rev_content.append (codec_box);
                    }
                }
            }

            revealer.set_child (rev_content);
            this.append (revealer);

            button.clicked.connect (() => {
                revealer.set_reveal_child (!revealer.get_reveal_child ());
            });
        }

        public void update_node_values (WirePlumberServiceNode new_node) {
            this.node = new_node;

            if ((scale.get_state_flags () & Gtk.StateFlags.ACTIVE) != 0) {
                return;
            }

            is_updating = true;
            scale.set_value (node.volume);
            is_updating = false;

            mute_btn.icon_name = get_mute_btn_icon ();
            icon.set_from_icon_name (get_node_icon ());
            
            update_default_dot_state ();
            update_name_label ();
        }

        private bool is_default_device () {
            var wps = WirePlumberService.get_global ();
            if (wps == null) return false;

            if (node.media_class != null && node.media_class.contains ("Source")) {
                var def = wps.get_default_source ();
                return (def != null && def.id == node.id);
            } else if (!is_stream) {
                var def = wps.get_default_sink ();
                return (def != null && def.id == node.id);
            }
            return false;
        }

        private void update_default_dot_state () {
            if (default_dot == null || is_stream) return;

            if (is_default_device ()) {
                default_dot.add_css_class ("active-icon-activated");
                default_dot.set_tooltip_text ("Main active device");
            } else {
                default_dot.remove_css_class ("active-icon-activated");
                default_dot.set_tooltip_text ("Click to set as main device");
            }
        }

        private void update_name_label () {
            string display_name = node.name;
            if (is_stream) {
                display_name = "+ " + display_name;
            }
            name_label.set_text (display_name);
        }

        private string? get_app_icon_name (string app_name) {
            var apps = GLib.AppInfo.get_all ();
            string lower_app_name = app_name.ascii_down ();
            
            foreach (var app in apps) {
                string? id = app.get_id ();
                if (id != null) {
                    string lower_id = id.ascii_down ();
                    if (lower_id.contains (lower_app_name)) {
                        var icon = app.get_icon ();
                        if (icon != null) {
                            return icon.to_string ();
                        }
                    }
                }
            }
            return null;
        }

        private string get_node_icon () {
            if (node.mute) {
                if (node.media_class != null && node.media_class.contains ("Source")) {
                    return "microphone-sensitivity-muted-symbolic";
                } else {
                    return "audio-volume-muted-symbolic";
                }
            }

            if (node.media_class != null && node.media_class.contains ("Source")) {
                if (node.volume < 0.25) {
                    return "microphone-sensitivity-low-symbolic";
                } else if (node.volume < 0.5) {
                    return "microphone-sensitivity-medium-symbolic";
                } else {
                    return "microphone-sensitivity-high-symbolic";
                }
            } else if (is_stream) {
                string? app_icon = get_app_icon_name (node.name);
                if (app_icon != null && app_icon != "") {
                    return app_icon;
                }
                return "applications-multimedia-symbolic";
            } else {
                return WirePlumberService.map_sink_vol_icon ((float)node.volume, node.mute);
            }
        }

        private string get_mute_btn_icon () {
            if (node.media_class != null && node.media_class.contains ("Source")) {
                return node.mute ? "microphone-sensitivity-muted-symbolic" : "audio-input-microphone-symbolic";
            } else {
                return node.mute ? "audio-volume-muted-symbolic" : "audio-volume-high-symbolic";
            }
        }
    }
}
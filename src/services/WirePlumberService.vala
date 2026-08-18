// Путь: src/services/WirePlumberService.vala
using Gtk;
using Wp;

[CCode (cheader_filename = "wireplumber-0.5/wp/wp.h", cname = "wp_init")]
extern static void wp_init (int flags);

[CCode (cheader_filename = "wireplumber-0.5/wp/wp.h", cname = "wp_core_load_component")]
extern static void wp_core_load_component (GLib.Object core, string component, string type, GLib.Object? args, string provides, GLib.Object? cancellable, GLib.AsyncReadyCallback callback);

[CCode (cheader_filename = "way-shell-wp-helpers.h", cname = "way_shell_wp_set_volume")]
extern static void way_shell_wp_set_volume (GLib.Object mixer_api, uint32 id, double volume);

[CCode (cheader_filename = "way-shell-wp-helpers.h", cname = "way_shell_wp_set_mute")]
extern static void way_shell_wp_set_mute (GLib.Object mixer_api, uint32 id, bool mute);

namespace WayShell.Services {
    public class BluetoothCodecInfo : GLib.Object {
        public string card_name;
        public string active_profile;
        public string[] profile_names;
        public string[] display_names;
        public uint active_index;
    }

    public class WirePlumberServiceNode : GLib.Object {
        public uint32 id { get; set; }
        public string name { get; set; }
        public double volume { get; set; }
        public bool mute { get; set; }
        public string media_class { get; set; }
        public string? serial { get; set; }
        public string? node_name { get; set; }
        public string? pulse_id { get; set; }

        public WirePlumberServiceNode (uint32 id, string name, double volume, bool mute, string media_class, string? serial = null, string? node_name = null, string? pulse_id = null) {
            this.id = id;
            this.name = name;
            this.volume = volume;
            this.mute = mute;
            this.media_class = media_class;
            this.serial = serial;
            this.node_name = node_name;
            this.pulse_id = pulse_id;
        }
    }

    public class WirePlumberService : GLib.Object {
        private static WirePlumberService? global = null;

        private Wp.Core core;
        private Wp.ObjectManager om;
        
        private GLib.Object? def_nodes_api = null;
        private GLib.Object? mixer_api = null;

        public signal void default_sink_volume_changed (WirePlumberServiceNode sink);
        public signal void default_sink_changed (WirePlumberServiceNode? sink);
        public signal void microphone_active (bool active);
        public signal void mixer_changed ();

        public static WirePlumberService? get_global () {
            if (global == null) {
                global = new WirePlumberService ();
            }
            return global;
        }

        private WirePlumberService () {
            wp_init (0x3f);

            core = new Wp.Core (null, null, null);
            core.connect ();

            om = new Wp.ObjectManager ();
            om.add_interest (typeof (Wp.Node), null);
            om.add_interest (typeof (Wp.Device), null);
            om.add_interest (typeof (Wp.Metadata), null);

            om.objects_changed.connect (on_objects_changed);
            om.installed.connect (on_installed);

            core.install_object_manager (om);

            wp_core_load_component (core, "libwireplumber-module-default-nodes-api", "module", null, "default-nodes-api", null, (obj, res) => {
                wp_core_load_component (core, "libwireplumber-module-mixer-api", "module", null, "mixer-api", null, (obj2, res2) => {
                    load_plugins ();
                    update_state ();
                    debug ("WirePlumberService: API modules loaded successfully.");
                });
            });
        }

        private void load_plugins () {
            def_nodes_api = Wp.Plugin.find (core, "default-nodes-api");
            mixer_api = Wp.Plugin.find (core, "mixer-api");

            if (def_nodes_api == null) {
                warning ("WirePlumberService: default-nodes-api plugin not loaded!");
            }
            if (mixer_api == null) {
                warning ("WirePlumberService: mixer-api plugin not loaded!");
            } else {
                GLib.Signal.connect (mixer_api, "changed", (GLib.Callback) on_mixer_changed, this);
            }
        }

        private static void on_mixer_changed (GLib.Object plugin, uint32 id, WirePlumberService self) {
            self.update_state ();
        }

        private void on_installed () {
            debug ("WirePlumberService: ObjectManager installed.");
            update_state ();
        }

        private void on_objects_changed () {
            update_state ();
        }

        private void update_state () {
            if (def_nodes_api == null || mixer_api == null) {
                load_plugins ();
            }

            var sink = get_default_sink ();
            if (sink != null) {
                default_sink_changed (sink);
                default_sink_volume_changed (sink);
            } else {
                default_sink_changed (null);
            }

            microphone_active (is_microphone_active ());
            mixer_changed ();
        }

        public void route_stream (uint32 stream_id, uint32 target_id, string? target_node_name = null, string? target_serial = null, string? pulse_stream_id = null) {
            try {
                string serial_to_use = target_serial ?? target_id.to_string ();

                Process.spawn_command_line_async ("pw-metadata -n default %u target.object %s".printf (stream_id, serial_to_use));
                Process.spawn_command_line_async ("pw-metadata -n default %u target.node %s".printf (stream_id, serial_to_use));
                if (target_node_name != null && target_node_name != "") {
                    Process.spawn_command_line_async ("pw-metadata -n default %u target.node \"%s\"".printf (stream_id, target_node_name));
                }

                if (pulse_stream_id != null && pulse_stream_id != "") {
                    string sink_target = target_node_name ?? serial_to_use;
                    Process.spawn_command_line_async ("pactl move-sink-input %s %s".printf (pulse_stream_id, sink_target));
                }

                debug ("WirePlumberService: Routed stream %u to target %s", stream_id, serial_to_use);
                GLib.Timeout.add (150, () => {
                    mixer_changed ();
                    return false;
                });
            } catch (Error e) {
                warning ("WirePlumberService: Failed to route stream: %s", e.message);
            }
        }

        // --- Получение и установка Bluetooth кодеков ---
        public BluetoothCodecInfo? get_bluetooth_codecs (string node_name) {
            if (!node_name.contains ("bluez")) return null;

            try {
                string stdout_str;
                Process.spawn_command_line_sync ("pactl list cards", out stdout_str);

                string[] cards = stdout_str.split ("Card #");
                foreach (var card in cards) {
                    if (card.contains ("bluez_card")) {
                        string card_name = "";
                        string active_profile = "";
                        var prof_names = new GenericArray<string> ();
                        var disp_names = new GenericArray<string> ();

                        string[] lines = card.split ("\n");
                        bool in_profiles = false;

                        foreach (var line in lines) {
                            string trimmed = line.strip ();
                            if (trimmed.has_prefix ("Name: ")) {
                                card_name = trimmed.replace ("Name: ", "").strip ();
                            } else if (trimmed.has_prefix ("Active Profile: ")) {
                                active_profile = trimmed.replace ("Active Profile: ", "").strip ();
                            } else if (trimmed == "Profiles:") {
                                in_profiles = true;
                            } else if (in_profiles) {
                                if (trimmed.has_prefix ("Active Profile:") || trimmed.has_prefix ("Ports:")) {
                                    in_profiles = false;
                                } else if (trimmed.contains (":") && trimmed.contains ("available: yes")) {
                                    string prof_key = trimmed.split (":")[0].strip ();
                                    if (prof_key.has_prefix ("a2dp-sink-") || prof_key.has_prefix ("headset-head-unit")) {
                                        prof_names.add (prof_key);
                                        disp_names.add (format_codec_name (prof_key));
                                    }
                                }
                            }
                        }

                        if (prof_names.length > 0 && card_name != "") {
                            var info = new BluetoothCodecInfo ();
                            info.card_name = card_name;
                            info.active_profile = active_profile;
                            info.profile_names = new string[prof_names.length];
                            info.display_names = new string[disp_names.length];
                            info.active_index = 0;

                            for (int i = 0; i < prof_names.length; i++) {
                                info.profile_names[i] = prof_names[i];
                                info.display_names[i] = disp_names[i];
                                if (prof_names[i] == active_profile) {
                                    info.active_index = (uint) i;
                                }
                            }
                            return info;
                        }
                    }
                }
            } catch (Error e) {
                warning ("Failed to query bluetooth codecs: %s", e.message);
            }
            return null;
        }

        private string format_codec_name (string profile_key) {
            if (profile_key == "a2dp-sink-ldac") return "LDAC (High-Res)";
            if (profile_key == "a2dp-sink-aptx_hd") return "aptX HD";
            if (profile_key == "a2dp-sink-aptx") return "aptX";
            if (profile_key == "a2dp-sink-aac") return "AAC";
            if (profile_key == "a2dp-sink-sbc_xq") return "SBC-XQ (HQ)";
            if (profile_key == "a2dp-sink-sbc") return "SBC (Standard)";
            if (profile_key == "a2dp-sink-opus") return "Opus";
            if (profile_key == "a2dp-sink-lc3") return "LC3";
            if (profile_key.contains ("headset")) return "Headset / Mic (HFP)";
            return profile_key.replace ("a2dp-sink-", "").up ();
        }

        public void set_bluetooth_codec (string card_name, string profile_name) {
            try {
                Process.spawn_command_line_async ("pactl set-card-profile %s %s".printf (card_name, profile_name));
                debug ("WirePlumberService: Set Bluetooth codec for %s to %s", card_name, profile_name);
                GLib.Timeout.add (250, () => {
                    mixer_changed ();
                    return false;
                });
            } catch (Error e) {
                warning ("Failed to set bluetooth codec: %s", e.message);
            }
        }

        private string? get_node_name_by_id (uint32 id) {
            var iter = om.new_iterator ();
            GLib.Value val = GLib.Value (typeof (GLib.Object));
            while (iter.next (ref val)) {
                var obj = val.get_object ();
                if (obj is Wp.Node) {
                    var wp_node = (Wp.Node) obj;
                    if (wp_node.get_bound_id () == id) {
                        string? node_name = wp_node.get_pw_property ("node.name");
                        val.unset ();
                        return node_name;
                    }
                }
                val.unset ();
            }
            return null;
        }

        public WirePlumberServiceNode? get_default_sink () {
            if (def_nodes_api == null || mixer_api == null) return null;

            uint32 id = 0;
            GLib.Signal.emit_by_name (def_nodes_api, "get-default-node", "Audio/Sink", out id);

            if (id == 0 || id == uint32.MAX) {
                return null;
            }

            double vol = 0.0;
            bool mute = false;

            GLib.Variant? variant = null;
            GLib.Signal.emit_by_name (mixer_api, "get-volume", id, out variant);

            if (variant != null) {
                var v_vol = variant.lookup_value ("volume", GLib.VariantType.DOUBLE);
                if (v_vol != null) {
                    vol = Math.cbrt (v_vol.get_double ());
                }

                var v_mute = variant.lookup_value ("mute", GLib.VariantType.BOOLEAN);
                if (v_mute != null) mute = v_mute.get_boolean ();
            }

            string? node_name = get_node_name_by_id (id);
            return new WirePlumberServiceNode (id, "Default Sink", vol, mute, "Audio/Sink", null, node_name);
        }

        public WirePlumberServiceNode? get_default_source () {
            if (def_nodes_api == null || mixer_api == null) return null;

            uint32 id = 0;
            GLib.Signal.emit_by_name (def_nodes_api, "get-default-node", "Audio/Source", out id);

            if (id == 0 || id == uint32.MAX) {
                return null;
            }

            double vol = 0.0;
            bool mute = false;

            GLib.Variant? variant = null;
            GLib.Signal.emit_by_name (mixer_api, "get-volume", id, out variant);

            if (variant != null) {
                var v_vol = variant.lookup_value ("volume", GLib.VariantType.DOUBLE);
                if (v_vol != null) {
                    vol = Math.cbrt (v_vol.get_double ());
                }

                var v_mute = variant.lookup_value ("mute", GLib.VariantType.BOOLEAN);
                if (v_mute != null) mute = v_mute.get_boolean ();
            }

            string? node_name = get_node_name_by_id (id);
            return new WirePlumberServiceNode (id, "Default Source", vol, mute, "Audio/Source", null, node_name);
        }

        public void set_default_sink (uint32 id) {
            try {
                Process.spawn_command_line_async ("wpctl set-default %u".printf (id));
                debug ("WirePlumberService: Set default sink via wpctl to ID %u", id);
                GLib.Timeout.add (100, () => {
                    mixer_changed ();
                    return false;
                });
            } catch (Error e) {
                warning ("WirePlumberService: Failed to set default sink: %s", e.message);
            }
        }

        public void set_default_source (uint32 id) {
            try {
                Process.spawn_command_line_async ("wpctl set-default %u".printf (id));
                debug ("WirePlumberService: Set default source via wpctl to ID %u", id);
                GLib.Timeout.add (100, () => {
                    mixer_changed ();
                    return false;
                });
            } catch (Error e) {
                warning ("WirePlumberService: Failed to set default source: %s", e.message);
            }
        }

        public bool is_microphone_active () {
            if (def_nodes_api == null || mixer_api == null) return false;

            uint32 id = 0;
            GLib.Signal.emit_by_name (def_nodes_api, "get-default-node", "Audio/Source", out id);

            if (id == 0 || id == uint32.MAX) {
                return false;
            }

            bool mute = false;
            GLib.Variant? variant = null;
            GLib.Signal.emit_by_name (mixer_api, "get-volume", id, out variant);

            if (variant != null) {
                var v_mute = variant.lookup_value ("mute", GLib.VariantType.BOOLEAN);
                if (v_mute != null) mute = v_mute.get_boolean ();
            }

            return !mute;
        }

        public void volume_up (WirePlumberServiceNode sink) {
            double new_vol = double.min (sink.volume + 0.05, 1.0);
            set_volume (sink, new_vol);
        }

        public void volume_down (WirePlumberServiceNode sink) {
            double new_vol = double.max (sink.volume - 0.05, 0.0);
            set_volume (sink, new_vol);
        }

        public void set_mute (WirePlumberServiceNode sink, bool mute) {
            if (mixer_api == null) return;
            way_shell_wp_set_mute (mixer_api, sink.id, mute);
            sink.mute = mute;
            default_sink_volume_changed (sink);
        }

        public void set_volume (WirePlumberServiceNode node, double vol) {
            if (mixer_api == null) return;
            double vol_linear = Math.pow (vol, 3);
            way_shell_wp_set_volume (mixer_api, node.id, vol_linear);
            node.volume = vol;
            default_sink_volume_changed (node);
        }

        public GenericArray<WirePlumberServiceNode> get_audio_sinks () {
            var list = new GenericArray<WirePlumberServiceNode> ();
            if (mixer_api == null) return list;

            var iter = om.new_iterator ();
            GLib.Value val = GLib.Value (typeof (GLib.Object));
            while (iter.next (ref val)) {
                var obj = val.get_object ();
                if (obj is Wp.Node) {
                    var node = (Wp.Node) obj;
                    string? media_class = node.get_pw_property ("media.class");
                    if (media_class != null && media_class.contains ("Sink")) {
                        double vol = 0.0;
                        bool mute = false;
                        uint32 id = node.get_bound_id ();
                        
                        GLib.Variant? variant = null;
                        GLib.Signal.emit_by_name (mixer_api, "get-volume", id, out variant);

                        if (variant != null) {
                            var v_vol = variant.lookup_value ("volume", GLib.VariantType.DOUBLE);
                            if (v_vol != null) {
                                vol = Math.cbrt (v_vol.get_double ());
                            }

                            var v_mute = variant.lookup_value ("mute", GLib.VariantType.BOOLEAN);
                            if (v_mute != null) mute = v_mute.get_boolean ();
                        }

                        string name = node.get_pw_property ("node.nick") ??
                                      node.get_pw_property ("alsa.mixer_name") ??
                                      node.get_pw_property ("node.description") ?? 
                                      node.get_pw_property ("node.name") ?? "Audio Output";
                        string? serial = node.get_pw_property ("object.serial");
                        string? node_name = node.get_pw_property ("node.name");
                        list.add (new WirePlumberServiceNode (id, name, vol, mute, media_class, serial, node_name));
                    }
                }
                val.unset ();
            }
            return list;
        }

        public GenericArray<WirePlumberServiceNode> get_audio_sources () {
            var list = new GenericArray<WirePlumberServiceNode> ();
            if (mixer_api == null) return list;

            var iter = om.new_iterator ();
            GLib.Value val = GLib.Value (typeof (GLib.Object));
            while (iter.next (ref val)) {
                var obj = val.get_object ();
                if (obj is Wp.Node) {
                    var node = (Wp.Node) obj;
                    string? media_class = node.get_pw_property ("media.class");
                    if (media_class != null && media_class.contains ("Source")) {
                        double vol = 0.0;
                        bool mute = false;
                        uint32 id = node.get_bound_id ();
                        
                        GLib.Variant? variant = null;
                        GLib.Signal.emit_by_name (mixer_api, "get-volume", id, out variant);

                        if (variant != null) {
                            var v_vol = variant.lookup_value ("volume", GLib.VariantType.DOUBLE);
                            if (v_vol != null) {
                                vol = Math.cbrt (v_vol.get_double ());
                            }

                            var v_mute = variant.lookup_value ("mute", GLib.VariantType.BOOLEAN);
                            if (v_mute != null) mute = v_mute.get_boolean ();
                        }

                        string name = node.get_pw_property ("node.nick") ??
                                      node.get_pw_property ("alsa.mixer_name") ??
                                      node.get_pw_property ("node.description") ?? 
                                      node.get_pw_property ("node.name") ?? "Audio Input";
                        string? serial = node.get_pw_property ("object.serial");
                        string? node_name = node.get_pw_property ("node.name");
                        list.add (new WirePlumberServiceNode (id, name, vol, mute, media_class, serial, node_name));
                    }
                }
                val.unset ();
            }
            return list;
        }

        public GenericArray<WirePlumberServiceNode> get_audio_streams () {
            var list = new GenericArray<WirePlumberServiceNode> ();
            if (mixer_api == null) return list;

            var iter = om.new_iterator ();
            GLib.Value val = GLib.Value (typeof (GLib.Object));
            while (iter.next (ref val)) {
                var obj = val.get_object ();
                if (obj is Wp.Node) {
                    var node = (Wp.Node) obj;
                    string? media_class = node.get_pw_property ("media.class");
                    if (media_class != null && media_class.contains ("Stream")) {
                        double vol = 0.0;
                        bool mute = false;
                        uint32 id = node.get_bound_id ();
                        
                        GLib.Variant? variant = null;
                        GLib.Signal.emit_by_name (mixer_api, "get-volume", id, out variant);

                        if (variant != null) {
                            var v_vol = variant.lookup_value ("volume", GLib.VariantType.DOUBLE);
                            if (v_vol != null) {
                                vol = Math.cbrt (v_vol.get_double ());
                            }

                            var v_mute = variant.lookup_value ("mute", GLib.VariantType.BOOLEAN);
                            if (v_mute != null) mute = v_mute.get_boolean ();
                        }

                        string name = node.get_pw_property ("application.name") ??
                                      node.get_pw_property ("node.name") ?? "Application Stream";
                        string? serial = node.get_pw_property ("object.serial");
                        string? node_name = node.get_pw_property ("node.name");
                        string? pulse_id = node.get_pw_property ("pulse.server.sink-input.id");

                        list.add (new WirePlumberServiceNode (id, name, vol, mute, media_class, serial, node_name, pulse_id));
                    }
                }
                val.unset ();
            }
            return list;
        }

        public static string map_sink_vol_icon (float volume, bool mute) {
            if (mute || volume < 0.01) {
                return "audio-volume-muted-symbolic";
            }
            if (volume < 0.3) {
                return "audio-volume-low-symbolic";
            }
            if (volume < 0.7) {
                return "audio-volume-medium-symbolic";
            }
            return "audio-volume-high-symbolic";
        }
    }
}
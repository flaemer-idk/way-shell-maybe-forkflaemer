// Путь: src/services/WirePlumberService.vala
using Gtk;
using Wp;

// Переносим только wp_init (он нужен для инициализации wireplumber-0.5)
[CCode (cheader_filename = "wireplumber-0.5/wp/wp.h", cname = "wp_init")]
extern static void wp_init (int flags);

// Внешнее объявление функции загрузки модулей (чтобы не изменять wireplumber-0.5.vapi)
[CCode (cheader_filename = "wireplumber-0.5/wp/wp.h", cname = "wp_core_load_component")]
extern static void wp_core_load_component (GLib.Object core, string component, string type, GLib.Object? args, string provides, GLib.Object? cancellable, GLib.AsyncReadyCallback callback);

// Нативные Си-функции (ключевое слово static гарантирует Си-выравнивание без неявного self)
[CCode (cheader_filename = "way-shell-wp-helpers.h", cname = "way_shell_wp_set_volume")]
extern static void way_shell_wp_set_volume (GLib.Object mixer_api, uint32 id, double volume);

[CCode (cheader_filename = "way-shell-wp-helpers.h", cname = "way_shell_wp_set_mute")]
extern static void way_shell_wp_set_mute (GLib.Object mixer_api, uint32 id, bool mute);

namespace WayShell.Services {
    public class WirePlumberServiceNode : GLib.Object {
        public uint32 id { get; set; }
        public string name { get; set; }
        public double volume { get; set; }
        public bool mute { get; set; }
        public string media_class { get; set; } // Обозначает класс медиа (Sink/Source/Stream)
        public string? serial { get; set; }
        public string? node_name { get; set; }

        public WirePlumberServiceNode (uint32 id, string name, double volume, bool mute, string media_class, string? serial = null, string? node_name = null) {
            this.id = id;
            this.name = name;
            this.volume = volume;
            this.mute = mute;
            this.media_class = media_class;
            this.serial = serial;
            this.node_name = node_name;
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

            // Асинхронно загружаем необходимые модули WirePlumber
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

        private Wp.Metadata? get_default_metadata () {
            var iter = om.new_iterator ();
            GLib.Value val = GLib.Value (typeof (GLib.Object));
            while (iter.next (ref val)) {
                var obj = val.get_object ();
                if (obj is Wp.Metadata) {
                    string? name = null;
                    obj.get ("metadata-name", out name);
                    if (name == "default") {
                        var metadata = (Wp.Metadata) obj;
                        val.unset ();
                        return metadata;
                    }
                }
                val.unset ();
            }
            return null;
        }

        // Перенаправление потока конкретного приложения (Stream) на выбранный физический выход/вход
        public void route_stream (uint32 stream_id, string target_node_name) {
            try {
                // Используем утилиту pw-metadata для гарантированного перенаправления потока
                string cmd = "pw-metadata -n default %u target.object '{\"name\": \"%s\"}' Spa:String:JSON".printf (stream_id, target_node_name);
                Process.spawn_command_line_async (cmd);
                debug ("WirePlumberService: Routed stream %u to target %s", stream_id, target_node_name);
                GLib.Timeout.add (150, () => {
                    mixer_changed ();
                    return false;
                });
            } catch (Error e) {
                warning ("WirePlumberService: Failed to route stream natively: %s", e.message);
            }
        }
        
        

// Вспомогательный метод для поиска имени ноды по её ID в ObjectManager
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

        // Обновленный метод получения дефолтного выхода (теперь возвращает и уникальное имя node_name)
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

        // Возвращает дефолтный вход
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

// Установка дефолтного выхода через вызов системной утилиты wpctl
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

        // Установка дефолтного входа (микрофона) через вызов системной утилиты wpctl
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
            // Безопасный Си-вызов без неявного self
            way_shell_wp_set_mute (mixer_api, sink.id, mute);
            sink.mute = mute;
            default_sink_volume_changed (sink);
        }

        public void set_volume (WirePlumberServiceNode node, double vol) {
            if (mixer_api == null) return;
            double vol_linear = Math.pow (vol, 3);
            // Безопасный Си-вызов без неявного self
            way_shell_wp_set_volume (mixer_api, node.id, vol_linear);
            node.volume = vol;
            default_sink_volume_changed (node);
        }

        // Возвращает физические выходы (sinks) с именами аудиочипов (ALC3227)
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

                        // Приоритетно читаем физический чип alsa.mixer_name / node.nick
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

        // Возвращает физические входы (sources)
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

        // Возвращает играющие приложения (Streams, e.g. G4Music)
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
                        list.add (new WirePlumberServiceNode (id, name, vol, mute, media_class, serial, node_name));
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
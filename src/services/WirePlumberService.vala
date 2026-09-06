// Путь: src/services/WirePlumberService.vala
using Gtk;
using Wp;

[CCode (cheader_filename = "wireplumber-0.5/wp/wp.h", cname = "wp_init")]
extern static void wp_init (int flags);

[CCode (cheader_filename = "way-shell-wp-helpers.h", cname = "way_shell_wp_set_volume")]
extern static void way_shell_wp_set_volume (GLib.Object mixer_api, uint32 id, double volume);

[CCode (cheader_filename = "way-shell-wp-helpers.h", cname = "way_shell_wp_set_mute")]
extern static void way_shell_wp_set_mute (GLib.Object mixer_api, uint32 id, bool mute);

// Профили звуковой карты через SPA-поды. На стороне C потому, что
// wp_spa_pod_get_property отдаёт вложенный под через out-параметр, а обход
// объекта идёт итератором подов — в Vala это не выражается без горы биндингов.
[CCode (cheader_filename = "way-shell-wp-helpers.h", cname = "way_shell_wp_get_card_profiles")]
extern static GLib.Variant? way_shell_wp_get_card_profiles (GLib.Object om, string node_name);

[CCode (cheader_filename = "way-shell-wp-helpers.h", cname = "way_shell_wp_set_card_profile")]
extern static bool way_shell_wp_set_card_profile (GLib.Object om, string card_name, int32 index);

namespace WayShell.Services {
    public class BluetoothCodecInfo : GLib.Object {
        public string card_name;
        public string active_profile;
        public string[] profile_names;
        public string[] display_names;
        // Индексы профилей в SPA (не совпадают с позицией в массиве: незвучащие
        // профили отфильтрованы).
        public int32[] profile_indices;
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
        // Раньше вместо этого был microphone_active(bool) = !mute. Слушатели
        // прятали по нему сам регулятор микрофона, и после mute вернуть звук
        // было нечем. Теперь отдаём узел целиком, а решение показывать или нет
        // остаётся за виджетом.
        public signal void default_source_changed (WirePlumberServiceNode? source);
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
            // Кэш данных метаданных нужен, чтобы читать из них (find). BOUND
            // указывается явно: request_object_features задаёт набор целиком, а без
            // BOUND объекты вообще не попадают в ObjectManager.
            om.request_object_features (typeof (Wp.Metadata),
                                       Wp.PROXY_FEATURE_BOUND | Wp.METADATA_FEATURE_DATA);
            // Картам нужен PARAM_PROFILE, иначе enum_params_sync("EnumProfile") пустой
            // и список Bluetooth-кодеков не собирается.
            om.request_object_features (typeof (Wp.Device),
                                       Wp.PROXY_FEATURE_BOUND
                                       | Wp.PIPEWIRE_OBJECT_FEATURE_INFO
                                       | Wp.PIPEWIRE_OBJECT_FEATURE_PARAM_PROFILE);

            om.objects_changed.connect (on_objects_changed);
            om.installed.connect (on_installed);

            core.install_object_manager (om);

            load_api_modules.begin ();
        }

        private async void load_api_modules () {
            try {
                yield core.load_component ("libwireplumber-module-default-nodes-api", "module",
                                           null, "default-nodes-api");
                yield core.load_component ("libwireplumber-module-mixer-api", "module",
                                           null, "mixer-api");
            } catch (Error e) {
                // Раньше ошибка загрузки модуля терялась: колбек не вызывал
                // wp_core_load_component_finish, и звук просто молча не работал.
                warning ("WirePlumberService: модули API не загрузились: %s", e.message);
                return;
            }

            load_plugins ();
            update_state ();
            debug ("WirePlumberService: API modules loaded successfully.");
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

            // default-nodes-api сам сообщает о смене устройства по умолчанию (сигнал
            // changed без аргументов). Без этого смена выхода замечалась только
            // когда заодно приходил mixer::changed.
            if (def_nodes_api != null) {
                GLib.Signal.connect (def_nodes_api, "changed",
                                     (GLib.Callback) on_default_nodes_changed, this);
            }
        }

        private static void on_default_nodes_changed (GLib.Object plugin, WirePlumberService self) {
            self.update_state ();
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

            default_source_changed (get_default_source ());
            mixer_changed ();
        }

        // Метаданные "default" — туда пишется привязка потока к выходу.
        private Wp.Metadata? find_default_metadata () {
            var iter = om.new_iterator ();
            GLib.Value val = GLib.Value (typeof (GLib.Object));
            while (iter.next (ref val)) {
                var obj = val.get_object ();
                if (obj is Wp.Metadata) {
                    var md = (Wp.Metadata) obj;
                    var props = md.get_global_properties ();
                    if (props != null && props.get ("metadata.name") == "default") {
                        val.unset ();
                        return md;
                    }
                }
                val.unset ();
            }
            return null;
        }

        // Раньше здесь было три спавна pw-metadata и один pactl, причём node.name
        // интерполировался в шелл-строку. Теперь одна запись в метаданные
        // через API, как это делает сам pw-metadata.
        public void route_stream (uint32 stream_id, uint32 target_id, string? target_node_name = null, string? target_serial = null, string? pulse_stream_id = null) {
            var md = find_default_metadata ();
            if (md == null) {
                warning ("WirePlumberService: метаданные \"default\" не найдены, поток не перенаправлен");
                return;
            }

            // PipeWire принимает либо имя узла (target.object с типом Spa:String),
            // либо serial. Имя надёжнее: id меняется при пересоздании узла.
            string target = (target_node_name != null && target_node_name != "")
                ? target_node_name
                : (target_serial ?? target_id.to_string ());

            md.set (stream_id, "target.object", "Spa:String", target);

            debug ("WirePlumberService: поток %u → %s", stream_id, target);
            GLib.Timeout.add (150, () => {
                mixer_changed ();
                return false;
            });
        }

        // --- Получение и установка Bluetooth кодеков ---
        //
        // Кодек у BlueZ — это профиль карты. Раньше список брался разбором
        // текстового вывода `pactl list cards` через spawn_command_line_sync,
        // блокирующий главный поток. Теперь — из самого WirePlumber.
        public BluetoothCodecInfo? get_bluetooth_codecs (string node_name) {
            if (!node_name.contains ("bluez")) return null;

            var reply = way_shell_wp_get_card_profiles (om, node_name);
            if (reply == null) return null;

            string card_name = reply.get_child_value (0).get_string ();
            int32 active = reply.get_child_value (1).get_int32 ();
            var profiles = reply.get_child_value (2);

            var prof_names = new GenericArray<string> ();
            var disp_names = new GenericArray<string> ();
            var indices = new GenericArray<int32> ();

            uint n = (uint) profiles.n_children ();
            for (uint i = 0; i < n; i++) {
                var entry = profiles.get_child_value (i);
                int32 idx = entry.get_child_value (0).get_int32 ();
                string name = entry.get_child_value (1).get_string ();

                // В списке карты есть и off, и дублирующие профили без кодека —
                // пользователю нужны только звучащие.
                if (!name.has_prefix ("a2dp-sink") && !name.has_prefix ("headset-head-unit")) {
                    continue;
                }

                indices.add (idx);
                prof_names.add (name);
                disp_names.add (format_codec_name (name));
            }

            if (prof_names.length == 0) return null;

            var info = new BluetoothCodecInfo ();
            info.card_name = card_name;
            info.profile_names = new string[prof_names.length];
            info.display_names = new string[disp_names.length];
            info.profile_indices = new int32[indices.length];
            info.active_index = 0;
            info.active_profile = "";

            for (int i = 0; i < prof_names.length; i++) {
                info.profile_names[i] = prof_names[i];
                info.display_names[i] = disp_names[i];
                info.profile_indices[i] = indices[i];
                if (indices[i] == active) {
                    info.active_index = (uint) i;
                    info.active_profile = prof_names[i];
                }
            }

            return info;
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

        public void set_bluetooth_codec (string card_name, int32 profile_index) {
            if (!way_shell_wp_set_card_profile (om, card_name, profile_index)) {
                warning ("WirePlumberService: профиль %d для %s не выставился",
                         profile_index, card_name);
                return;
            }
            debug ("WirePlumberService: профиль карты %s = %d", card_name, profile_index);
            GLib.Timeout.add (250, () => {
                mixer_changed ();
                return false;
            });
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
            set_default_node (id, "Audio/Sink");
        }

        public void set_default_source (uint32 id) {
            set_default_node (id, "Audio/Source");
        }

        // Через default-nodes-api, а не спавном `wpctl set-default`: плагин ждёт
        // имя узла, поэтому id сначала разыменовывается в node.name.
        private void set_default_node (uint32 id, string media_class) {
            if (def_nodes_api == null) {
                warning ("WirePlumberService: default-nodes-api не загружен, устройство по умолчанию не выбрать");
                return;
            }

            string? node_name = get_node_name_by_id (id);
            if (node_name == null) {
                warning ("WirePlumberService: у узла %u нет node.name", id);
                return;
            }

            bool ok = false;
            GLib.Signal.emit_by_name (def_nodes_api, "set-default-configured-node-name",
                                      media_class, node_name, out ok);
            if (!ok) {
                warning ("WirePlumberService: %s по умолчанию не выставился (%s)",
                         media_class, node_name);
                return;
            }

            debug ("WirePlumberService: %s по умолчанию = %s", media_class, node_name);
            // Отдельный таймер не нужен: плагин сам пришлёт changed,
            // а на нём висит update_state().
        }

        // Кто-то реально пишет звук: у приложения-записывающего есть узел
        // media.class = Stream/Input/Audio. Именно это значит «микрофон занят».
        //
        // Заменило is_microphone_active(), который возвращал !mute. На том имени
        // строилась и видимость слайдера микрофона в шторке (кнопка mute
        // прятала сама себя), и иконка в панели (горела всегда, пока микрофон
        // просто включён).
        public bool microphone_in_use () {
            var iter = om.new_iterator ();
            GLib.Value val = GLib.Value (typeof (GLib.Object));
            bool found = false;
            while (iter.next (ref val)) {
                var obj = val.get_object ();
                if (obj is Wp.Node) {
                    string? media_class = ((Wp.Node) obj).get_pw_property ("media.class");
                    if (media_class == "Stream/Input/Audio") {
                        found = true;
                        val.unset ();
                        break;
                    }
                }
                val.unset ();
            }
            return found;
        }

        public void volume_up (WirePlumberServiceNode sink) {
            double new_vol = double.min (sink.volume + 0.05, 1.0);
            set_volume (sink, new_vol);
        }

        public void volume_down (WirePlumberServiceNode sink) {
            double new_vol = double.max (sink.volume - 0.05, 0.0);
            set_volume (sink, new_vol);
        }

        public void set_mute (WirePlumberServiceNode node, bool mute) {
            if (mixer_api == null) return;
            way_shell_wp_set_mute (mixer_api, node.id, mute);
            node.mute = mute;
            notify_node_changed (node);
        }

        public void set_volume (WirePlumberServiceNode node, double vol) {
            if (mixer_api == null) return;
            double vol_linear = Math.pow (vol, 3);
            way_shell_wp_set_volume (mixer_api, node.id, vol_linear);
            node.volume = vol;
            notify_node_changed (node);
        }

        // Сигнал по классу узла. Раньше оба сеттера всегда эмитили
        // default_sink_volume_changed — и приглушение микрофона вызывало OSD
        // громкости с иконкой колонки и чужим значением. mixer_changed здесь
        // не нужен: mixer-api сам пришлёт changed и разбудит update_state().
        private void notify_node_changed (WirePlumberServiceNode node) {
            if (node.media_class.contains ("Source")) {
                default_source_changed (node);
            } else {
                default_sink_volume_changed (node);
            }
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

        // Была своя копия в Scales и своя в StatusBar, с разными порогами.
        public static string map_source_vol_icon (float volume, bool mute) {
            if (mute || volume < 0.01) {
                return "microphone-sensitivity-muted-symbolic";
            }
            if (volume < 0.3) {
                return "microphone-sensitivity-low-symbolic";
            }
            if (volume < 0.7) {
                return "microphone-sensitivity-medium-symbolic";
            }
            return "microphone-sensitivity-high-symbolic";
        }

        // Проценты для подсказок. Слайдеры и иконки живут в разных файлах,
        // а формат один: «80%» или «muted».
        public static string format_volume (double volume, bool mute) {
            if (mute) return _("muted");
            return "%d%%".printf ((int) Math.round (volume * 100.0));
        }
    }
}
using GLib;

namespace WayShell.Services {
    // Плеер MPRIS: одна шина, один сервис на процесс.
    //
    // Раньше данные о треке брались из stdout `playerctl --follow`, причём
    // Panel запускала его в конструкторе — то есть по процессу на каждый
    // монитор, и каждый клик/скролл форкал ещё один playerctl. При падении
    // way-shell дочерние процессы осиротевали и висели в системе часами:
    // на машине владельца нашлось восемь таких, суммарно 69 МБ.
    //
    // Внешне для пользователя ничего не меняется: та же кнопка в центре панели,
    // клик = play/pause, колесо = переключение трека.
    public class MediaPlayerService : GLib.Object {
        private const string MPRIS_PREFIX = "org.mpris.MediaPlayer2.";
        private const string MPRIS_PATH = "/org/mpris/MediaPlayer2";
        private const string PLAYER_IFACE = "org.mpris.MediaPlayer2.Player";
        private const string PROPS_IFACE = "org.freedesktop.DBus.Properties";
        private const string DBUS_NAME = "org.freedesktop.DBus";
        private const string DBUS_PATH = "/org/freedesktop/DBus";

        private static MediaPlayerService? global = null;

        private DBusConnection? conn = null;
        private uint noc_sub = 0;

        // bus name → состояние плеера. Плееров может быть несколько
        // одновременно (браузер + музыкальный клиент), поэтому держим все.
        private HashTable<string, PlayerState> players;
        private string? active_name = null;
        // Кто играл последним. Без этого при двух плеерах на паузе
        // активным становился первый из обхода HashTable, а его порядок
        // не определён: пауза в браузере показывала трек из музыкального
        // клиента, а команды уходили туда же, а не в браузер.
        private string? last_active_name = null;

        // Что показывать в панели. available == false означает «плеера нет».
        public string title { get; private set; default = ""; }
        public string artist { get; private set; default = ""; }
        public bool playing { get; private set; default = false; }
        public bool available { get; private set; default = false; }

        // Что активный плеер умеет. Браузер на видео отдаёт
        // CanGoNext = false, и дёргать Next у него бессмысленно.
        public bool can_go_next { get; private set; default = false; }
        public bool can_go_previous { get; private set; default = false; }

        public signal void changed ();

        private class PlayerState {
            public string bus_name;
            public string title = "";
            public string artist = "";
            public string status = "Stopped";
            public bool can_go_next = false;
            public bool can_go_previous = false;
            // Своя подписка на PropertiesChanged именно этого плеера.
            public uint props_sub = 0;

            public PlayerState (string bus_name) {
                this.bus_name = bus_name;
            }

            public bool is_playing () {
                return status == "Playing";
            }

            public bool has_track () {
                return title != "" || artist != "";
            }
        }

        public static MediaPlayerService get_global () {
            if (global == null) {
                global = new MediaPlayerService ();
            }
            return global;
        }

        private MediaPlayerService () {
            players = new HashTable<string, PlayerState> (str_hash, str_equal);

            Bus.get.begin (BusType.SESSION, null, (obj, res) => {
                try {
                    conn = Bus.get.end (res);
                } catch (Error e) {
                    warning ("MediaPlayerService: нет сессионной шины: %s", e.message);
                    return;
                }
                subscribe ();
                discover_players.begin ();
            });
        }

        ~MediaPlayerService () {
            if (conn == null) return;
            if (noc_sub != 0) conn.signal_unsubscribe (noc_sub);

            var iter = HashTableIter<string, PlayerState> (players);
            string name;
            PlayerState state;
            while (iter.next (out name, out state)) {
                if (state.props_sub != 0) conn.signal_unsubscribe (state.props_sub);
            }
        }

        private void subscribe () {
            // Bus.watch_name работает по точному имени, а имена MPRIS —
            // org.mpris.MediaPlayer2.<что угодно>. Поэтому слушаем
            // NameOwnerChanged целиком и фильтруем по префиксу сами.
            noc_sub = conn.signal_subscribe (DBUS_NAME, DBUS_NAME, "NameOwnerChanged",
                                             DBUS_PATH, null, DBusSignalFlags.NONE,
                                             on_name_owner_changed);
        }

        private async void discover_players () {
            try {
                var reply = yield conn.call (DBUS_NAME, DBUS_PATH, DBUS_NAME, "ListNames",
                                             null, new VariantType ("(as)"),
                                             DBusCallFlags.NONE, -1, null);
                var names = reply.get_child_value (0);
                for (size_t i = 0; i < names.n_children (); i++) {
                    string name = names.get_child_value (i).get_string ();
                    if (name.has_prefix (MPRIS_PREFIX)) add_player.begin (name);
                }
            } catch (Error e) {
                warning ("MediaPlayerService: ListNames не удался: %s", e.message);
            }
        }

        private void on_name_owner_changed (DBusConnection c, string? sender, string path,
                                            string iface, string signal_name, Variant parameters) {
            if (parameters.n_children () < 3) return;
            string name = parameters.get_child_value (0).get_string ();
            if (!name.has_prefix (MPRIS_PREFIX)) return;

            string old_owner = parameters.get_child_value (1).get_string ();
            string new_owner = parameters.get_child_value (2).get_string ();

            if (old_owner != "" && new_owner == "") {
                remove_player (name);
            } else if (new_owner != "") {
                add_player.begin (name);
            }
        }

        private async void add_player (string bus_name) {
            if (players.contains (bus_name)) return;
            var state = new PlayerState (bus_name);
            players.insert (bus_name, state);

            // Подписка на каждого плеера отдельно, с захватом его state в
            // замыкании. Общий подписчик потребовал бы сопоставлять уникальное
            // имя отправителя (:1.42) с well-known именем через GetNameOwner —
            // то есть блокирующий вызов на каждый сигнал в UI-потоке.
            state.props_sub = conn.signal_subscribe (bus_name, PROPS_IFACE,
                                                     "PropertiesChanged", MPRIS_PATH,
                                                     PLAYER_IFACE, DBusSignalFlags.NONE,
                                                     (c, sender, path, iface, sig, parameters) => {
                if (parameters.n_children () < 2) return;
                apply_props (state, parameters.get_child_value (1));
                recompute ();
            });

            // Начальный снимок: PropertiesChanged расскажет только про
            // последующие изменения, а плеер мог играть до нашего старта.
            try {
                var reply = yield conn.call (bus_name, MPRIS_PATH, PROPS_IFACE, "GetAll",
                                             new Variant ("(s)", PLAYER_IFACE),
                                             new VariantType ("(a{sv})"),
                                             DBusCallFlags.NONE, -1, null);
                apply_props (state, reply.get_child_value (0));
            } catch (Error e) {
                // Плеер мог исчезнуть между NameOwnerChanged и запросом.
                debug ("MediaPlayerService: GetAll на %s: %s", bus_name, e.message);
            }

            recompute ();
        }

        private void remove_player (string bus_name) {
            PlayerState? state = players.lookup (bus_name);
            if (state == null) return;
            if (state.props_sub != 0 && conn != null) {
                conn.signal_unsubscribe (state.props_sub);
                state.props_sub = 0;
            }
            players.remove (bus_name);
            if (active_name == bus_name) active_name = null;
            if (last_active_name == bus_name) last_active_name = null;
            recompute ();
        }

        private void apply_props (PlayerState state, Variant props) {
            var iter = new VariantIter (props);
            string key;
            Variant val;
            while (iter.next ("{sv}", out key, out val)) {
                switch (key) {
                    case "PlaybackStatus":
                        if (val.is_of_type (VariantType.STRING)) {
                            state.status = val.get_string ();
                            // Плеер, который только что заиграл, становится предпочтительным
                            // и остаётся таким после паузы.
                            if (state.is_playing ()) last_active_name = state.bus_name;
                        }
                        break;
                    case "Metadata":
                        apply_metadata (state, val);
                        break;
                    case "CanGoNext":
                        if (val.is_of_type (VariantType.BOOLEAN)) state.can_go_next = val.get_boolean ();
                        break;
                    case "CanGoPrevious":
                        if (val.is_of_type (VariantType.BOOLEAN)) state.can_go_previous = val.get_boolean ();
                        break;
                }
            }
        }

        private void apply_metadata (PlayerState state, Variant metadata) {
            // Metadata приходит как a{sv}, но некоторые плееры заворачивают её
            // ещё в один вариант.
            Variant m = metadata;
            if (m.is_of_type (VariantType.VARIANT)) m = m.get_variant ();
            if (!m.is_of_type (new VariantType ("a{sv}"))) return;

            string new_title = "";
            string new_artist = "";

            var iter = new VariantIter (m);
            string key;
            Variant val;
            while (iter.next ("{sv}", out key, out val)) {
                if (key == "xesam:title") {
                    if (val.is_of_type (VariantType.STRING)) new_title = val.get_string ();
                } else if (key == "xesam:artist") {
                    // По спеке это as, но встречается и одиночная строка.
                    if (val.is_of_type (new VariantType ("as"))) {
                        if (val.n_children () > 0) {
                            new_artist = val.get_child_value (0).get_string ();
                        }
                    } else if (val.is_of_type (VariantType.STRING)) {
                        new_artist = val.get_string ();
                    }
                }
            }

            state.title = new_title;
            state.artist = new_artist;
        }

        // Приоритет выбора активного плеера:
        //   1. тот, кто сейчас играет;
        //   2. тот, кто играл последним — так пауза остаётся на том плеере,
        //      с которым взаимодействовали, а не перескакивает на другой;
        //   3. любой с треком — чтобы кнопка не пропадала после рестарта оболочки.
        private void recompute () {
            PlayerState? best = null;

            var iter = HashTableIter<string, PlayerState> (players);
            string name;
            PlayerState state;
            while (iter.next (out name, out state)) {
                if (!state.has_track ()) continue;
                if (state.is_playing ()) {
                    best = state;
                    break;
                }
            }

            if (best == null && last_active_name != null) {
                var remembered = players.lookup (last_active_name);
                if (remembered != null && remembered.has_track ()) best = remembered;
            }

            if (best == null) {
                var iter2 = HashTableIter<string, PlayerState> (players);
                while (iter2.next (out name, out state)) {
                    if (state.has_track ()) {
                        best = state;
                        break;
                    }
                }
            }

            if (best == null) {
                active_name = null;
                if (available) {
                    available = false;
                    title = "";
                    artist = "";
                    playing = false;
                    can_go_next = false;
                    can_go_previous = false;
                    changed ();
                }
                return;
            }

            active_name = best.bus_name;

            bool dirty = !available
                      || title != best.title
                      || artist != best.artist
                      || playing != best.is_playing ()
                      || can_go_next != best.can_go_next
                      || can_go_previous != best.can_go_previous;
            if (!dirty) return;

            available = true;
            title = best.title;
            artist = best.artist;
            playing = best.is_playing ();
            can_go_next = best.can_go_next;
            can_go_previous = best.can_go_previous;
            changed ();
        }

        // Текст для панели: «Артист - Название», либо только то, что известно.
        public string get_display_text () {
            if (!available) return "";
            if (artist != "" && title != "") return @"$artist - $title";
            if (title != "") return title;
            return artist;
        }

        public void play_pause () {
            call_active ("PlayPause");
        }

        public void next () {
            if (!can_go_next) return;
            call_active ("Next");
        }

        public void previous () {
            if (!can_go_previous) return;
            call_active ("Previous");
        }

        private void call_active (string method) {
            if (conn == null || active_name == null) return;
            // Явное взаимодействие закрепляет плеер: если после PlayPause он
            // встал на паузу, панель всё равно показывает его, а не чужой трек.
            last_active_name = active_name;
            conn.call.begin (active_name, MPRIS_PATH, PLAYER_IFACE, method, null, null,
                             DBusCallFlags.NONE, 2000, null, (obj, res) => {
                try {
                    conn.call.end (res);
                } catch (Error e) {
                    warning ("MediaPlayerService: %s не выполнен: %s", method, e.message);
                }
            });
        }
    }
}

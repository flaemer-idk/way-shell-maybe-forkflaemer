// Путь: src/services/StatusNotifierService.vala
//
// Системный трей по протоколу StatusNotifierItem (KDE/freedesktop).
//
// Раньше здесь был стаб: конструктор создавал пустой HashTable, четыре сигнала
// не эмитились никогда, IndicatorBar показывал пустоту. Теперь оболочка сама
// работает watcher'ом и host'ом: держит имя org.kde.StatusNotifierWatcher,
// принимает регистрации приложений, читает их свойства и строит меню из
// com.canonical.dbusmenu.
using GLib;

namespace WayShell.Services {

    // Watcher, которого ищут приложения. Отдельный объект, потому что его
    // методы и свойства экспортируются на шину как есть, а сервис вокруг
    // занимается уже своей логикой.
    [DBus (name = "org.kde.StatusNotifierWatcher")]
    public class StatusNotifierWatcher : GLib.Object {
        // service → путь объекта. Ключ — то, что приложение прислало в
        // RegisterStatusNotifierItem, приведённое к "bus_name/object_path".
        private GenericArray<string> items;
        private bool host_registered = false;

        public signal void status_notifier_item_registered (string service);
        public signal void status_notifier_item_unregistered (string service);
        public signal void status_notifier_host_registered ();
        public signal void status_notifier_host_unregistered ();

        public StatusNotifierWatcher () {
            items = new GenericArray<string> ();
        }

        public string[] registered_status_notifier_items {
            owned get {
                var result = new string[items.length];
                for (int i = 0; i < items.length; i++) result[i] = items.get (i);
                return result;
            }
        }

        public bool is_status_notifier_host_registered {
            get { return host_registered; }
        }

        public int protocol_version {
            get { return 0; }
        }

        // service по спецификации — имя на шине, но часть приложений присылает
        // путь объекта ("/StatusNotifierItem"). Тогда именем считается sender.
        public void register_status_notifier_item (string service, GLib.BusName sender) throws Error {
            string bus_name;
            string object_path;

            if (service.has_prefix ("/")) {
                bus_name = (string) sender;
                object_path = service;
            } else {
                bus_name = service;
                object_path = "/StatusNotifierItem";
            }

            string key = bus_name + object_path;
            for (int i = 0; i < items.length; i++) {
                if (items.get (i) == key) return;
            }

            items.add (key);
            debug ("StatusNotifierWatcher: зарегистрирован %s", key);
            status_notifier_item_registered (key);
        }

        public void register_status_notifier_host (string service) throws Error {
            if (host_registered) return;
            host_registered = true;
            status_notifier_host_registered ();
        }

        // Не часть протокола: вызывается сервисом, когда приложение ушло с шины.
        [DBus (visible = false)]
        public void drop_item (string key) {
            for (int i = 0; i < items.length; i++) {
                if (items.get (i) == key) {
                    items.remove_index (i);
                    status_notifier_item_unregistered (key);
                    return;
                }
            }
        }
    }

    // Один значок трея: свойства с шины, меню и способы его активировать.
    public class StatusNotifierItem : GLib.Object {
        private const string ITEM_IFACE = "org.kde.StatusNotifierItem";
        private const string PROPS_IFACE = "org.freedesktop.DBus.Properties";

        public string bus_name { get; private set; }
        public string object_path { get; private set; }
        // Ключ в таблице сервиса: bus_name + object_path.
        public string key { owned get { return bus_name + object_path; } }

        public string id { get; private set; default = ""; }
        public string title { get; private set; default = ""; }
        public string status { get; private set; default = "Active"; }
        public string tooltip { get; private set; default = ""; }
        public bool item_is_menu { get; private set; default = false; }

        public string icon_name { get; private set; default = ""; }
        // Готовая картинка, если приложение отдало пиксели вместо имени иконки.
        public Gdk.Paintable? icon_paintable { get; private set; default = null; }

        public GLib.MenuModel? menu_model { get; private set; default = null; }
        public GLib.ActionGroup? action_group { get; private set; default = null; }

        // Иконка, статус или подсказка поменялись.
        public signal void updated ();
        // Модель меню заменилась целиком — виджету нужно пересоздать popover.
        public signal void menu_updated ();

        private DBusConnection conn;
        private uint signal_sub = 0;
        private uint refresh_timer = 0;
        private string? menu_path = null;
        private DbusMenu? menu = null;

        public StatusNotifierItem (DBusConnection conn, string bus_name, string object_path) {
            this.conn = conn;
            this.bus_name = bus_name;
            this.object_path = object_path;

            // Приложения сообщают об изменениях не через PropertiesChanged, а
            // своими сигналами NewIcon/NewStatus/NewToolTip/NewTitle. Подписка
            // одна на все — фильтр по интерфейсу, а имя сигнала не важно:
            // в ответ мы вс႑ равно перечитываем свойства целиком.
            signal_sub = conn.signal_subscribe (bus_name, ITEM_IFACE, null, object_path,
                                                null, DBusSignalFlags.NONE,
                                                on_item_signal);
            refresh.begin ();
        }

        ~StatusNotifierItem () {
            shutdown ();
        }

        // Отвязка от шины вручную. На автоматику полагаться нельзя: действия
        // меню держат ссылку на DbusMenu, а тот — на группу действий, то есть
        // без явного разрыва цикл ссылок оставлял бы значок в памяти навсегда.
        public void shutdown () {
            if (refresh_timer != 0) {
                Source.remove (refresh_timer);
                refresh_timer = 0;
            }
            if (signal_sub != 0) {
                conn.signal_unsubscribe (signal_sub);
                signal_sub = 0;
            }
            if (menu != null) {
                menu.shutdown ();
                menu = null;
            }
            menu_model = null;
            action_group = null;
        }

        private void on_item_signal (DBusConnection c, string? sender, string path,
                                     string iface, string signal_name, Variant parameters) {
            // Приложения шлют NewIcon, NewStatus и NewToolTip одной очередью;
            // без склейки на каждое уш႑л бы свой GetAll.
            if (refresh_timer != 0) return;
            refresh_timer = Timeout.add (80, () => {
                refresh_timer = 0;
                refresh.begin ();
                return Source.REMOVE;
            });
        }

        public async void refresh () {
            Variant? reply = null;
            try {
                reply = yield conn.call (bus_name, object_path, PROPS_IFACE, "GetAll",
                                         new Variant ("(s)", ITEM_IFACE),
                                         new VariantType ("(a{sv})"),
                                         DBusCallFlags.NONE, -1, null);
            } catch (Error e) {
                debug ("StatusNotifierItem: %s не отдал свойства: %s", key, e.message);
                return;
            }

            var props = reply.get_child_value (0);
            apply_props (props);

            // Меню читается один раз: путь у значка не меняется.
            if (menu == null && menu_path != null) {
                menu = new DbusMenu (conn, bus_name, menu_path);
                menu.changed.connect (on_menu_changed);
                yield menu.reload ();
            }

            updated ();
        }

        private void on_menu_changed () {
            if (menu == null) return;
            menu_model = menu.model;
            action_group = menu.actions;
            menu_updated ();
        }

        private void apply_props (Variant props) {
            string? s;

            s = lookup_string (props, "Id");
            if (s != null) id = s;
            s = lookup_string (props, "Title");
            if (s != null) title = s;
            s = lookup_string (props, "Status");
            if (s != null) status = s;

            var v_menu = props.lookup_value ("Menu", VariantType.OBJECT_PATH);
            if (v_menu != null) menu_path = v_menu.get_string ();

            var v_is_menu = props.lookup_value ("ItemIsMenu", VariantType.BOOLEAN);
            if (v_is_menu != null) item_is_menu = v_is_menu.get_boolean ();

            // Свой каталог с иконками: приложения вне темы (Flatpak, snap)
            // складывают их рядом с собой и сообщают путь здесь.
            s = lookup_string (props, "IconThemePath");
            if (s != null && s != "") {
                var theme = Gtk.IconTheme.get_for_display (Gdk.Display.get_default ());
                theme.add_search_path (s);
            }

            // NeedsAttention — отдельная иконка, если приложение её дало.
            bool attention = (status == "NeedsAttention");
            string icon_prop = attention ? "AttentionIconName" : "IconName";
            string pixmap_prop = attention ? "AttentionIconPixmap" : "IconPixmap";

            s = lookup_string (props, icon_prop);
            if ((s == null || s == "") && attention) s = lookup_string (props, "IconName");
            icon_name = s ?? "";

            var pixmap = props.lookup_value (pixmap_prop, new VariantType ("a(iiay)"));
            if (pixmap == null) pixmap = props.lookup_value ("IconPixmap", new VariantType ("a(iiay)"));
            icon_paintable = (pixmap != null) ? pixmap_to_paintable (pixmap) : null;

            apply_tooltip (props);
        }

        // ToolTip — (icon_name, icon_pixmap, title, body). Показываем title,
        // при наличии добавляем body: у blueman там имя устройства.
        private void apply_tooltip (Variant props) {
            var v = props.lookup_value ("ToolTip", new VariantType ("(sa(iiay)ss)"));
            if (v == null) {
                tooltip = (title != "") ? title : id;
                return;
            }

            string tip_title = v.get_child_value (2).get_string ();
            string tip_body = v.get_child_value (3).get_string ();

            if (tip_title != "" && tip_body != "") {
                tooltip = tip_title + "\n" + tip_body;
            } else if (tip_title != "") {
                tooltip = tip_title;
            } else if (tip_body != "") {
                tooltip = tip_body;
            } else {
                tooltip = (title != "") ? title : id;
            }
        }

        private static string? lookup_string (Variant props, string name) {
            var v = props.lookup_value (name, VariantType.STRING);
            return (v != null) ? v.get_string () : null;
        }

        // Пиксели в SNI — ARGB32 в сетевом порядке байтов. Берём самый большой
        // вариант: панель всё равно масштабирует иконку до своего размера.
        private static Gdk.Paintable? pixmap_to_paintable (Variant pixmaps) {
            int best_w = 0, best_h = 0;
            Variant? best_data = null;

            var iter = pixmaps.iterator ();
            Variant? entry = null;
            while ((entry = iter.next_value ()) != null) {
                int w = entry.get_child_value (0).get_int32 ();
                int h = entry.get_child_value (1).get_int32 ();
                if (w <= 0 || h <= 0) continue;
                if (w * h > best_w * best_h) {
                    best_w = w;
                    best_h = h;
                    best_data = entry.get_child_value (2);
                }
            }

            if (best_data == null) return null;

            var bytes = best_data.get_data_as_bytes ();
            if (bytes.get_size () < (size_t) (best_w * best_h * 4)) return null;

            return new Gdk.MemoryTexture (best_w, best_h,
                                          Gdk.MemoryFormat.A8R8G8B8,
                                          bytes, best_w * 4);
        }

        public void activate_item (int x, int y) {
            call_item ("Activate", new Variant ("(ii)", x, y));
        }

        public void secondary_activate (int x, int y) {
            call_item ("SecondaryActivate", new Variant ("(ii)", x, y));
        }

        public void scroll (int delta, string orientation) {
            call_item ("Scroll", new Variant ("(is)", delta, orientation));
        }

        private void call_item (string method, Variant args) {
            conn.call.begin (bus_name, object_path, ITEM_IFACE, method, args,
                             null, DBusCallFlags.NONE, -1, null, (obj, res) => {
                try {
                    conn.call.end (res);
                } catch (Error e) {
                    // Часть приложений не реализует SecondaryActivate/Scroll —
                    // это нормально, поэтому debug, а не warning.
                    debug ("StatusNotifierItem: %s.%s: %s", key, method, e.message);
                }
            });
        }

        // Приложение может строить меню лениво, по AboutToShow.
        public void about_to_show () {
            if (menu != null) menu.about_to_show ();
        }
    }
    // Меню значка по протоколу com.canonical.dbusmenu.
    //
    // Из дерева, которое отдаёт GetLayout, собирается GLib.MenuModel и
    // SimpleActionGroup: PopoverMenu умеет показывать только их. Обратный путь —
    // метод Event с eventId "clicked".
    public class DbusMenu : GLib.Object {
        private const string MENU_IFACE = "com.canonical.dbusmenu";
        // Префикс группы действий. Должен совпадать с insert_action_group в виджете.
        public const string ACTION_PREFIX = "tray";

        public GLib.Menu? model { get; private set; default = null; }
        public GLib.SimpleActionGroup? actions { get; private set; default = null; }

        public signal void changed ();

        private DBusConnection conn;
        private string bus_name;
        private string object_path;
        private uint signal_sub = 0;
        private uint reload_timer = 0;

        public DbusMenu (DBusConnection conn, string bus_name, string object_path) {
            this.conn = conn;
            this.bus_name = bus_name;
            this.object_path = object_path;

            // LayoutUpdated и ItemsPropertiesUpdated обрабатываются одинаково —
            // перечитыванием дерева, поэтому имя сигнала не фильтруем.
            signal_sub = conn.signal_subscribe (bus_name, MENU_IFACE, null, object_path,
                                               null, DBusSignalFlags.NONE, on_menu_signal);
        }

        ~DbusMenu () {
            shutdown ();
        }

        // Действия меню замыкаются на this через send_event, а группа действий
        // лежит в поле — без явного сброса деструктор не вызовётся никогда.
        public void shutdown () {
            if (reload_timer != 0) {
                Source.remove (reload_timer);
                reload_timer = 0;
            }
            if (signal_sub != 0) {
                conn.signal_unsubscribe (signal_sub);
                signal_sub = 0;
            }
            model = null;
            actions = null;
        }

        private void on_menu_signal (DBusConnection c, string? sender, string path,
                                     string iface, string signal_name, Variant parameters) {
            // Приложения вроде мониторов сети шлют обновления пачками; без
            // склейки на каждое приходил бы отдельный GetLayout.
            if (reload_timer != 0) return;
            reload_timer = Timeout.add (100, () => {
                reload_timer = 0;
                reload.begin ();
                return Source.REMOVE;
            });
        }

        public async void reload () {
            Variant? reply = null;
            try {
                var args = new Variant.tuple (new Variant[] {
                    new Variant.int32 (0),   // parentId: корень
                    new Variant.int32 (-1),  // recursionDepth: всё дерево
                    new Variant.array (VariantType.STRING, new Variant[] {})
                });
                reply = yield conn.call (bus_name, object_path, MENU_IFACE, "GetLayout",
                                        args, new VariantType ("(u(ia{sv}av))"),
                                        DBusCallFlags.NONE, -1, null);
            } catch (Error e) {
                debug ("DbusMenu: GetLayout на %s%s: %s", bus_name, object_path, e.message);
                return;
            }

            var root = reply.get_child_value (1);
            var new_actions = new SimpleActionGroup ();
            var new_model = new GLib.Menu ();
            build_items (new_model, root.get_child_value (2), new_actions);

            model = new_model;
            actions = new_actions;
            changed ();
        }

        // Разделители в GMenu — это границы секций, отдельного элемента нет.
        private void build_items (GLib.Menu menu, Variant children, SimpleActionGroup group) {
            var section = new GLib.Menu ();

            var iter = children.iterator ();
            Variant? raw = null;
            while ((raw = iter.next_value ()) != null) {
                Variant item = raw.is_of_type (VariantType.VARIANT) ? raw.get_variant () : raw;
                if (!item.is_of_type (new VariantType ("(ia{sv}av)"))) continue;

                int32 id = item.get_child_value (0).get_int32 ();
                var props = item.get_child_value (1);
                var kids = item.get_child_value (2);

                if (!prop_bool (props, "visible", true)) continue;

                string type = prop_string (props, "type") ?? "standard";
                if (type == "separator") {
                    if (section.get_n_items () > 0) {
                        menu.append_section (null, section);
                        section = new GLib.Menu ();
                    }
                    continue;
                }

                string label = prop_string (props, "label") ?? "";

                if (prop_string (props, "children-display") == "submenu") {
                    var submenu = new GLib.Menu ();
                    build_items (submenu, kids, group);
                    section.append_submenu (label, submenu);
                    continue;
                }

                string action_name = "i%d".printf (id);
                string toggle_type = prop_string (props, "toggle-type") ?? "";

                SimpleAction action;
                if (toggle_type != "") {
                    bool state = prop_int (props, "toggle-state", 0) == 1;
                    action = new SimpleAction.stateful (action_name, null,
                                                        new Variant.boolean (state));
                } else {
                    action = new SimpleAction (action_name, null);
                }
                action.set_enabled (prop_bool (props, "enabled", true));

                action.activate.connect (() => {
                    // Своя обработка activate отключает автоматическое
                    // переключение состояния в GSimpleAction — делаем сами.
                    if (toggle_type != "") {
                        var st = action.get_state ();
                        if (st != null) {
                            action.set_state (new Variant.boolean (!st.get_boolean ()));
                        }
                    }
                    send_event (id, "clicked");
                });
                group.add_action (action);

                var menu_item = new GLib.MenuItem (label, ACTION_PREFIX + "." + action_name);
                string? icon_name = prop_string (props, "icon-name");
                if (icon_name != null && icon_name != "") {
                    menu_item.set_icon (new ThemedIcon (icon_name));
                }
                section.append_item (menu_item);
            }

            if (section.get_n_items () > 0) {
                menu.append_section (null, section);
            }
        }

        private static string? prop_string (Variant props, string name) {
            var v = props.lookup_value (name, VariantType.STRING);
            return (v != null) ? v.get_string () : null;
        }

        private static bool prop_bool (Variant props, string name, bool fallback) {
            var v = props.lookup_value (name, VariantType.BOOLEAN);
            return (v != null) ? v.get_boolean () : fallback;
        }

        private static int32 prop_int (Variant props, string name, int32 fallback) {
            var v = props.lookup_value (name, VariantType.INT32);
            return (v != null) ? v.get_int32 () : fallback;
        }

        private void send_event (int32 id, string event_id) {
            var args = new Variant.tuple (new Variant[] {
                new Variant.int32 (id),
                new Variant.string (event_id),
                new Variant.variant (new Variant.string ("")),
                new Variant.uint32 ((uint32) (get_real_time () / 1000000))
            });
            conn.call.begin (bus_name, object_path, MENU_IFACE, "Event", args,
                             null, DBusCallFlags.NONE, -1, null, (obj, res) => {
                try {
                    conn.call.end (res);
                } catch (Error e) {
                    warning ("DbusMenu: Event(%d) не доставлен: %s", id, e.message);
                }
            });
        }

        // Часть приложений наполняет меню лениво и ждёт этот вызов перед показом.
        public void about_to_show () {
            conn.call.begin (bus_name, object_path, MENU_IFACE, "AboutToShow",
                             new Variant ("(i)", 0), new VariantType ("(b)"),
                             DBusCallFlags.NONE, -1, null, (obj, res) => {
                try {
                    var reply = conn.call.end (res);
                    // true = «дерево изменилось», надо перечитать.
                    if (reply.get_child_value (0).get_boolean ()) reload.begin ();
                } catch (Error e) {
                    debug ("DbusMenu: AboutToShow: %s", e.message);
                }
            });
        }
    }

    public class StatusNotifierService : GLib.Object {
        private const string WATCHER_NAME = "org.kde.StatusNotifierWatcher";
        private const string WATCHER_PATH = "/StatusNotifierWatcher";

        private static StatusNotifierService? global = null;

        private DBusConnection? conn = null;
        private StatusNotifierWatcher watcher;
        private uint watcher_name_id = 0;
        private uint host_name_id = 0;
        private uint watcher_reg_id = 0;

        private HashTable<string, StatusNotifierItem> items;
        // key → id подписки на исчезновение владельца имени.
        private HashTable<string, uint> owner_watches;

        public signal void item_added (StatusNotifierItem item);
        public signal void item_removed (StatusNotifierItem item);

        public static StatusNotifierService get_global () {
            if (global == null) {
                global = new StatusNotifierService ();
            }
            return global;
        }

        private StatusNotifierService () {
            items = new HashTable<string, StatusNotifierItem> (str_hash, str_equal);
            owner_watches = new HashTable<string, uint> (str_hash, str_equal);

            watcher = new StatusNotifierWatcher ();
            watcher.status_notifier_item_registered.connect (on_item_registered);

            watcher_name_id = Bus.own_name (BusType.SESSION, WATCHER_NAME,
                                           BusNameOwnerFlags.NONE,
                                           on_bus_acquired,
                                           on_watcher_name_acquired,
                                           on_watcher_name_lost);
        }

        ~StatusNotifierService () {
            if (watcher_reg_id != 0 && conn != null) conn.unregister_object (watcher_reg_id);
            if (watcher_name_id != 0) Bus.unown_name (watcher_name_id);
            if (host_name_id != 0) Bus.unown_name (host_name_id);
        }

        public HashTable<string, StatusNotifierItem> get_items () {
            return items;
        }

        private void on_bus_acquired (DBusConnection c, string name) {
            conn = c;
            try {
                watcher_reg_id = c.register_object (WATCHER_PATH, watcher);
            } catch (IOError e) {
                warning ("StatusNotifierService: watcher не экспортирован: %s", e.message);
            }
        }

        private void on_watcher_name_acquired (DBusConnection c, string name) {
            // Приложения из мира KDE проверяют не только watcher, но и наличие
            // хоста, который его слушает. Хост — это мы; отдельное имя нужно
            // только чтобы проверка проходила.
            host_name_id = Bus.own_name (BusType.SESSION,
                                         "org.kde.StatusNotifierHost-%d".printf (Posix.getpid ()),
                                         BusNameOwnerFlags.NONE, null, null, null);
            // Метод объявлен throws только ради D-Bus-конвенции; своё тело
            // исключений не бросает.
            try {
                watcher.register_status_notifier_host (name);
            } catch (Error e) {
                warning ("StatusNotifierService: саморегистрация хоста: %s", e.message);
            }
            debug ("StatusNotifierService: watcher поднят");
        }

        private void on_watcher_name_lost (DBusConnection? c, string name) {
            // Трей в сессии может быть только один. Если имя занято другой
            // оболочкой или панелью, молча уступаем: перехват сломал бы её.
            warning ("StatusNotifierService: %s занят другим процессом, трей отключён", name);
        }

        private void on_item_registered (string key) {
            if (conn == null) return;
            if (items.contains (key)) return;

            // key = bus_name + object_path, а путь всегда начинается со слэша.
            int split = key.index_of_char ('/');
            if (split <= 0) return;
            string bus_name = key.substring (0, split);
            string object_path = key.substring (split);

            var item = new StatusNotifierItem (conn, bus_name, object_path);
            items.insert (key, item);

            // Приложение может умереть без Unregister — следим за именем сами.
            uint watch = Bus.watch_name (BusType.SESSION, bus_name,
                                         BusNameWatcherFlags.NONE, null,
                                         (c, n) => { remove_item (key); });
            owner_watches.insert (key, watch);

            item_added (item);
        }

        private void remove_item (string key) {
            var item = items.lookup (key);
            if (item == null) return;

            items.remove (key);
            uint watch = owner_watches.lookup (key);
            if (watch != 0) {
                Bus.unwatch_name (watch);
                owner_watches.remove (key);
            }
            watcher.drop_item (key);
            item_removed (item);
            // После того как виджеты отпустили значок: рвём подписки и цикл
            // ссылок внутри меню.
            item.shutdown ();
        }
    }
}

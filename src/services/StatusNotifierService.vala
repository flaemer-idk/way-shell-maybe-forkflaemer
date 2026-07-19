namespace WayShell.Services {
    // Описываем D-Bus прокси-интерфейс для активации значков трея (StatusNotifierItem)
    [DBus (name = "org.kde.StatusNotifierItem")]
    public interface StatusNotifierItemProxy : GLib.Object {
        public abstract void activate (int32 x, int32 y) throws GLib.Error;
    }

    public class StatusNotifierItem : GLib.Object {
        public string bus_name { get; set; }
        public string icon_name { get; set; }
        public string title { get; set; }
        public GLib.MenuModel? menu_model { get; set; }
        public GLib.ActionGroup? action_group { get; set; }
        public Gdk.Pixbuf? icon_pixmap { get; set; }
        public Gdk.Pixbuf? icon_pixmap_from_theme { get; set; }
        
        // Используем типизированный D-Bus прокси вместо 'dynamic'
        public StatusNotifierItemProxy proxy { get; set; }

        public StatusNotifierItem (string bus_name, string icon_name) {
            this.bus_name = bus_name;
            this.icon_name = icon_name;
        }

        public void about_to_show (uint32 id) {}
    }

    public class StatusNotifierService : GLib.Object {
        private static StatusNotifierService? global = null;
        private HashTable<string, StatusNotifierItem> items;

        public signal void status_notifier_item_added (HashTable<string, StatusNotifierItem> items, StatusNotifierItem item);
        public signal void status_notifier_item_removed (HashTable<string, StatusNotifierItem> items, StatusNotifierItem item);
        public signal void status_notifier_item_properties_changed (StatusNotifierItem item);
        public signal void status_notifier_item_menu_updated (StatusNotifierItem item);

        public static StatusNotifierService get_global () {
            if (global == null) {
                global = new StatusNotifierService ();
            }
            return global;
        }

        private StatusNotifierService () {
            items = new HashTable<string, StatusNotifierItem> (str_hash, str_equal);
        }

        public HashTable<string, StatusNotifierItem> get_items () {
            return items;
        }
    }
}
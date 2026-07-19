[CCode (cheader_filename = "wireplumber-0.5/wp/wp.h", cprefix = "Wp", lower_case_cprefix = "wp_")]
namespace Wp {
    [CCode (cheader_filename = "wireplumber-0.5/wp/wp.h", cname = "WpCore")]
    public class Core : GLib.Object {
        public Core (GLib.Object? context, GLib.Object? properties, GLib.Object? main_context);
        public bool connect ();
        public bool install_object_manager (GLib.Object om);
    }

    [CCode (cheader_filename = "wireplumber-0.5/wp/wp.h", cname = "WpIterator", free_function = "wp_iterator_free")]
    public class Iterator {
        [CCode (cname = "wp_iterator_next")]
        public bool next (ref GLib.Value item);
    }

    [CCode (cheader_filename = "wireplumber-0.5/wp/wp.h", cname = "WpObjectManager")]
    public class ObjectManager : GLib.Object {
        public ObjectManager ();
        public void add_interest (GLib.Type type, ...);
        public signal void objects_changed ();
        public signal void installed ();
        [CCode (cname = "wp_object_manager_new_iterator")]
        public Iterator new_iterator ();
    }

    [CCode (cheader_filename = "wireplumber-0.5/wp/wp.h", cname = "WpNode")]
    public class Node : GLib.Object {
        [CCode (cname = "wp_pipewire_object_get_property")]
        public unowned string? get_pw_property (string name);

        [CCode (cname = "wp_proxy_get_bound_id")]
        public uint32 get_bound_id ();
    }

    [CCode (cheader_filename = "wireplumber-0.5/wp/wp.h", cname = "WpDevice")]
    public class Device : GLib.Object {}

    [CCode (cheader_filename = "wireplumber-0.5/wp/wp.h", cname = "WpPlugin")]
    public class Plugin : GLib.Object {
        public static unowned Plugin? find (Core core, string name);
    }

    [CCode (cheader_filename = "wireplumber-0.5/wp/wp.h", cname = "WpMetadata")]
    public class Metadata : GLib.Object {
        [CCode (cname = "wp_metadata_set")]
        public void set (uint32 subject, string? key, string? type, string? value);
    }
}
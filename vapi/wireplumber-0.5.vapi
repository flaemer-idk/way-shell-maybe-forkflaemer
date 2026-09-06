[CCode (cheader_filename = "wireplumber-0.5/wp/wp.h", cprefix = "Wp", lower_case_cprefix = "wp_")]
namespace Wp {
    [CCode (cheader_filename = "wireplumber-0.5/wp/wp.h", cname = "WpCore")]
    public class Core : GLib.Object {
        public Core (GLib.Object? context, GLib.Object? properties, GLib.Object? main_context);
        public bool connect ();
        public bool install_object_manager (GLib.Object om);

        // Реальная сигнатура (component-loader.h) заканчивается `gpointer data`
        // после колбека. Когда функция была объявлена вручную через extern
        // без этого параметра, совпадение держалось на том, что valac сам
        // кладёт target делегата следующим аргументом: стоило лямбде
        // захватить локальную переменную, и туда ушла бы выделенная блок-структура
        // без владельца. Объявлена как async: finish_name даёт вала-стороне
        // проверку ошибки, которую прежний вариант молча терял.
        [CCode (cname = "wp_core_load_component", finish_name = "wp_core_load_component_finish")]
        public async bool load_component (string component, string type, void* args,
                                         string? provides, GLib.Cancellable? cancellable = null) throws GLib.Error;
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
        // Без этого объекты приходят неактивированными: у WpMetadata не будет
        // ни локального кэша данных, ни возможности писать в него.
        [CCode (cname = "wp_object_manager_request_object_features")]
        public void request_object_features (GLib.Type type, uint32 features);
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

    // WpProperties — не GObject, а счётчик-структура.
    [CCode (cheader_filename = "wireplumber-0.5/wp/wp.h", cname = "WpProperties",
            ref_function = "wp_properties_ref", unref_function = "wp_properties_unref")]
    [Compact]
    public class Properties {
        [CCode (cname = "wp_properties_get")]
        public unowned string? get (string key);
    }

    [CCode (cheader_filename = "wireplumber-0.5/wp/wp.h", cname = "WpMetadata")]
    public class Metadata : GLib.Object {
        [CCode (cname = "wp_metadata_set")]
        public void set (uint32 subject, string? key, string? type, string? value);

        [CCode (cname = "wp_metadata_find")]
        public unowned string? find (uint32 subject, string key, out unowned string? type);

        // Метаданные не WpPipewireObject, так что get_pw_property к ним не применим;
        // имя (metadata.name) лежит в глобальных свойствах прокси.
        [CCode (cname = "wp_global_proxy_get_global_properties")]
        public Properties? get_global_properties ();
    }

    // Фичи объектов (wp/proxy.h). Объект попадает в ObjectManager только когда
    // активированы все затребованные фичи, а request_object_features задаёт набор
    // целиком — BOUND нужно перечислять явно вместе с остальными.
    [CCode (cname = "WP_PROXY_FEATURE_BOUND")]
    public const uint32 PROXY_FEATURE_BOUND;

    [CCode (cname = "WP_PIPEWIRE_OBJECT_FEATURE_INFO")]
    public const uint32 PIPEWIRE_OBJECT_FEATURE_INFO;

    // Без неё enum_params_sync("EnumProfile") на карте отдаёт пустоту.
    [CCode (cname = "WP_PIPEWIRE_OBJECT_FEATURE_PARAM_PROFILE")]
    public const uint32 PIPEWIRE_OBJECT_FEATURE_PARAM_PROFILE;

    // WP_METADATA_FEATURE_DATA — WP_PROXY_FEATURE_CUSTOM_START << 0, то есть 1 << 16.
    [CCode (cname = "WP_METADATA_FEATURE_DATA")]
    public const uint32 METADATA_FEATURE_DATA;
}
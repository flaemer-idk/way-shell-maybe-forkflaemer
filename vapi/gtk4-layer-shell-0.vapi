[CCode (cheader_filename = "gtk4-layer-shell.h", gir_namespace = "Gtk4LayerShell", gir_version = "1.0")]
namespace Gtk4LayerShell {
    [CCode (cheader_filename = "gtk4-layer-shell.h", cname = "GtkLayerShellLayer", cprefix = "GTK_LAYER_SHELL_LAYER_")]
    public enum Layer {
        BACKGROUND,
        BOTTOM,
        TOP,
        OVERLAY
    }

    [CCode (cheader_filename = "gtk4-layer-shell.h", cname = "GtkLayerShellEdge", cprefix = "GTK_LAYER_SHELL_EDGE_")]
    public enum Edge {
        LEFT,
        RIGHT,
        TOP,
        BOTTOM,
        ENTRY_NUMBER
    }

    [CCode (cheader_filename = "gtk4-layer-shell.h", cname = "GtkLayerShellKeyboardMode", cprefix = "GTK_LAYER_SHELL_KEYBOARD_MODE_")]
    public enum KeyboardMode {
        NONE,
        EXCLUSIVE,
        ON_DEMAND
    }

    [CCode (cheader_filename = "gtk4-layer-shell.h", cname = "gtk_layer_init_for_window")]
    public static void init_for_window (Gtk.Window window);

    [CCode (cheader_filename = "gtk4-layer-shell.h", cname = "gtk_layer_set_namespace")]
    public static void set_namespace (Gtk.Window window, string name_space);

    [CCode (cheader_filename = "gtk4-layer-shell.h", cname = "gtk_layer_set_layer")]
    public static void set_layer (Gtk.Window window, Layer layer);

    [CCode (cheader_filename = "gtk4-layer-shell.h", cname = "gtk_layer_set_anchor")]
    public static void set_anchor (Gtk.Window window, Edge edge, bool anchor_to_edge);

    [CCode (cheader_filename = "gtk4-layer-shell.h", cname = "gtk_layer_set_margin")]
    public static void set_margin (Gtk.Window window, Edge edge, int margin_size);

    [CCode (cheader_filename = "gtk4-layer-shell.h", cname = "gtk_layer_set_keyboard_mode")]
    public static void set_keyboard_mode (Gtk.Window window, KeyboardMode mode);

    [CCode (cheader_filename = "gtk4-layer-shell.h", cname = "gtk_layer_auto_exclusive_zone_enable")]
    public static void auto_exclusive_zone_enable (Gtk.Window window);

    [CCode (cheader_filename = "gtk4-layer-shell.h", cname = "gtk_layer_set_monitor")]
    public static void set_monitor (Gtk.Window window, Gdk.Monitor monitor);
}
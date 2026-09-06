using Gtk;

namespace WayShell.Services {
    public class ThemeService : GLib.Object {
        private static ThemeService? global = null;

        private const string CSS_RESOURCE =
            "/org/flaemer/way-shell/data/theme/way-shell-dark.css";
        private const string CSS_FILENAME = "way-shell-dark.css";

        private CssProvider provider;

        public static ThemeService get_global () {
            if (global == null) {
                global = new ThemeService ();
            }
            return global;
        }

        private ThemeService () {
            provider = new CssProvider ();
            provider.parsing_error.connect ((section, e) => {
                warning ("ThemeService: CSS error at %s: %s",
                         section.to_string (), e.message);
            });
            load_css ();
        }

        private void load_css () {
            var user_css = File.new_for_path (
                Path.build_filename (Environment.get_user_config_dir (),
                                     "way-shell", CSS_FILENAME));

            if (user_css.query_exists ()) {
                provider.load_from_file (user_css);
            } else {
                provider.load_from_resource (CSS_RESOURCE);
            }

            var display = Gdk.Display.get_default ();
            if (display != null) {
                StyleContext.add_provider_for_display (
                    display, provider, Gtk.STYLE_PROVIDER_PRIORITY_THEME);
            }
        }
    }
}

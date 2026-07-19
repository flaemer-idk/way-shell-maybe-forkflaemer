using Gtk;

namespace WayShell.Services {
    public enum ThemeType {
        LIGHT, DARK
    }

    public class ThemeService : GLib.Object {
        private static ThemeService? global = null;

        private GLib.Settings settings;
        private CssProvider provider;

        public signal void theme_changed(ThemeType theme);

        public static ThemeService get_global() {
            if (global == null) {
                global = new ThemeService();
            }
            return global;
        }

        private ThemeService() {
            // Изменено на org.flaemer.way-shell.system
            settings = new GLib.Settings("org.flaemer.way-shell.system");
            provider = new CssProvider();

            apply_theme_state();
            settings.changed["light-theme"].connect(apply_theme_state);
        }

        private void apply_theme_state() {
            bool is_light = settings.get_boolean("light-theme");
            if (is_light) {
                // Изменен путь ресурса на /org/flaemer/
                load_css("way-shell-light.css", "/org/flaemer/way-shell/data/theme/way-shell-light.css");
                theme_changed(ThemeType.LIGHT);
            } else {
                // Изменен путь ресурса на /org/flaemer/
                load_css("way-shell-dark.css", "/org/flaemer/way-shell/data/theme/way-shell-dark.css");
                theme_changed(ThemeType.DARK);
            }
            trigger_script_async(is_light ? "light" : "dark");
        }

        private void load_css(string filename, string resource_path) {
            var local_file = File.new_for_path(Path.build_filename(Environment.get_user_config_dir(), "way-shell", filename));
            if (local_file.query_exists()) {
                provider.load_from_file(local_file);
            } else {
                provider.load_from_resource(resource_path);
            }

            var display = Gdk.Display.get_default();
            if (display != null) {
                StyleContext.add_provider_for_display(display, provider, Gtk.STYLE_PROVIDER_PRIORITY_THEME);
            }
        }

        private void trigger_script_async(string mode) {
            string script = Path.build_filename(Environment.get_user_config_dir(), "way-shell", "on_theme_changed.sh");
            if (FileUtils.test(script, FileTest.EXISTS | FileTest.IS_EXECUTABLE)) {
                try {
                    string[] spawn_args = { "bash", "-c", "%s %s".printf(script, mode) };
                    Process.spawn_async(null, spawn_args, null, SpawnFlags.SEARCH_PATH, null, null);
                } catch (Error e) {
                    warning("ThemeService: Failed to execute script: %s", e.message);
                }
            }
        }

        public ThemeType get_theme() {
            return settings.get_boolean("light-theme") ? ThemeType.LIGHT : ThemeType.DARK;
        }
    }
}
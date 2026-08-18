// Путь: src/main.vala
using Gtk;
using Adw;
using WayShell.Services;
using WayShell.Panel;

extern GLib.Resource gresources_get_resource();

public class WayShellApp : Adw.Application {
    private Adw.ApplicationWindow global_window;

    public WayShellApp() {
        Object(application_id: "org.flaemer.way-shell", flags: ApplicationFlags.DEFAULT_FLAGS);
    }

    protected override void activate() {
        var resource = gresources_get_resource();
        GLib.resources_register(resource);
        
        global_window = new Adw.ApplicationWindow(this);
        add_window(global_window);

        // Инициализация синглтонов глобальных служб
        ClockService.get_global();
        BrightnessService.get_global();
        ThemeService.get_global();
        IpcService.get_global();
        NiriClient.get_global();
        NotificationsService.get_global();

        // Инициализация MessageTray на старте гарантирует, что список уведомлений сразу слушает D-Bus
        MessageTray.get_global();

        // Инициализация графических оверлеев
        WayShell.Osd.Osd.get_global();

        // Запуск интерфейса панелей на мониторах
        Panel.activate_subsystem(this);
    }

    public static int main(string[] args) {
        var app = new WayShellApp();
        return app.run(args);
    }
}
using Gtk;
using Adw;
using WayShell.Services;
using WayShell.Panel;

extern GLib.Resource gresources_get_resource();

public class WayShellApp : Adw.Application {
    public WayShellApp() {
        Object(application_id: "org.flaemer.way-shell", flags: ApplicationFlags.DEFAULT_FLAGS);
    }

    protected override void activate() {
        var resource = gresources_get_resource();
        GLib.resources_register(resource);

        // Оболочка живёт на layer-shell окнах, которые не принадлежат GApplication.
        // hold() не даёт приложению завершиться без фиктивного окна.
        this.hold();
        Adw.StyleManager.get_default().color_scheme = Adw.ColorScheme.FORCE_DARK;

        // Инициализация синглтонов глобальных служб
        ClockService.get_global();
        BrightnessService.get_global();
        ThemeService.get_global();
        IpcService.get_global();
        NotificationsService.get_global();

        // Трей поднимаем до панелей: приложения регистрируются в watcher сразу,
        // как он появился на шине, и ждать создания виджета не будут. Ключ
        // проверяем здесь же — владеть org.kde.StatusNotifierWatcher, ничего не
        // показывая, хуже, чем не владеть совсем: другой трей уже не поднимется.
        var panel_settings = new GLib.Settings("org.flaemer.way-shell.panel");
        if (panel_settings.get_boolean("enable-tray-icons")) {
            StatusNotifierService.get_global();
        }

        // Инициализация MessageTray на старте
        MessageTray.get_global();

        // Инициализация графических оверлеев и баннеров уведомлений
        WayShell.Osd.Osd.get_global();
        WayShell.Osd.NotificationBanner.get_global(); 

        // Запуск интерфейса панелей на мониторах
        Panel.activate_subsystem(this);

        // Связываем шторку/трей/OSD: взаимное скрытие и подсветка кнопок панели.
        // Вызывать после activate_subsystem: hide_all_except ходит по get_all_panels().
        Mediator.get_global().connect_signals();
    }
    public static int main(string[] args) {
        // Язык берётся из локали пользователя (LANG/LC_MESSAGES) — своего
        // переключателя у оболочки нет и не нужно.
        Intl.setlocale(LocaleCategory.ALL, "");

        // При запуске из build-каталога установленных переводов ещё нет,
        // поэтому путь можно перекрыть — так же, как схема через GSETTINGS_SCHEMA_DIR.
        string? localedir = Environment.get_variable("WAY_SHELL_LOCALEDIR");
        if (localedir == null || localedir == "") localedir = Config.LOCALEDIR;

        Intl.bindtextdomain(Config.GETTEXT_PACKAGE, localedir);
        Intl.bind_textdomain_codeset(Config.GETTEXT_PACKAGE, "UTF-8");
        Intl.textdomain(Config.GETTEXT_PACKAGE);

        var app = new WayShellApp();
        return app.run(args);
    }
}
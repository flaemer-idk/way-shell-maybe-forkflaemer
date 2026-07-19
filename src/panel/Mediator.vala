using GLib;
using WayShell.Services; 

namespace WayShell.Panel {
    public class Mediator : GLib.Object {
        private static Mediator? global = null;

        public static Mediator get_global() {
            if (global == null) {
                global = new Mediator();
            }
            return global;
        }

public void connect_signals() {
    var mt = MessageTray.get_global();
    // Изменен путь к Drawer
    var qs = WayShell.QS.Drawer.get_global();

    mt.visible.connect(() => {
        hide_all_except(mt);
        foreach (var panel in Panel.get_all_panels().get_values()) {
            panel.on_msg_tray_visible();
        }
    });

    mt.hidden.connect(() => {
        foreach (var panel in Panel.get_all_panels().get_values()) {
            panel.on_msg_tray_hidden();
        }
    });

    qs.visible.connect(() => {
        hide_all_except(qs);
        foreach (var panel in Panel.get_all_panels().get_values()) {
            panel.on_qs_visible();
        }
    });

    qs.hidden.connect(() => {
        foreach (var panel in Panel.get_all_panels().get_values()) {
            panel.on_qs_hidden();
        }
    });
}

private void hide_all_except(GLib.Object active_component) {
    var mt = MessageTray.get_global();
    // Изменен путь к Drawer
    var qs = WayShell.QS.Drawer.get_global();

    if (active_component != mt) mt.set_hidden();
    if (active_component != qs) qs.set_hidden();

    // Изменен вызов Osd синглтона с корректным регистром имени класса
    WayShell.Osd.Osd.get_global().set_hidden();
}
    }
}
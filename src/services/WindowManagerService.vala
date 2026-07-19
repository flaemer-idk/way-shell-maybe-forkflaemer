namespace WayShell.Services {
    public class WMWorkspace : GLib.Object {
        public string name { get; set; }
        public string output { get; set; }
        public bool focused { get; set; }
        public bool urgent { get; set; }

        public WMWorkspace (string name, string output, bool focused, bool urgent) {
            this.name = name;
            this.output = output;
            this.focused = focused;
            this.urgent = urgent;
        }
    }

    public delegate void WorkspacesChangedCallback (GenericArray<WMWorkspace> workspaces);

    public class WindowManagerService : GLib.Object {
        private static WindowManagerService? global = null;
        private GenericArray<WMWorkspace> workspaces;
        private WorkspacesChangedCallback? callback = null;

        public static WindowManagerService get_global () {
            if (global == null) {
                global = new WindowManagerService ();
            }
            return global;
        }

        private WindowManagerService () {
            workspaces = new GenericArray<WMWorkspace> ();
            workspaces.add (new WMWorkspace ("1", "eDP-1", true, false));
            workspaces.add (new WMWorkspace ("2", "eDP-1", false, false));

            var niri = NiriClient.get_global ();
            if (niri != null) {
                niri.workspaces_changed.connect (on_niri_workspaces_changed);
            }
        }

        private void on_niri_workspaces_changed (GenericArray<WMWorkspace> updated) {
            this.workspaces = updated;
            if (callback != null) {
                callback (workspaces);
            }
        }

        public GenericArray<WMWorkspace> get_workspaces () {
            return workspaces;
        }

        public void focus_workspace (WMWorkspace ws) {
            var niri = NiriClient.get_global ();
            if (niri != null) {
                niri.focus_workspace (ws);
            }
        }

        public void register_on_workspaces_changed (WorkspacesChangedCallback cb, GLib.Object owner) {
            this.callback = cb;
            cb (workspaces);
        }
    }
}
namespace WayShell.Wayland {

    [CCode (has_target = false)]
    public delegate void ZwlrGammaControlV1GammaSizeDelegate (void* data, ZwlrGammaControlV1 obj, uint32 size);
    [CCode (has_target = false)]
    public delegate void ZwlrGammaControlV1FailedDelegate (void* data, ZwlrGammaControlV1 obj);

    [Compact]
    [CCode (cheader_filename = "wlr-gamma-control-unstable-v1.h", cname = "struct zwlr_gamma_control_v1", free_function = "zwlr_gamma_control_v1_destroy", has_typedef = false)]
    public class ZwlrGammaControlV1 {
        [CCode (cname = "zwlr_gamma_control_v1_set_gamma")]
        public void set_gamma (int32 fd);

        [CCode (cname = "zwlr_gamma_control_v1_destroy")]
        public void destroy ();
    }

    [CCode (cheader_filename = "wlr-gamma-control-unstable-v1.h", cname = "struct zwlr_gamma_control_v1_listener", has_typedef = false)]
    public struct ZwlrGammaControlV1Listener {
        public ZwlrGammaControlV1GammaSizeDelegate gamma_size;
        public ZwlrGammaControlV1FailedDelegate failed;
    }

    [CCode (cheader_filename = "wlr-gamma-control-unstable-v1.h", cname = "zwlr_gamma_control_v1_add_listener")]
    public static int zwlr_gamma_control_v1_add_listener (ZwlrGammaControlV1 obj, ZwlrGammaControlV1Listener* listener, void* data);


    [Compact]
    [CCode (cheader_filename = "wlr-gamma-control-unstable-v1.h", cname = "struct zwlr_gamma_control_manager_v1", free_function = "zwlr_gamma_control_manager_v1_destroy", has_typedef = false)]
    public class ZwlrGammaControlManagerV1 {
        [CCode (cname = "zwlr_gamma_control_manager_v1_get_gamma_control")]
        public ZwlrGammaControlV1 get_gamma_control (GLib.Object output);

        [CCode (cname = "zwlr_gamma_control_manager_v1_destroy")]
        public void destroy ();
    }


    [CCode (has_target = false)]
    public delegate void ZwlrForeignToplevelHandleV1TitleDelegate (void* data, ZwlrForeignToplevelHandleV1 obj, string title);
    [CCode (has_target = false)]
    public delegate void ZwlrForeignToplevelHandleV1AppIdDelegate (void* data, ZwlrForeignToplevelHandleV1 obj, string app_id);
    [CCode (has_target = false)]
    public delegate void ZwlrForeignToplevelHandleV1OutputEnterDelegate (void* data, ZwlrForeignToplevelHandleV1 obj, GLib.Object output);
    [CCode (has_target = false)]
    public delegate void ZwlrForeignToplevelHandleV1OutputLeaveDelegate (void* data, ZwlrForeignToplevelHandleV1 obj, GLib.Object output);
    [CCode (has_target = false)]
    public delegate void ZwlrForeignToplevelHandleV1StateDelegate (void* data, ZwlrForeignToplevelHandleV1 obj, void* state);
    [CCode (has_target = false)]
    public delegate void ZwlrForeignToplevelHandleV1DoneDelegate (void* data, ZwlrForeignToplevelHandleV1 obj);
    [CCode (has_target = false)]
    public delegate void ZwlrForeignToplevelHandleV1ClosedDelegate (void* data, ZwlrForeignToplevelHandleV1 obj);
    [CCode (has_target = false)]
    public delegate void ZwlrForeignToplevelHandleV1ParentDelegate (void* data, ZwlrForeignToplevelHandleV1 obj, ZwlrForeignToplevelHandleV1 parent);

    [Compact]
    [CCode (cheader_filename = "wlr-foreign-toplevel-management-unstable-v1.h", cname = "struct zwlr_foreign_toplevel_handle_v1", free_function = "zwlr_foreign_toplevel_handle_v1_destroy", has_typedef = false)]
    public class ZwlrForeignToplevelHandleV1 {
        [CCode (cname = "zwlr_foreign_toplevel_handle_v1_set_maximized")]
        public void set_maximized ();

        [CCode (cname = "zwlr_foreign_toplevel_handle_v1_unset_maximized")]
        public void unset_maximized ();

        [CCode (cname = "zwlr_foreign_toplevel_handle_v1_set_minimized")]
        public void set_minimized ();

        [CCode (cname = "zwlr_foreign_toplevel_handle_v1_unset_minimized")]
        public void unset_minimized ();

        [CCode (cname = "zwlr_foreign_toplevel_handle_v1_activate")]
        public void activate (GLib.Object seat);

        [CCode (cname = "zwlr_foreign_toplevel_handle_v1_close")]
        public void close ();

        [CCode (cname = "zwlr_foreign_toplevel_handle_v1_destroy")]
        public void destroy ();
    }

    [CCode (cheader_filename = "wlr-foreign-toplevel-management-unstable-v1.h", cname = "struct zwlr_foreign_toplevel_handle_v1_listener", has_typedef = false)]
    public struct ZwlrForeignToplevelHandleV1Listener {
        public ZwlrForeignToplevelHandleV1TitleDelegate title;
        public ZwlrForeignToplevelHandleV1AppIdDelegate app_id;
        public ZwlrForeignToplevelHandleV1OutputEnterDelegate output_enter;
        public ZwlrForeignToplevelHandleV1OutputLeaveDelegate output_leave;
        public ZwlrForeignToplevelHandleV1StateDelegate state;
        public ZwlrForeignToplevelHandleV1DoneDelegate done;
        public ZwlrForeignToplevelHandleV1ClosedDelegate closed;
        public ZwlrForeignToplevelHandleV1ParentDelegate parent;
    }

    [CCode (cheader_filename = "wlr-foreign-toplevel-management-unstable-v1.h", cname = "zwlr_foreign_toplevel_handle_v1_add_listener")]
    public static int zwlr_foreign_toplevel_handle_v1_add_listener (ZwlrForeignToplevelHandleV1 obj, ZwlrForeignToplevelHandleV1Listener* listener, void* data);


    [CCode (has_target = false)]
    public delegate void ZwlrForeignToplevelManagerV1ToplevelDelegate (void* data, ZwlrForeignToplevelManagerV1 manager, ZwlrForeignToplevelHandleV1 toplevel);
    [CCode (has_target = false)]
    public delegate void ZwlrForeignToplevelManagerV1FinishedDelegate (void* data, ZwlrForeignToplevelManagerV1 manager);

    [Compact]
    [CCode (cheader_filename = "wlr-foreign-toplevel-management-unstable-v1.h", cname = "struct zwlr_foreign_toplevel_manager_v1", free_function = "zwlr_foreign_toplevel_manager_v1_destroy", has_typedef = false)]
    public class ZwlrForeignToplevelManagerV1 {
        [CCode (cname = "zwlr_foreign_toplevel_manager_v1_destroy")]
        public void destroy ();
    }

    [CCode (cheader_filename = "wlr-foreign-toplevel-management-unstable-v1.h", cname = "struct zwlr_foreign_toplevel_manager_v1_listener", has_typedef = false)]
    public struct ZwlrForeignToplevelManagerV1Listener {
        public ZwlrForeignToplevelManagerV1ToplevelDelegate toplevel;
        public ZwlrForeignToplevelManagerV1FinishedDelegate finished;
    }

    [CCode (cheader_filename = "wlr-foreign-toplevel-management-unstable-v1.h", cname = "zwlr_foreign_toplevel_manager_v1_add_listener")]
    public static int zwlr_foreign_toplevel_manager_v1_add_listener (ZwlrForeignToplevelManagerV1 obj, ZwlrForeignToplevelManagerV1Listener* listener, void* data);
}
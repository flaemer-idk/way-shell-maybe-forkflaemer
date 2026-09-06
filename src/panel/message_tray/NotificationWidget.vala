using Gtk;
using Adw;
using GLib;

namespace WayShell.Panel {
    public class NotificationWidget : Box {
        public uint32 id;
        public Box container;

        private Image app_icon;
        private Label app_name_label;
        private Label timer_label;
        private Button dismiss_btn;
        private Button expand_btn;

        private Image main_icon;

        private Box text_area;
        private Label summary_label;
        private Label body_label;

        private int64 created_time_us;
        private bool expanded = false;
        private uint timer_id = 0;

        public signal void collapsed();
        public signal void expanded_signal();
        public signal void activated();

        public NotificationWidget(Services.Notification n, bool is_osd = false) {
            Object(orientation: Orientation.VERTICAL, spacing: 0);
            this.id = n.id;
            // Монотонное время: устраняет баг с "4h ago" и часовыми поясами
            this.created_time_us = GLib.get_monotonic_time();
            this.hexpand = true;

            this.add_css_class("notification-widget-container");
            this.set_size_request(-1, -1);

            container = new Box(Orientation.VERTICAL, 4);
            container.add_css_class("card");
            container.add_css_class("notification-widget");
            container.hexpand = true;
            container.margin_top = 2;
            container.margin_bottom = 2;

            var inner = new Box(Orientation.VERTICAL, 4);
            inner.margin_top = 8;
            inner.margin_bottom = 8;
            inner.margin_start = 10;
            inner.margin_end = 10;
            inner.hexpand = true;

            // --- 1. Шапка ---
            var header = new CenterBox();
            header.add_css_class("notification-widget-header");

            var header_left = new Box(Orientation.HORIZONTAL, 6);
            header_left.valign = Align.CENTER;
            app_icon = new Image();
            app_icon.pixel_size = 16;
            app_icon.halign = Align.START;

            app_name_label = new Label(n.app_name);
            app_name_label.add_css_class("dim-label");
            app_name_label.add_css_class("caption");
            app_name_label.valign = Align.CENTER;
            app_name_label.ellipsize = Pango.EllipsizeMode.END;
            app_name_label.width_chars = 1;
            app_name_label.max_width_chars = 16;
            app_name_label.xalign = 0.0f;

            timer_label = new Label(_("Just now"));
            timer_label.add_css_class("dim-label");
            timer_label.add_css_class("caption");
            timer_label.valign = Align.CENTER;

            header_left.append(app_icon);
            header_left.append(app_name_label);
            header_left.append(timer_label);

            var header_right = new Box(Orientation.HORIZONTAL, 2);
            header_right.valign = Align.CENTER;

            expand_btn = new Button.from_icon_name("go-down-symbolic");
            expand_btn.add_css_class("circular");
            expand_btn.add_css_class("flat");
            // Кнопки только с иконкой — без меток скринридер не скажет, что это.
            expand_btn.tooltip_text = _("Expand notification");
            expand_btn.update_property(Gtk.AccessibleProperty.LABEL, _("Expand notification"), -1);
            expand_btn.update_state(Gtk.AccessibleState.EXPANDED, false, -1);
            expand_btn.clicked.connect(on_expand_clicked);
            expand_btn.visible = !is_osd;

            dismiss_btn = new Button.from_icon_name("window-close-symbolic");
            dismiss_btn.add_css_class("circular");
            dismiss_btn.add_css_class("flat");
            dismiss_btn.tooltip_text = _("Dismiss notification");
            dismiss_btn.update_property(Gtk.AccessibleProperty.LABEL, _("Dismiss notification"), -1);
            dismiss_btn.clicked.connect(on_dismiss_clicked);

            header_right.append(expand_btn);
            header_right.append(dismiss_btn);

            header.set_start_widget(header_left);
            header.set_end_widget(header_right);
            inner.append(header);

            // --- 2. Тело уведомления ---
            var body_box = new Box(Orientation.HORIZONTAL, 0);
            body_box.hexpand = true;
            body_box.valign = Align.START;

            var btn_body = new Button();
            btn_body.add_css_class("flat");
            btn_body.clicked.connect(on_body_clicked);
            btn_body.hexpand = true;
            btn_body.valign = Align.START;

            var body_contents = new Box(Orientation.HORIZONTAL, 10);
            body_contents.margin_top = 2;
            body_contents.margin_bottom = 2;
            body_contents.hexpand = true;
            body_contents.valign = Align.START;

            // Настоящая GTK иконка без красных кругов Adw.Avatar
            main_icon = new Image();
            main_icon.pixel_size = 38;
            main_icon.valign = Align.START;
            body_contents.append(main_icon);

            text_area = new Box(Orientation.VERTICAL, 2);
            text_area.valign = Align.START;
            text_area.hexpand = true;

            summary_label = new Label(n.summary);
            summary_label.add_css_class("heading");
            summary_label.halign = Align.START;
            summary_label.xalign = 0.0f;
            summary_label.wrap = true;
            summary_label.wrap_mode = Pango.WrapMode.WORD_CHAR;
            summary_label.lines = 1;
            summary_label.ellipsize = Pango.EllipsizeMode.END;
            summary_label.width_chars = 1;

            body_label = new Label("");
            body_label.add_css_class("body");
            body_label.halign = Align.START;
            body_label.xalign = 0.0f;
            body_label.wrap = true;
            body_label.wrap_mode = Pango.WrapMode.WORD_CHAR;
            body_label.lines = is_osd ? 2 : 1;
            body_label.ellipsize = Pango.EllipsizeMode.END;
            body_label.width_chars = 1;
            set_markup_safe(body_label, n.body);

            text_area.append(summary_label);
            text_area.append(body_label);
            body_contents.append(text_area);
            btn_body.set_child(body_contents);
            body_box.append(btn_body);

            inner.append(body_box);
            container.append(inner);

            timer_id = GLib.Timeout.add_seconds(10, update_timer);
            setup_icons(n);

            this.append(container);
        }

        // Без этого 10-секундный таймер жил вечно и держал ссылку на уже
        // удалённый виджет: за сессию с сотней уведомлений — сотня живых source.
        public override void dispose() {
            if (timer_id != 0) {
                GLib.Source.remove(timer_id);
                timer_id = 0;
            }
            base.dispose();
        }

        private void setup_icons(Services.Notification n) {
            var display = Gdk.Display.get_default();
            var icon_theme = Gtk.IconTheme.get_for_display(display);
            bool main_loaded = false;

            // 1. Сырые пиксели из D-Bus hints
            if (n.image_pixbuf != null) {
                var texture = Gdk.Texture.for_pixbuf(n.image_pixbuf);
                main_icon.set_from_paintable(texture);
                main_loaded = true;
            }
            // 2. Файл с диска
            else if (n.image_path != null && n.image_path != "") {
                main_loaded = load_image_to_icon(main_icon, n.image_path);
            }
            // 3. app_icon как путь к файлу
            else if (n.app_icon != null && (n.app_icon.has_prefix("/") || n.app_icon.has_prefix("file://"))) {
                main_loaded = load_image_to_icon(main_icon, n.app_icon);
            }
            // 4. app_icon в системной теме
            else if (n.app_icon != null && n.app_icon != "") {
                if (icon_theme.has_icon(n.app_icon)) {
                    main_icon.set_from_icon_name(n.app_icon);
                    main_loaded = true;
                } else {
                    main_loaded = check_pixmaps_fallback(main_icon, n.app_icon);
                }
            }

            // 5. Поиск по имени программы в .desktop файлах
            if (!main_loaded && n.app_name != "") {
                main_loaded = find_app_icon_by_name(main_icon, n.app_name, icon_theme);
            }

            // 6. Запасной значок
            if (!main_loaded) {
                main_icon.set_from_icon_name("preferences-system-notifications-symbolic");
            }

            setup_header_app_icon(n, icon_theme);
        }

        private bool load_image_to_icon(Image img, string path_or_uri) {
            try {
                string raw_path = path_or_uri.has_prefix("file://") ? path_or_uri.replace("file://", "") : path_or_uri;
                var file = File.new_for_path(raw_path);
                if (file.query_exists()) {
                    var texture = Gdk.Texture.from_file(file);
                    img.set_from_paintable(texture);
                    return true;
                }
            } catch (Error e) {}
            return false;
        }

        private bool check_pixmaps_fallback(Image img, string icon_name) {
            string[] extensions = { "", ".png", ".svg", ".xpm" };
            foreach (var ext in extensions) {
                string full = Path.build_filename("/usr/share/pixmaps", icon_name + ext);
                if (FileUtils.test(full, FileTest.EXISTS)) {
                    if (load_image_to_icon(img, full)) return true;
                }
            }
            return false;
        }

        private bool find_app_icon_by_name(Image img, string app_name, Gtk.IconTheme theme) {
            string name_lower = app_name.ascii_down();
            if (theme.has_icon(name_lower)) {
                img.set_from_icon_name(name_lower);
                return true;
            }

            var apps = GLib.AppInfo.get_all();
            foreach (var app in apps) {
                string app_id_lower = app.get_id() != null ? app.get_id().ascii_down() : "";
                string display_name_lower = app.get_name().ascii_down();

                if (display_name_lower == name_lower || app_id_lower.contains(name_lower)) {
                    var gicon = app.get_icon();
                    if (gicon != null) {
                        img.set_from_gicon(gicon);
                        return true;
                    }
                }
            }
            return false;
        }

        private void setup_header_app_icon(Services.Notification n, Gtk.IconTheme theme) {
            if (n.app_icon != null && n.app_icon != "" && !n.app_icon.has_prefix("/") && theme.has_icon(n.app_icon)) {
                app_icon.set_from_icon_name(n.app_icon);
                return;
            }

            if (n.app_name != "") {
                string name_lower = n.app_name.ascii_down();
                if (theme.has_icon(name_lower)) {
                    app_icon.set_from_icon_name(name_lower);
                    return;
                }
                if (find_app_icon_by_name(app_icon, n.app_name, theme)) {
                    return;
                }
            }

            app_icon.set_from_icon_name("preferences-system-notifications-symbolic");
        }

        private void set_markup_safe(Label label, string text) {
            // Markup.escape_text гарантирует валидный markup, поэтому set_markup не бросает.
            label.set_markup(Markup.escape_text(text));
        }

        private void on_expand_clicked() {
            expanded = !expanded;
            expand_btn.update_state(Gtk.AccessibleState.EXPANDED, expanded, -1);
            if (expanded) {
                expand_btn.set_icon_name("go-up-symbolic");
                expand_btn.tooltip_text = _("Collapse notification");
                expand_btn.update_property(Gtk.AccessibleProperty.LABEL,
                                           _("Collapse notification"), -1);
                // lines = 0: ВЫКЛЮЧАЕТ ВСЕ ЛИМИТЫ (текст идет вниз сколько угодно строк)
                body_label.lines = 0;
                body_label.ellipsize = Pango.EllipsizeMode.NONE;
                expanded_signal();
            } else {
                expand_btn.set_icon_name("go-down-symbolic");
                expand_btn.tooltip_text = _("Expand notification");
                expand_btn.update_property(Gtk.AccessibleProperty.LABEL,
                                           _("Expand notification"), -1);
                body_label.lines = 1;
                body_label.ellipsize = Pango.EllipsizeMode.END;
                collapsed();
            }
        }

        private void on_dismiss_clicked() {
            var ns = Services.NotificationsService.get_global();
            ns.closed_notification(id, 2);
        }

        private void on_body_clicked() {
            var ns = Services.NotificationsService.get_global();
            ns.invoke_action(id, "default");
            activated();
        }

        private bool update_timer() {
            int64 elapsed_sec = (GLib.get_monotonic_time() - created_time_us) / 1000000;
            if (elapsed_sec < 60) {
                timer_label.set_text(_("Just now"));
            } else if (elapsed_sec < 3600) {
                timer_label.set_text(_("%ldm ago").printf((long) (elapsed_sec / 60)));
            } else {
                timer_label.set_text(_("%ldh ago").printf((long) (elapsed_sec / 3600)));
            }
            return true;
        }
    }
}
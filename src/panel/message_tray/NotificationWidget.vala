using Gtk;
using Adw;

namespace WayShell.Panel {
    public class NotificationWidget : Box {
        public uint32 id;
        public Box container;

        private Image app_icon;
        private Label app_name_label;
        private Label timer_label;
        private Button dismiss_btn;
        private Button expand_btn;

        private Avatar avatar;
        private Box text_area;
        private Label summary_label;
        private Label body_label;

        private DateTime created_on;
        private bool expanded = false;
        private Adw.Animation expand_anim;
        private uint timer_id = 0;

        public signal void collapsed();
        public signal void expanded_signal();
        public signal void activated();

        public NotificationWidget(Services.Notification n, bool is_osd = false) {
            Object(orientation: Orientation.VERTICAL, spacing: 0);
            this.id = n.id;
            this.created_on = n.created_on;

            this.add_css_class("notification-widget-container");
            this.set_size_request(400, 120);

            container = new Box(Orientation.VERTICAL, 0);
            container.add_css_class("notification-widget");

            // Шапка карточки
            var header = new CenterBox();
            header.add_css_class("notification-widget-header");

            var header_left = new Box(Orientation.HORIZONTAL, 0);
            header_left.valign = Align.CENTER;
            app_icon = new Image();
            app_icon.pixel_size = 18;
            app_icon.add_css_class("notification-widget-icon");
            app_icon.halign = Align.START;

            app_name_label = new Label(n.app_name);
            app_name_label.add_css_class("notification-widget-app-name");
            app_name_label.valign = Align.CENTER;

            timer_label = new Label("Just now");
            timer_label.add_css_class("notification-widget-timer");
            timer_label.valign = Align.END;

            header_left.append(app_icon);
            header_left.append(app_name_label);
            header_left.append(timer_label);

            var header_right = new Box(Orientation.HORIZONTAL, 0);
            header_right.valign = Align.CENTER;

            expand_btn = new Button.from_icon_name("go-down-symbolic");
            expand_btn.add_css_class("circular");
            expand_btn.add_css_class("notification-widget-expand-button");
            expand_btn.clicked.connect(on_expand_clicked);
            expand_btn.visible = !is_osd;

            dismiss_btn = new Button();
            dismiss_btn.set_child(new Image.from_icon_name("window-close-symbolic"));
            dismiss_btn.add_css_class("circular");
            dismiss_btn.add_css_class("notification-widget-dismiss-button");
            dismiss_btn.clicked.connect(on_dismiss_clicked);

            header_right.append(expand_btn);
            header_right.append(dismiss_btn);

            header.set_start_widget(header_left);
            header.set_end_widget(header_right);

            // Тело уведомления
            var body_box = new Box(Orientation.HORIZONTAL, 0);
            var btn_body = new Button();
            btn_body.add_css_class("notification-widget-button");
            btn_body.clicked.connect(on_body_clicked);

            var body_contents = new Box(Orientation.HORIZONTAL, 0);
            avatar = new Avatar(48, "", false);
            avatar.add_css_class("notification-widget-icon");
            avatar.set_icon_name("preferences-system-notifications-symbolic");
            avatar.valign = Align.START;

            text_area = new Box(Orientation.VERTICAL, 0);
            text_area.valign = Align.CENTER;

            summary_label = new Label(n.summary);
            summary_label.add_css_class("summary");
            summary_label.halign = Align.START;
            summary_label.ellipsize = Pango.EllipsizeMode.END;
            summary_label.max_width_chars = 40;
            summary_label.xalign = 0.0f;

            body_label = new Label("");
            body_label.add_css_class("body");
            body_label.halign = Align.START;
            body_label.ellipsize = Pango.EllipsizeMode.END;
            body_label.max_width_chars = 200;
            body_label.xalign = 0.0f;
            body_label.lines = 1;
            body_label.wrap = true;
            set_markup_safe(body_label, n.body);

            text_area.append(summary_label);
            text_area.append(body_label);
            body_contents.append(avatar);
            body_contents.append(text_area);
            btn_body.set_child(body_contents);
            body_box.append(btn_body);

            container.append(header);
            container.append(body_box);

            // Анимация раскрытия подробностей
            var target = new Adw.CallbackAnimationTarget((value) => {
                body_label.lines = (int)value;
            });
            expand_anim = new Adw.TimedAnimation(body_label, 1.0, 10.0, 200, target);
            expand_anim.done.connect(() => {
                var timed_anim = (Adw.TimedAnimation)expand_anim;
                if (timed_anim.get_reverse()) {
                    collapsed();
                } else {
                    expanded_signal();
                }
            });

            timer_id = GLib.Timeout.add_seconds(60, update_timer);
            setup_icons(n);

            this.append(container);
        }

        private void setup_icons(Services.Notification n) {
            if (n.app_icon != null && n.app_icon != "") {
                avatar.set_icon_name(n.app_icon);
                app_icon.set_from_icon_name(n.app_icon);
            }
        }

        private void set_markup_safe(Label label, string text) {
            string escaped = Markup.escape_text(text);
            try {
                label.set_markup(escaped);
            } catch (Error e) {
                label.set_text(text);
            }
        }

        private void on_expand_clicked() {
            var timed_anim = (Adw.TimedAnimation)expand_anim;
            if (expanded) {
                expand_btn.set_icon_name("go-down-symbolic");
                timed_anim.set_reverse(true);
            } else {
                expand_btn.set_icon_name("go-up-symbolic");
                timed_anim.set_reverse(false);
            }
            expand_anim.play();
            expanded = !expanded;
        }

        private void on_dismiss_clicked() {
            // Закрываем/удаляем уведомление ТОЛЬКО по крестику
            var ns = Services.NotificationsService.get_global();
            ns.closed_notification(id, 2);
        }

        private void on_body_clicked() {
            // При нажатии на текст/тело только вызываем действие приложения (уведомление остается в списке)
            var ns = Services.NotificationsService.get_global();
            ns.invoke_action(id, "default");
            activated();
        }

        private bool update_timer() {
            var now = new DateTime.now_local();
            var span = now.difference(created_on);
            int64 minutes = span / TimeSpan.MINUTE;
            if (minutes == 0) {
                timer_label.set_text("Just now");
            } else if (minutes < 60) {
                // Приведение типов к long
                timer_label.set_text("%ldm ago".printf((long) minutes));
            } else {
                // Приведение типов к long
                timer_label.set_text("%ldh ago".printf((long) (minutes / 60)));
            }
            return true;
        }
        
        public void set_stack_effect(bool show) {
            expand_btn.visible = !show;
        }
    }
}
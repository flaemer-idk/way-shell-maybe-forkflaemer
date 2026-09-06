using Gtk;

namespace WayShell.Panel {
    public class CalendarWidget : Box {
        private DateTime now;
        private bool dirty = false;
        private Calendar calendar;
        private Button today_btn;
        private Adw.ActionRow today_row;

        private CenterBox month_selector;
        private Button btn_back;
        private Button btn_forward;
        private Label date_label;

        public CalendarWidget() {
            Object(orientation: Orientation.VERTICAL, spacing: 0);
            this.add_css_class("calendar-area");

            now = new DateTime.now_local();

            // Панель выбора месяца
            month_selector = new CenterBox();
            month_selector.name = "calendar-month-selector";
            
            btn_back = new Button();
            btn_back.set_child(new Image.from_icon_name("pan-start-symbolic"));
            btn_back.tooltip_text = _("Previous month");
            btn_back.update_property(Gtk.AccessibleProperty.LABEL, _("Previous month"), -1);
            btn_back.clicked.connect(on_back_clicked);

            btn_forward = new Button();
            btn_forward.set_child(new Image.from_icon_name("pan-end-symbolic"));
            btn_forward.tooltip_text = _("Next month");
            btn_forward.update_property(Gtk.AccessibleProperty.LABEL, _("Next month"), -1);
            btn_forward.clicked.connect(on_forward_clicked);

            date_label = new Label(now.format("%B %Y"));

            month_selector.set_start_widget(btn_back);
            month_selector.set_center_widget(date_label);
            month_selector.set_end_widget(btn_forward);

            // Календарная сетка GTK
            calendar = new Calendar();
            calendar.set_size_request(-1, 224);
            calendar.show_heading = false;
            calendar.show_week_numbers = false;
            calendar.hexpand = true;
            calendar.day_selected.connect(on_day_selected);

            // Кнопка быстрого возврата к «Сегодня»
            today_btn = new Button();
            today_btn.name = "calendar-today";
            today_btn.hexpand = true;
            today_btn.tooltip_text = _("Go to today");
            today_btn.update_property(Gtk.AccessibleProperty.LABEL, _("Go to today"), -1);
            today_btn.clicked.connect(on_today_clicked);

            today_row = new Adw.ActionRow();
            today_btn.set_child(today_row);

            this.append(today_btn);
            this.append(month_selector);
            this.append(calendar);

            var cs = Services.ClockService.get_global();
            cs.tick.connect(on_clock_tick);

            update_today_row(now);
        }

        private void on_clock_tick(Services.ClockService cs, DateTime tick_now) {
            if (tick_now.get_day_of_year() == now.get_day_of_year()) return;
            now = tick_now;
            update_today_row(now);
            update_dirty_state();
        }

        private void update_today_row(DateTime dt) {
            today_row.title = dt.format("%A");
            today_row.subtitle = dt.format("%B %d %Y");
            date_label.set_text(dt.format("%B %Y"));
        }

        private void on_back_clicked() {
            var current = calendar.get_date();
            var next = current.add_months(-1);
            calendar.select_day(next);
            update_dirty_state();
        }

        private void on_forward_clicked() {
            var current = calendar.get_date();
            var next = current.add_months(1);
            calendar.select_day(next);
            update_dirty_state();
        }

        private void on_day_selected() {
            var current = calendar.get_date();
            date_label.set_text(current.format("%B %Y"));
            update_dirty_state();
        }

        private void on_today_clicked() {
            if (dirty) {
                calendar.select_day(now);
                date_label.set_text(now.format("%B %Y"));
                calendar.clear_marks();
            }
            update_dirty_state();
        }

        private void update_dirty_state() {
            var current = calendar.get_date();
            if (current.get_month() == now.get_month() && 
                current.get_year() == now.get_year() && 
                current.get_day_of_month() == now.get_day_of_month()) {
                today_btn.remove_css_class("calendar-today-dirty");
                dirty = false;
            } else {
                today_btn.add_css_class("calendar-today-dirty");
                dirty = true;
            }
        }
    }
}
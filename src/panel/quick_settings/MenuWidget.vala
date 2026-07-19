using Gtk;

namespace WayShell.QS {
    public class MenuWidget : Box {
        public Box options_container;
        public Box title_container;
        public Label title_label;
        public Revealer banner;
        public Box title_icon_container;
        public Image icon;
        public Box options;
        public ScrolledWindow? scroll;

        public MenuWidget(string title, string icon_name, bool scrolling = false) {
            Object(orientation: Orientation.VERTICAL, spacing: 0);
            this.name = "quick-settings-menu";
            this.vexpand = true;

            options_container = new Box(Orientation.VERTICAL, 0);
            options_container.name = "container";
            options_container.vexpand = true;

            title_container = new Box(Orientation.HORIZONTAL, 0);
            title_container.name = "title-container";

            title_icon_container = new Box(Orientation.HORIZONTAL, 0);
            title_icon_container.name = "icon-container";
            
            icon = new Image.from_icon_name(icon_name);
            icon.pixel_size = 24;

            title_icon_container.append(icon);
            title_container.append(title_icon_container);
            
            title_label = new Label(title);
            title_container.append(title_label);

            banner = new Revealer();
            banner.name = "banner";
            banner.transition_type = RevealerTransitionType.SLIDE_DOWN;
            banner.transition_duration = 250;

            options = new Box(Orientation.VERTICAL, 0);
            options.name = "options-container";

            options_container.append(title_container);
            options_container.append(banner);

            if (scrolling) {
                scroll = new ScrolledWindow();
                scroll.vexpand = true;
                scroll.set_child(options);
                scroll.set_policy(PolicyType.NEVER, PolicyType.AUTOMATIC);
                options_container.append(scroll);
            } else {
                options_container.append(options);
            }

            this.append(options_container);
        }
    }
}
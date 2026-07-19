namespace WayShell.Services {
    public class MediaPlayer : GLib.Object {
        public string? artist { get; set; }
        public string? title { get; set; }

        public MediaPlayer (string? artist, string? title) {
            this.artist = artist;
            this.title = title;
        }
    }

    public class MediaPlayerService : GLib.Object {
        private static MediaPlayerService? global = null;

        public signal void media_player_changed (MediaPlayer player);

        public static MediaPlayerService get_global () {
            if (global == null) {
                global = new MediaPlayerService ();
            }
            return global;
        }

        private MediaPlayerService () {}
    }
}
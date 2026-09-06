using GLib;

namespace WayShell.Services {
    // Индикатор «камера используется».
    //
    // Раньше это жило в Panel: Timeout.add(1000) на каждый монитор, внутри
    // File.read("/dev/video0") с расчётом поймать IOError.BUSY. Не работало
    // вообще: uvcvideo разрешает несколько одновременных open(), EBUSY приходит
    // только на VIDIOC_STREAMON, а не на открытии файла. Проверено на железе —
    // при работающем захвате три дополнительных open() проходят успешно.
    //
    // Почему inotify, а не PipeWire: через PipeWire ходят браузеры, OBS и
    // Flatpak-приложения, но v4l2 никуда не делся, и нативные приложения
    // открывают /dev/videoN напрямую. Проверено: `ffmpeg -f v4l2` захватывает
    // камеру, а нода PipeWire остаётся в состоянии suspended. Обратное неверно —
    // когда стримит сам PipeWire, он тоже делает open() на устройстве. То есть
    // inotify видит оба случая, а PipeWire только один.
    public class WebcamService : GLib.Object {
        // Сколько ждать перед показом иконки. wireplumber и udev-хелперы
        // открывают устройство на доли секунды, чтобы прочитать возможности;
        // без задержки иконка мигала бы на старте и на каждое переподключение.
        private const uint SHOW_DELAY_MS = 400;

        private static WebcamService? global = null;

        private int infd = -1;
        private uint io_watch = 0;
        private IOChannel? channel = null;
        // wd → путь устройства. Нужен только для отладочных сообщений: события
        // приходят с дескриптором наблюдения, а не с именем файла.
        private HashTable<int, string> watches;
        // Открытых дескрипторов по всем устройствам. Счётчик, а не bool: камеру
        // может держать несколько процессов одновременно.
        private int open_count = 0;
        private uint show_timer = 0;

        public bool in_use { get; private set; default = false; }

        // true, если в системе вообще есть камера. Panel по этому флагу решает,
        // создавать ли виджет: без камеры не нужен ни виджет, ни watch.
        public bool has_device {
            get { return watches.size() > 0; }
        }

        public static WebcamService get_global () {
            if (global == null) {
                global = new WebcamService ();
            }
            return global;
        }

        private WebcamService () {
            watches = new HashTable<int, string> (direct_hash, direct_equal);
            setup ();
        }

        ~WebcamService () {
            if (show_timer != 0) Source.remove (show_timer);
            if (io_watch != 0) Source.remove (io_watch);
            // channel закрывает infd сам: set_close_on_unref(true) ниже.
            channel = null;
        }

        private void setup () {
            var devices = find_devices ();
            if (devices.length == 0) {
                debug ("WebcamService: камер не найдено, индикатор отключён");
                return;
            }

            infd = Linux.inotify_init (Linux.InotifyFlags.NONBLOCK | Linux.InotifyFlags.CLOEXEC);
            if (infd < 0) {
                warning ("WebcamService: inotify_init не удался, индикатор отключён");
                return;
            }

            // IN_OPEN/IN_CLOSE_* на устройстве работают: события даёт VFS, а не
            // файловая система, поэтому devtmpfs не мешает.
            var mask = Linux.InotifyMaskFlags.OPEN
                     | Linux.InotifyMaskFlags.CLOSE_WRITE
                     | Linux.InotifyMaskFlags.CLOSE_NOWRITE;

            for (int i = 0; i < devices.length; i++) {
                string path = devices.get (i);
                int wd = Linux.inotify_add_watch (infd, path, mask);
                if (wd < 0) {
                    warning ("WebcamService: не удалось следить за %s", path);
                    continue;
                }
                watches.insert (wd, path);
                debug ("WebcamService: следим за %s (wd=%d)", path, wd);
            }

            if (watches.size () == 0) {
                Posix.close (infd);
                infd = -1;
                return;
            }

            // Кто-то мог открыть камеру до нашего старта: inotify такое не
            // покажет, поэтому первое состояние читаем через /proc.
            open_count = count_current_holders (devices);
            if (open_count > 0) in_use = true;

            channel = new IOChannel.unix_new (infd);
            try {
                // null-кодировка = сырые байты: в потоке лежат структуры, не текст.
                channel.set_encoding (null);
            } catch (IOChannelError e) {
                warning ("WebcamService: set_encoding: %s", e.message);
                channel = null;
                return;
            }
            channel.set_buffered (false);
            channel.set_close_on_unref (true);
            io_watch = channel.add_watch (IOCondition.IN, on_inotify_ready);
        }

        // /dev/video* — это и камеры, и метаданные, и radio/vbi-узлы. Берём все
        // video4linux-узлы: лишний watch дешевле пропущенного захвата.
        private GenericArray<string> find_devices () {
            var result = new GenericArray<string> ();
            try {
                var dir = Dir.open ("/sys/class/video4linux");
                string? name;
                while ((name = dir.read_name ()) != null) {
                    string dev = "/dev/" + name;
                    if (FileUtils.test (dev, FileTest.EXISTS)) result.add (dev);
                }
            } catch (Error e) {
                debug ("WebcamService: /sys/class/video4linux недоступен: %s", e.message);
            }
            return result;
        }

        // Считает процессы, уже держащие устройство открытым, по симлинкам в
        // /proc/<pid>/fd. Вызывается один раз на старте.
        private int count_current_holders (GenericArray<string> devices) {
            int count = 0;
            try {
                var proc = Dir.open ("/proc");
                string? pid;
                while ((pid = proc.read_name ()) != null) {
                    if (!pid[0].isdigit ()) continue;
                    string fd_dir = @"/proc/$pid/fd";
                    Dir fds;
                    try {
                        fds = Dir.open (fd_dir);
                    } catch (Error e) {
                        // Чужие процессы и те, что умерли между читениями.
                        continue;
                    }
                    string? fd;
                    while ((fd = fds.read_name ()) != null) {
                        try {
                            string target = FileUtils.read_link (@"$fd_dir/$fd");
                            for (int i = 0; i < devices.length; i++) {
                                if (target == devices.get (i)) {
                                    count++;
                                    break;
                                }
                            }
                        } catch (Error e) {
                            continue;
                        }
                    }
                }
            } catch (Error e) {
                debug ("WebcamService: /proc не читается: %s", e.message);
            }
            return count;
        }

        private bool on_inotify_ready (IOChannel source, IOCondition cond) {
            // Событий за одно чтение может быть несколько, поэтому читаем
            // сырым read() и разбираем буфер вручную: IOChannel.read_chars
            // на структурах фиксированного размера удобнее не делает.
            uint8 buf[4096];
            ssize_t got = Posix.read (infd, buf, buf.length);
            if (got <= 0) return true;

            size_t offset = 0;
            // sizeof(struct inotify_event) без хвоста name[].
            const size_t HEADER = 16;
            while (offset + HEADER <= (size_t) got) {
                uint32 mask = 0;
                uint32 len = 0;
                Memory.copy (&mask, (uint8*) buf + offset + 4, sizeof (uint32));
                Memory.copy (&len, (uint8*) buf + offset + 12, sizeof (uint32));

                if ((mask & Linux.InotifyMaskFlags.OPEN) != 0) {
                    open_count++;
                } else if ((mask & (Linux.InotifyMaskFlags.CLOSE_WRITE
                                  | Linux.InotifyMaskFlags.CLOSE_NOWRITE)) != 0) {
                    if (open_count > 0) open_count--;
                }

                offset += HEADER + len;
            }

            apply_state ();
            return true;
        }

        private void apply_state () {
            bool active = open_count > 0;
            if (active == in_use && show_timer == 0) return;

            if (!active) {
                // Закрытие показываем сразу: лучше убрать иконку мгновенно, чем
                // оставить «камера работает», когда она уже нет.
                if (show_timer != 0) {
                    Source.remove (show_timer);
                    show_timer = 0;
                }
                if (in_use) in_use = false;
                return;
            }

            if (in_use || show_timer != 0) return;

            show_timer = Timeout.add (SHOW_DELAY_MS, () => {
                show_timer = 0;
                // За время задержки устройство могли закрыть — короткая проба
                // возможностей выглядит именно так.
                if (open_count > 0) in_use = true;
                return Source.REMOVE;
            });
        }
    }
}

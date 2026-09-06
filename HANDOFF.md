# HANDOFF: way-shell (Vala-форк) — состояние работ

Форк [ldelossa/way-shell](https://github.com/ldelossa/way-shell), переписанный с C на Vala.
Окружение: NixOS, niri, GTK4 + libadwaita + gtk4-layer-shell.
Ветка `main`, последний коммит `5a7827c`. **Всё описанное ниже не закоммичено, лежит в рабочем дереве.**

Владелец проекта — flaemer. Отвечать ему по-русски.

**Документ сверен с кодом 2026-09-06.** Каждое утверждение проверено по файлам, а не
унаследовано из прежней версии. Раздел 1 — что сделано (с оговорками, где сделано
иначе), раздел 2 — что осталось.

Объём рабочего дерева относительно `5a7827c`: 57 изменённых файлов, +3677/−4275 строк,
плюс неотслеживаемые: `HANDOFF.md`, `data/meson.build`, `package.nix`, `po/`,
`src/services/BluetoothService.vala`, `src/services/WebcamService.vala`, `vapi/config.vapi`;
удалён `way-shell.nix`. `src/services/MediaPlayerService.vala` числится изменённым, а не
новым: файл с таким именем есть в коммите, но его содержимое полностью другое
(см. 1.13 и последний пункт раздела 5).

---

## 0. Сборка и проверка

`meson` и `valac` не на PATH, только через nix-shell:

```
nix-shell --run 'meson setup build --reconfigure && meson compile -C build'
```

Вывод C-компилятора зашумлён `-Wdiscarded-qualifiers` из glib-макросов атомиков и
`set but not used` из сгенерированных valac временных. Фильтр только на диагностику Vala:

```
nix-shell --run 'meson compile -C build 2>&1 | grep -E "^\.\./src/.*\.vala:[0-9]+\.[0-9]+-|error:|FAILED"'
```

Таймаут для nix-shell вызовов — не меньше 600000 мс.

Тулчейн (из вывода `meson setup`): meson 1.10.2, Vala 0.56.18, gcc 15.2.0, ninja 1.13.2,
GTK 4.22.4, libadwaita 1.9.3, gtk4-layer-shell 1.3.0, wireplumber 0.5.14, libnm 1.56.0.

**Каталог сборки должен называться `build`**, не `_build`: `shell.nix` экспортирует
`GSETTINGS_SCHEMA_DIR=$PWD/build/data` (строка 26), а `data/meson.build` компилирует схему
в `<builddir>/data/`. С `_build` схема не найдётся и `GLib.Settings` на отсутствующей схеме
вызовет `g_error` → abort.

Текущее состояние сборки: **чисто, одно неустранимое предупреждение**

```
../src/services/ThemeService.vala:42.17-42.28: warning: `Gtk.StyleContext' has been deprecated since 4.10
```

Проверено сборкой с нуля: ни `error:`, ни `FAILED`; бинарник `build/way-shell` собирается.

`gtk_style_context_add_provider_for_display` — единственный способ зарегистрировать
CSS-провайдер на весь дисплей в GTK4. Не трогать.

**Предупреждение libadwaita в логе запуска — не наш баг, чинится в системе.**
При каждом старте печатается:

```
Adwaita-WARNING: Using GtkSettings:gtk-application-prefer-dark-theme with libadwaita
is unsupported. Please use AdwStyleManager:color-scheme instead.
```

Это `warn_prefer_dark_theme()` из `adw-style-manager.c`. Срабатывает, когда свойство уже
`TRUE` на момент `adw_style_manager_constructed`, или по `notify::` от чужой записи; свои
записи libadwaita защищает флагом `changing_gtk_settings`. Причина у владельца найдена:
`gtk-application-prefer-dark-theme=1` лежит в **`~/.config/gtk-4.0/settings.ini` и
`~/.config/gtk-3.0/settings.ini`** (в `/etc/gtk-*/settings.ini` ключа нет). Код проекта тут
ни при чём: он делает правильно, `Adw.StyleManager.get_default().color_scheme = FORCE_DARK`
в `main.vala:20`.

На внешний вид не влияет: libadwaita ставит `gtk-theme-name = "Adwaita-empty"`, поднимает
свой провайдер на `PRIORITY_THEME` и переключает тему свойством `prefers-color-scheme`, то
есть старый флаг на стили не действует. Само предупреждение временное — в 1.9.3 весь блок
обёрнут в `if (gtk_check_version (4, 23, 1) != NULL)` (у владельца GTK 4.22.4, попадает), а
в `main` libadwaita функцию удалил: GTK deprecated это свойство в 4.20. Уйдёт само при
обновлении GTK или libadwaita.

Если захочется убрать раньше: `gsettings set org.gnome.desktop.interface color-scheme
prefer-dark` (портал у владельца работает, `AdwSettings` это читает), затем убрать ключ из
`gtk-4.0/settings.ini`. Ключ для `gtk-3.0` лучше оставить — чистые GTK3-приложения нового
не понимают. **`GTK_THEME` в окружении не выставлять**: при непустом `GTK_THEME` libadwaita
вообще не ставит свою таблицу стилей (`!g_getenv ("GTK_THEME")` в `constructed`), и вид
сломается по-настоящему.

**Поправка к прежнему утверждению:** в прошлой версии здесь было написано, что после
чистки CSS диагностика Zed по проекту пуста. **Это неверно.** Перепроверено:
`data/theme/way-shell-dark.css` — **271 ошибка и 35 предупреждений** от CSS-парсера Zed.
Все они — следствие GTK-синтаксиса, которого в веб-CSS нет: `@define-color` (35
предупреждений «Unknown at rule»), ссылки `@имя-цвета` в значениях («property value
expected»), `shade()` («`)` expected») и `-gtk-icon-size`. **К сборке и к работе оболочки
это отношения не имеет**: тема уезжает в gresource и разбирается самим GTK, а `ThemeService`
вешает `parsing_error` и пишет в `warning()` — в логе запуска таких строк нет.
Не пытаться чинить эти «ошибки» и не мерить качество темы по ним.

---

## 1. Что сделано и проверено в коде

Порядок: сначала правки первой сессии, затем то, что было в старом плане как «дальше
по приоритету» и с тех пор закрыто.

### 1.1. Один `NM.Client` на процесс — сделано

Было три независимых `new NM.Client(null)`: в `NetworkManagerService`, в `WifiButton`,
в `EthernetButton` (плюс четвёртый в `should_be_visible()` как повторная попытка).

Это не ломало корректность — NetworkManager рассылает `PropertiesChanged` всем клиентам,
состояние не расходилось. Проблема была в цене:

- `nm_client_new()` синхронный: блокирует поток, пока не вытянет по D-Bus весь кэш
  объектов NM (устройства, активные соединения, сохранённые профили, точки доступа,
  IP-конфиги). Три раза подряд на старте, ровно когда NM сам ещё поднимается.
- `EthernetButton.should_be_visible()` вызывается из `Grid.refresh_grid_layout()`, а тот
  подписан на `Drawer.will_show` — то есть на **каждом открытии шторки, в UI-потоке**.
  Если `nm_client` был `null`, там создавался клиент прямо в ответ на клик. Отсюда
  плавающие подвисания шторки на пол-секунды.
- Три копии кэша: каждая появившаяся точка доступа при скане — `AccessPointAdded`,
  доставленный трижды.

Сейчас `new NM.Client` в `src/` ровно один — `NetworkManagerService.vala:47`.

`src/services/NetworkManagerService.vala` — добавлены

```vala
public NM.Client get_client ()
public NM.DeviceWifi? get_wifi_device ()
public NM.DeviceEthernet? get_ethernet_device ()
```

`WifiButton.vala`:
- клиент берётся из `Services.NetworkManagerService.get_global().get_client()` (строка 82)
- `find_wifi_device()` сравнивает найденное с текущим (`if (found == wifi_device) return;`)
  перед навешиванием обработчиков. Раньше повторный вызов из `device_added` вешал ещё один
  набор `notify`, и каждое изменение состояния обрабатывалось дважды.
- **опрос `update_active_ap_status()` каждые 3 секунды убран**. Он был бессмысленным: сила
  сигнала живёт на объекте `NM.AccessPoint`, а кэш NM обновляется только по сканированию —
  опрос видел те же цифры. Вместо него `watch_ap()` (строки 123–133), подписка на
  `notify["strength"]` активной точки с отключением старого обработчика.
  Поля `watched_ap`, `watched_ap_handler` (строки 12–13).

`EthernetButton.vala`:
- `ensure_client()` (строка 34) — ленивое получение клиента из сервиса. Подписки навешиваются
  там же, а не в конструкторе: если NM на старте не поднялся, попытка повторится при
  следующем обращении.
- `find_ethernet_device()` — та же защита от повторной подписки.
- **таймер на 3 секунды убран**, вместо него подписки `notify["state"]`, `notify["carrier"]`,
  `notify["speed"]`, `notify["ip4-config"]` (строки 71–84; последняя нужна, чтобы подзаголовок
  с IP обновился после DHCP).
- `should_be_visible()` → `should_be_visible(bool has_wifi)` (строка 111).

`Grid.vala` — `WifiButton.has_wireless_hardware()` (он сканирует `/sys/class/net`) считается
один раз и передаётся параметром (строки 42–52), а не вызывается дважды на каждое открытие
шторки. Там же добавлен `BluetoothButton.has_bluetooth_hardware()` (строка 57).

**Логика показа кнопок сохранена ровно как просил владелец**, это проверять при рефакторинге:

| железо | Wi-Fi | Ethernet |
|---|---|---|
| только LAN, нет Wi-Fi модуля | нет | да (даже без кабеля, показывает Unplugged) |
| есть Wi-Fi, кабель вставлен | да | да |
| есть Wi-Fi, кабеля нет | да | **нет** |

Код: `return eth_device.carrier || !has_wifi;` (`EthernetButton.vala:129`)

### 1.2. Привязка синглтон-окон к монитору — сделано

`Panel` — per-monitor (`HashTable<Gdk.Monitor, Panel>`), и `attach_to_monitor()` вызывает
`Gtk4LayerShell.set_monitor()`. Это работало.

А `Drawer`, `MessageTray`, `Osd`, `NotificationBanner` — синглтоны, по одному окну на процесс,
и `set_monitor` не вызывал никто. В протоколе layer-shell, если клиент не указал output,
его выбирает композитор. Симптом, который владелец наблюдал сам: клик по панели монитора A
открывал шторку на мониторе B.

`vapi/gtk4-layer-shell-0.vapi` — добавлен биндинг `gtk_layer_get_monitor`:

```vala
[CCode (cheader_filename = "gtk4-layer-shell.h", cname = "gtk_layer_get_monitor")]
public static unowned Gdk.Monitor? get_monitor (Gtk.Window window);
```

`Panel.vala` — статическое поле `active_monitor` и методы:

```vala
public static Gdk.Monitor? get_active_monitor()      // с фолбэком на monitors[0]
public static void set_active_monitor(Gdk.Monitor?)  // игнорирует null и невалидные, :51
public static void place_on_active_monitor(Gtk.Window win)  // :67
public static bool is_on_active_monitor(Gtk.Window win)     // :57, см. 1.11
```

`place_on_active_monitor` проверяет `get_monitor(win) == mon` и только тогда ничего не делает.
Это важно: `gtk_layer_set_monitor` на показанном окне **пересоздаёт surface** (сказано в
хедере библиотеки), то есть окно мигнёт. Вызывать только пока окно скрыто и только когда
монитор реально меняется.

`on_monitor_added` ставит active, если он ещё null. `on_monitor_removed` переназначает
active на `monitors[0]`, если отключили именно активный.

Кто пишет active_monitor:
- `StatusBar.vala:24` — в обработчике клика, до `qs.toggle()`
- `Clock.vala:70` — в `on_clicked()`, до `mt.toggle()`

Кто читает (вызывает `place_on_active_monitor`):
- `Drawer.set_visible()` — `Drawer.vala:71`
- `MessageTray.set_visible()` — `MessageTray.vala:213`
- `Osd.trigger_osd()` — `Osd.vala:172`, только в ветке `if (!win.get_visible())`
- `NotificationBanner.show_banner()` — `NotificationBanner.vala:118`, только в ветке `if (!win.visible)`

### 1.3. Удалён `MessageTray.underlay` — сделано

Это было прозрачное окно на весь экран, приклеенное ко всем четырём краям, с кнопкой
внутри — чтобы клик мимо трея его закрывал. Не работало (владелец подтвердил), и он
явно попросил убрать, а не починить: «я пожалуй откажусь, чтобы как сейчас было».

Удалено: поле `underlay`, метод `init_underlay()`, вызовы `underlay.present()` /
`underlay.set_visible(false)`, блок `.underlay` в CSS. Слова `underlay` в `src/` больше нет.

Про оставшиеся цвета `@underlay-background` / `@underlay-background-heavy` см. 2.3 —
ситуация изменилась после чистки CSS.

Почему это вообще не работало, для понимания на будущее: чтобы клик по пустому месту
закрывал панель, поверхность-перехватчик должна получать события ввода на всём выходе.
В layer-shell это делается через input region, и GTK4 сам управляет им по геометрии
виджетов. Прозрачная кнопка на весь экран поверх остального ломает клики по всему, что
под ней. Правильно это делается либо на уровне композитора, либо через отдельный
protocol. Не приоритет.

### 1.4. Удалён media OSD — сделано

`Osd.vala` строил `media_osd` (иконка + лейбл) и подписывался на
`MediaPlayerService.media_player_changed`. А `MediaPlayerService.vala` был весь такой:

```vala
public signal void media_player_changed (MediaPlayer player);
private MediaPlayerService () {}
```

Сигнал не эмитился нигде — ни MPRIS, ни playerctl, ни D-Bus. То есть `on_osd_media_changed`
не вызывался никогда, плашка не показывалась никогда.

Если бы работало — всплывашка на каждую смену трека, включая автопереход по плейлисту.
Владелец: «это фигня, кусок тупого и бесячего кода». Согласен.

Удалено: файл `src/services/MediaPlayerService.vala`, строка в `meson.build`, поля
`media_osd`/`media_icon`/`media_label`, блок разметки, подписка, метод
`on_osd_media_changed`, строка в `show_osd()`. Упоминаний `MediaPlayerService` и `media_osd`
в `src/` и `meson.build` не осталось.

**Не путать с `media_btn` в `Panel.vala`** — кнопка плеера в центре панели
(артист + название, клик = play/pause, колесо = переключение трека). Она работает,
владелец ей пользуется, её не трогали. Она же — единственный оставшийся потребитель
playerctl, см. 1.13.

### 1.5. `BluetoothService` вынесен в сервис — сделано

Был главный риск проекта: `GLib.Timeout.add_seconds(3)` в `BluetoothButton.vala`, а внутри
`Bus.get_proxy_sync` + `get_managed_objects()` в UI-потоке. Любое подвисание BlueZ вешало
всю оболочку. Три интерфейса BlueZ были объявлены прямо в UI-файле, прокси создавались
заново на каждый вызов, а `on_bluetooth_toggle()` делал одно и то же тремя способами:
свойство `Powered` по D-Bus, потом `rfkill`, потом `bluetoothctl`.

Сейчас есть `src/services/BluetoothService.vala` (429 строк, новый файл, в `meson.build`):

- Конструктор: `Bus.get.begin(BusType.SYSTEM, ...)` (`:69-82`) + `Bus.watch_name_on_connection`
  на `org.bluez` (`:78-81`), обработчики `on_bluez_appeared` / `on_bluez_vanished` (`:107-119`).
- Подписки: `InterfacesAdded` (`:94-96`), `InterfacesRemoved` (`:97-99`), `PropertiesChanged`
  с `object_path == null`, то есть и адаптер, и все устройства (`:102-104`).
- `GetManagedObjects` остался, но асинхронный (`conn.call.begin`, `:125-152`) и только по
  событию появления `bluetoothd`, не по таймеру.
- Кэш `HashTable<string, BluetoothDevice>` (`:43`), наружу сигналы `changed()` /
  `devices_changed()` и свойства `has_adapter` / `powered` / `discovering` (`:52-54`).
- Операции `async` с `throws Error`: `start_discovery`, `stop_discovery`, `connect_device`,
  `disconnect_device`, `pair_device`, `remove_device` (`:400-427`), таймаут
  `OP_TIMEOUT_MS = 60000` для Connect/Pair.
- Опроса нет. Единственный `Timeout` в файле — одноразовый `Timeout.add(500)` (`:362`):
  повторная попытка `Powered=true` после снятия rfkill.

`bluetoothctl` вырезан полностью — в `src/` его нет. `rfkill` остался в `unblock_rfkill()`
(`:374-384`), но это **не избыточность, а обработка одного конкретного случая**:
`Process.spawn_async` с массивом argv (без шелла), вызывается только из ветки ошибки
`apply_powered()`, когда `enable && allow_unblock && "Blocked" in e.message` (`:360-361`),
то есть только на софт-блок. Повторная попытка идёт с `allow_unblock = false` — рекурсии нет.

`BluetoothButton.vala` (404 строки) теперь только виджеты: ни `[DBus]`-интерфейсов,
ни `Bus.get_proxy_sync`, ни `get_managed_objects`. На месте бывших интерфейсов (строки 7–40) —
поля виджета и `has_bluetooth_hardware()` (`:23-33`, чтение `/sys/class/bluetooth`).
`on_bluetooth_toggle()` (`:118-128`) — оптимистичное обновление вида плюс один
`bt.request_powered(next_state)`. Вид обновляется по сигналам `bt.changed`,
`bt.devices_changed`, `notify["discovering"]`, `notify["has-adapter"]` (`:93-99`).
Остался один `Timeout.add_seconds(15)` (`:177`) — автостоп сканирования, это нормально.

### 1.6. `PowerServices` — сделано

Старые претензии и что с ними стало (`src/services/PowerServices.vala`, 415 строк):

- «`get_primary_device()` возвращает `new UpDevice()` на каждый вызов» — **исправлено**:
  `:253-255` возвращает поле `device`, созданное один раз в конструкторе (`:229`).
- «Каждый вызов — утёкший вечный `Timeout.add_seconds(5)`» — **исправлено**: конструктор
  `UpDevice` (`:34-41`) таймер не создаёт, таймер живёт в `start_polling()` (`:89-100`)
  с защитой `if (poll_id != 0) return`, id хранится в `poll_id`, есть `stop_polling()`
  (`:102-106`) и вызов из деструктора (`:43-45`).
- «`UPowerService` не использует UPower, `client_proxy` создаётся и никогда не читается» —
  **исправлено, UPower используется по-настоящему**: `Bus.watch_name_on_connection` на
  `org.freedesktop.UPower` (`:239-242`), `GetDisplayDevice` (`:259-260`), подписка
  `PropertiesChanged` на `display_path` (`:272-274`), `GetAll("org.freedesktop.UPower.Device")`
  (`:290-292`), разбор в `apply_upower_props()` — `IsPresent`, `Percentage`, `State`,
  `TimeToEmpty`, `TimeToFull`, `Type` (`:49-69`). Мёртвого прокси в файле нет.
- sysfs остался **фолбэком, а не основным путём**: `start_polling()` зовётся в четырёх
  случаях — нет системной шины (`:236`), `GetDisplayDevice` упал (`:267`), UPower исчез
  с шины (`:286`), `GetAll` упал (`:301`). При успешном `GetAll` — `device.stop_polling()`
  (`:297`). Оговорка: один синхронный проход по `/sys/class/power_supply/BAT0..3` всё же
  делается безусловно в конструкторе `UpDevice` (`:39-40`) как первый снимок до ответа UPower.
- «`LogindService.set_idle_inhibit()` просто выставляет bool, настоящего `Inhibit` нет» —
  **исправлено**: `take_inhibit()` (`:382-406`) вызывает
  `conn.call_with_unix_fd_list(... "Inhibit", ("ssss") "idle"/"way-shell"/…/"block", VariantType("(h)"))`,
  берёт handle из тела ответа и дескриптор из `fd_list.get(idx)` (`:396-397`);
  `release_inhibit()` — `Posix.close(inhibit_fd)` (`:408-413`). Состояние читается как
  `inhibit_fd >= 0`, поля-bool больше нет, `pending` (`:340`) страхует от параллельных
  запросов. `StatusBar.IdleInhibitorButton` слушает `idle_inhibitor_changed` (`:127-130`).
  Переключается через IPC (`idle-inhibit-toggle` / `-on` / `-off`), своего клика у индикатора
  нет — он внутри общей кнопки, открывающей шторку.
- «Логика батареи дублируется трижды» — **сведено полностью, см. 1.15**. На момент
  первой сверки было сделано частично: расчёты централизованы (`get_status_text()`,
  `get_time_text()`, enum `BatteryState` вместо сырых чисел), но три виджета держали
  одинаковый шаблон из пяти `notify[...]`-подписок и своё `"%.0f%%".printf`.

### 1.7. `WirePlumberService` — сделано

- «В биндинге `wp_core_load_component` нет завершающего `gpointer data`, передаются
  захватывающие лямбды → UB» — **исправлено**. `vapi/wireplumber-0.5.vapi:16-18`:
  `public async bool load_component (string component, string type, void* args, string? provides, GLib.Cancellable? cancellable = null) throws GLib.Error`
  с `cname`/`finish_name`. Колбэк и `user_data` теперь генерирует valac, ручных лямбд нет.
  `load_api_modules()` (`WirePlumberService.vala:108-124`) — два `yield core.load_component`
  в одном `try/catch` с `warning`; раньше ошибка загрузки модуля терялась и звук молча
  не работал. После успеха `load_plugins()` (`:126-146`) находит плагины через `Wp.Plugin.find`.
- «Сервис шеллится в `wpctl set-default`, `pactl set-card-profile`, `pw-metadata`» —
  **исправлено, `Process.spawn*` в файле больше нет вообще**. Имена утилит остались только
  в комментариях (`:201`, `:203`, `:229`, `:397`). В `src/c/way-shell-wp-helpers.c` спавнов тоже нет.
  - `set_default_node()` (`:399-423`): `id` → `node.name` через `get_node_name_by_id()`
    (`:311-327`), затем `Signal.emit_by_name(def_nodes_api, "set-default-configured-node-name", …)`
    с проверкой результата.
  - `route_stream()` (`:204-224`): `find_default_metadata()` (`:183-199`) ищет `WpMetadata`
    с `metadata.name == "default"`, затем `md.set(stream_id, "target.object", "Spa:String", target)`;
    `target` — сначала `node_name`, иначе serial, иначе id.
- «`Process.spawn_command_line_sync("pactl list cards")` в `get_bluetooth_codecs()` блокирует
  главный поток» — **исправлено**. `get_bluetooth_codecs()` (`:231-283`) зовёт C-хелпер
  `way_shell_wp_get_card_profiles(om, node_name)` (`src/c/way-shell-wp-helpers.h:21`,
  реализация `way-shell-wp-helpers.c:112`), тот отдаёт `GVariant "(sia(is))"` — имя карты,
  активный индекс, список профилей; Vala фильтрует `a2dp-sink*` / `headset-head-unit*`
  и приводит имена к читаемым (`format_codec_name`, `:285-296`). Запись профиля —
  `set_bluetooth_codec()` (`:298-309`) через `way_shell_wp_set_card_profile()`.
  Хелперы подключены как `c_sources` в `meson.build` (строки 24–25, 79, 82).

### 1.8. `IpcService` — сделано, с оговорками

`src/services/IpcService.vala` (207 строк):

- **`chmod 0600` на сокете** — есть (`:73-75`). Оговорка: chmod идёт **после**
  `listener.add_address()` (`:61-62`), так что существует короткое окно, когда файл создан
  с правами по umask; провал chmod только логирует `warning`, сервис продолжает слушать.
- **`SO_PEERCRED`** — есть: `peer_is_trusted()` (`:126-137`) сравнивает
  `conn.socket.get_credentials().get_unix_user()` с `Posix.getuid()`, вызывается первым делом
  в `handle_connection()` (`:141-144`), иначе соединение закрывается.
- **Защита от 100% CPU в `accept_connections()`** — есть: `MAX_ACCEPT_ERRORS = 5` (`:10`),
  на лимите `critical` + `listener.close()` + `return` (`:103-108`), между попытками пауза
  200 мс (`:109-115`), счётчик сбрасывается после успешного accept (`:118`). Оговорка: при
  остановке слушателя файл сокета не удаляется (unlink только в деструкторе `:28-33`,
  который у статического синглтона фактически не вызывается), и IPC дальше мёртв молча.
- **Проверка живости сокета перед удалением** — есть: `socket_is_alive()` (`:81-92`),
  при живом экземпляре IPC отключается вместо отбирания сокета (`:45-50`). Оговорка:
  `client.timeout = 1` секунда и вердикт только по успеху connect — зависший, но живой
  экземпляр будет признан мёртвым и сокет перезаберут.

Команды белым списком через `switch` (`:161-205`), произвольного exec нет. Это нормально.

### 1.9. CSS почищен — сделано

`data/theme/way-shell-dark.css`: 1134 → 912 строк (диф по файлу +9/−231, оценка «около
230 строк мусора» подтвердилась численно).

- **Опечатки селекторов исправлены.** `#notification-osd` / `#notification-list`
  (единственное число) в файле больше нет; используются `#notifications-osd` и
  `#notifications-list` — ~60 селекторов, строки 304–546. Совпадает с кодом:
  `NotificationBanner.vala:40` (`win.name = "notifications-osd"`) и
  `MessageTray.vala:69` (`this.name = "notifications-list"`).
- **Мёртвые секции от C-версии удалены**: `#workspaces-bar`, `#workspaces-bar-list`,
  `#activities`, `#dialog-overlay`, `#app-switcher`, `#switcher` — ноль совпадений.

Что осталось несведённым — см. 2.3, там уже конкретные списки.

### 1.10. Доступность — сделано частично

Было «ни одного `update_property` во всём UI» и четыре тултипа. Сейчас:

| метрика | было на `5a7827c` | сейчас |
|---|---|---|
| `update_property` (все `AccessibleProperty.LABEL`) | 0 | 11 |
| accessibility-`update_state` | 0 | 5 (`HIDDEN` ×1, `EXPANDED` ×3, `PRESSED` ×1) |
| `accessible_role` | 0 | **0** |
| тултипы (`tooltip_text =` + `set_tooltip_text(`) | 4 | 16 |

Осторожно при подсчёте: `update_state` встречается в `src/` 15 раз, но 10 из них — это
одноимённый метод сервисов (`WirePlumberService`, `Scales`), а не accessibility.

Помечены пять файлов из 38:

| файл | что |
|---|---|
| `src/panel/StatusBar.vala:28,31,81,90` | главная кнопка QS: тултип + `LABEL`, пересобираемый из видимых индикаторов (`update_accessible_label` 64–91, имена в `indicator_name` 93–101); плюс тултип батареи (:303) |
| `src/panel/Clock.vala:38,39,48,109` | кнопка часов: тултип + `LABEL`; точка уведомлений скрыта через `AccessibleState.HIDDEN`; `LABEL` пересчитывается с DND/счётчиком (100–111) |
| `src/panel/quick_settings/Scales.vala:34,35,40,87,88,93` | кнопки mute звука и микрофона (тултип + `LABEL`), оба `Gtk.Scale` получили `LABEL` |
| `src/panel/quick_settings/GridButton.vala:96,97,100,115,123,140` | стрелка `reveal_button` (тултип + `LABEL` из заголовка), `AccessibleState.EXPANDED` на раскрытие, `PRESSED` на `set_toggled` |
| `src/panel/Panel.vala:106,128,202` | кнопка плеера (тултип + `LABEL` с названием трека), иконка веб-камеры (тултип) |

Структурная претензия к `StatusBar` из старой версии документа верна и сейчас: это `Box`
с одной `Gtk.Button` (`:19`), внутри которой шесть индикаторов-`Box` (`:35-57` —
`IdleInhibitorButton`, `NightLightButton`, `VpnButton`, `NetworkButton`, `SoundButton`,
`PowerButton`). Но безымянной для скринридера она больше не является.

Что ещё не покрыто — см. 2.4.

### 1.11. Перенос шторки между мониторами одним кликом — сделано

В прежней версии документа это лежало в отдельном разделе «Незаконченное — точный патч»
(`edit_file` пропал посреди работы). **Патч применён, раздел больше не нужен.**

Было: `if (win.get_visible()) set_hidden(); else set_visible();` — шторка открыта на мониторе A,
клик по панели B записывал `set_active_monitor(B)`, но `toggle()` видел `visible == true`
и просто закрывал. Перенос требовал двух кликов.

Сейчас в коде:

- `Panel.vala:57-62` — `is_on_active_monitor(Gtk.Window win)`. `current == null` трактуется
  как «на активном»: значит `set_monitor` ещё не звали ни разу и окно там, куда его положил
  композитор; гадать бессмысленно, а лишний remap хуже.
- `Drawer.vala:84-99` и `MessageTray.vala:224-239` — `toggle()` с тремя ветками: скрыто →
  показать; видимо и на активном мониторе → `set_hidden()`; видимо и на чужом →
  `win.set_visible(false)` + `set_visible()`.

Почему `win.set_visible(false)`, а не `set_hidden()`: `set_hidden()` эмитит `hidden()`,
на который через `Mediator` подписаны все панели (`on_qs_hidden` снимает подсветку), плюс
`GridCluster.hide_all` и `Header.collapse_all`. Пара `set_hidden()` + `set_visible()` подряд —
это лишняя пачка сигналов и мигание подсветки. Прямое скрытие достаточно: `set_visible()`
дальше сам вызовет `place_on_active_monitor` (окно уже скрыто, remap безопасен) и `present()`.

**Руками на двух мониторах владелец это ещё не подтверждал.** Сборка проходит; проверить
надо так: клик по статус-бару A → шторка на A; клик по статус-бару B → переехала на B одним
кликом; клик по B ещё раз → закрылась. То же с часами и треем.

### 1.12. Мелочи, попутно закрытые

- `DndButton.vala:16-17` — убран `Timeout.add(1000)`, поллинг GSettings с частотой 1 Гц;
  вместо него подписка на `changed`.
- `NotificationWidget.vala:33` — время в «N ago» считается по монотонным часам, ушёл баг
  с «4h ago» и часовыми поясами. `:160-167` — 10-секундный таймер теперь снимается,
  раньше он жил вечно и держал ссылку на удалённый виджет (сотня уведомлений — сотня
  живых source).
- `NotificationsService.vala:108-116` — проверка типа перед `get_byte()`: спека требует byte,
  но клиенты присылают int32/uint32, и без проверки процесс падал через `g_critical`.
  `:198-214` — sanity-лимиты на размеры пиксельных данных, пришедших по D-Bus от любого
  приложения.
- `data/gschemas.compiled` удалён из индекса (собирается в `build/data/`),
  `data/meson.build` — новый файл, ставит схему и компилирует её для запуска из build-каталога.
- `way-shell.nix` → `package.nix` (86 строк удалено, новый файл не отслеживается).
- Удалены `wlr-protocols` XML и сгенерированные C-биндинги wlr (foreign-toplevel, gamma-control,
  input-inhibitor, output-management) — вместе с `NiriClient` / `WindowManagerService` они
  стали не нужны, это ~2200 строк из общего минуса.

### 1.13. MPRIS вместо playerctl — сделано

`src/services/MediaPlayerService.vala` создан заново (305 строк, в `meson.build`). Внешне для
пользователя не изменилось ничего: та же кнопка в центре панели, клик = play/pause,
колесо = трек.

Что было: `playerctl --follow` запускался из конструктора `Panel`, то есть **по процессу
на каждый монитор**, и каждый клик/скролл форкал ещё один `playerctl`. Данные о треке
приходили текстом из stdout чужой программы и парсились через `split("|", 2)`.

Главное, что это давало на практике: при падении или kill way-shell `shutdown()` не
вызывался, и дочерние процессы осиротевали. На машине владельца на момент правки висело
**восемь процессов playerctl, суммарно 69 МБ**, самый старый — четыре дня, у всех
`PPID = 1` (`systemd --user`). Владелец решил убрать их перезагрузкой.

Как сделано:

- Обнаружение: `ListNames` на сессионной шине + фильтр по префиксу `org.mpris.MediaPlayer2.`,
  дальше `NameOwnerChanged` (`:117-131`) на запуск и смерть плееров. `Bus.watch_name` не
  подходит — он работает по точному имени, а нам нужен префикс.
- Данные: `PropertiesChanged` на `org.mpris.MediaPlayer2.Player`, плюс `GetAll` при
  добавлении плеера (`:150-160`) — плеер мог играть до нашего старта.
- Управление: `PlayPause` / `Next` / `Previous` через `conn.call.begin` (`:283-293`).
- Метаданные: `xesam:title` и `xesam:artist`; последний по спеке `as`, но встречается
  и одиночной строкой — обработаны оба случая (`:196-217`).

**Отклонение от изначального плана, которое важно понимать:** подписка на
`PropertiesChanged` сделана **отдельной на каждый плеер** (`:136-146`), а не одной общей.
Общая потребовала бы сопоставлять уникальное имя отправителя (`:1.42`) с well-known именем
плеера, а единственный способ это сделать — `GetNameOwner`, то есть блокирующий вызов
D-Bus на каждый сигнал в UI-потоке. При отдельных подписках сопоставление делает сам
шинный демон в match-правиле, а состояние плеера захватывается в замыкание.
Подписки снимаются в `remove_player()` и деструкторе.

Активным считается играющий плеер; если играющих нет — любой, у кого есть трек (`:222-262`).
Так кнопка не пропадает на паузе.

Попутно добавилось то, чего с playerctl не было: иконка кнопки меняется между
`media-playback-start-symbolic` и `media-playback-pause-symbolic` — до этого состояние
воспроизведения в текстовом выводе просто не приходило.

Из `Panel.vala` удалены `start_playerctl_monitor`, `playerctl_pid`, `playerctl_watch_id`,
оба спавна; `shutdown()` схлопнулся до `win.destroy()`. Из `package.nix` `playerctl` убран
и из `buildInputs`, и из runtime PATH.

Проверено на живом плеере, включая двойное переключение:

```
[03:23:50] changed: available=true playing=false text="Tyler, Le Createur - 16-Rusty..."
-- play_pause #1 --
[03:23:52] changed: available=true playing=true  text="..."
-- play_pause #2 --
[03:23:54] changed: available=true playing=false text="..."
```

### 1.14. Индикатор камеры: `WebcamService` на inotify — сделано

`src/services/WebcamService.vala` (231 строка, новый файл, в `meson.build`).

**Старая логика была сломана в принципе, а не просто дорога.** `Panel.vala` каждую секунду
делал `File.read("/dev/video0")` и ловил `IOError.BUSY`. Проверено на железе владельца
(`HP TrueVision HD`, драйвер `uvcvideo`): при удерживаемом открытом дескрипторе три
дополнительных `open()` проходят успешно — `uvcvideo` разрешает несколько одновременных
optn, а `EBUSY` возвращается только на `VIDIOC_STREAMON`. То есть **иконка не показывалась
никогда**, в том числе при работающем захвате. Плюс этот `open()` раз в секунду будил USB
и мешал autosuspend, и таймер был на каждый монитор.

**Почему inotify, а не PipeWire** (владелец спрашивал прямо, ответ проверен опытом):
через PipeWire ходят браузеры, OBS и Flatpak-приложения, но v4l2 никуда не делся, и
нативные приложения открывают `/dev/videoN` напрямую. Запуск `ffmpeg -f v4l2 -i /dev/video0`
захватывает камеру, а нода PipeWire остаётся `suspended` — то есть PipeWire-детекция такой
захват не увидит. Обратное неверно: когда стримит сам PipeWire, он тоже делает `open()`
на устройстве. Значит inotify видит оба случая, а PipeWire только один. PipeWire полезен
для другого — узнать, *кто именно* держит камеру (имя клиента в графе); если это
понадобится в тултипе, добавлять поверх, не вместо.

Как сделано:

- Один `inotify` fd на процесс, watch на **все** узлы из `/sys/class/video4linux`
  (`:110-124`) — у владельца их два, `video0` и `video1`, оба от одного `uvcvideo`.
- Счётчик открытых дескрипторов, а не bool (`:170-190`): камеру может держать несколько
  процессов. `IN_OPEN` → +1, `IN_CLOSE_WRITE`/`IN_CLOSE_NOWRITE` → −1.
- **Задержка 400 мс перед показом** (`:196-227`). wireplumber и udev-хелперы открывают
  устройство на доли секунды, чтобы прочитать возможности; без задержки иконка мигала бы
  на старте и на каждое переподключение. Закрытие применяется сразу, без задержки: лучше
  убрать иконку мгновенно, чем оставить ложное «камера работает».
- Начальное состояние читается один раз через `/proc/*/fd` (`:130-160`): кто-то мог открыть
  камеру до старта way-shell, а inotify про прошлое не знает.
- Свойство `has_device`: если камер нет, не создаются ни watch, ни виджет. Отключаемая
  настройка не нужна — ровно как просил владелец.

Иконка переехала из `Panel.right` внутрь `StatusBar` как класс `WebcamButton`
(`StatusBar.vala:113-131`), последней в ряду индикаторов — чтобы её появление не сдвигало
привычные позиции остальных. Теперь она получает клик (открывает шторку), подсветку и
попадает в accessible-метку кнопки. В CSS у `.webcam-active` убраны `margin-left/right`:
внутри бокса отступы задаёт `spacing`, свои margin ломали ровный ряд.

Проверено реальным захватом:

```
has_device = true
in_use (initial) = false
-- starting ffmpeg capture for 3s --
[03:15:11] in_use -> true
[03:15:14] in_use -> false
```

### 1.15. Дублирование логики батареи сведено — сделано

Виджетов по-прежнему три, и это осознанное решение владельца: батарея видна в панели,
в quick settings и в меню батареи. **Убирать их не предлагалось и не нужно** — сводился
только дублирующийся код.

В `UpDevice` добавлены `get_percent_text()` (`:193-195`), `get_icon_name()` (`:228-238`),
`get_summary_text()` (`:241-246`). Статический `UPowerService.device_map_icon_name()` удалён:
иконка теперь метод самого устройства, виджетам достаточно `UpDevice`.

Попутно нашлось кое-что реальнее косметики: каждый из трёх виджетов подписывался на пять
отдельных `notify[...]`, поэтому **один `PropertiesChanged` от UPower перерисовывал каждый
виджет до пяти раз подряд**. Теперь `UpDevice` эмитит один сигнал `changed()` на пакет
изменений (`:44-49`, эмиссия в `apply_upower_props()` и `refresh_sysfs()`), и подписка
у каждого виджета одна.

Затронуты `StatusBar.vala:287-327`, `…/header/BatteryButton.vala`, `…/header/BatteryMenu.vala`.
Проверка, что дублей не осталось: `grep` по `notify["percentage"]`, `notify["time-to`,
`device_map_icon_name`, `%.0f%%` находит только сам `get_percent_text` в `PowerServices.vala:194`.

### 1.16. Локализация gettext — сделано

`po/` с `LINGUAS`, `POTFILES.in`, `meson.build`, `way-shell.pot`, `en.po`, `ru.po`.
Домен `way-shell`, язык берётся из локали пользователя (`Intl.setlocale(ALL, "")` в
`main.vala:46`), своего переключателя нет — как просил владелец. Все `msgid` английские,
русский в `ru.po`; `en.po` заполнен через `msgen` (msgstr = msgid), чтобы `en` был реально
выбираемой локалью. Сейчас **112 строк, обе локали переведены полностью**
(`msgfmt --statistics`: `112 translated messages` для каждой).

Путь к переводам перекрывается `WAY_SHELL_LOCALEDIR` (`main.vala:50-51`) — при запуске из
`build/` установленных `.mo` ещё нет, так же как схема через `GSETTINGS_SCHEMA_DIR`:

```
WAY_SHELL_LOCALEDIR=$PWD/build/po GSETTINGS_SCHEMA_DIR=$PWD/build/data ./build/way-shell
```

Проверено разовой пробой — переводы действительно подхватываются:

```
LANG=ru_RU.utf8   → "Volume: %s" → "Громкость: %s", "muted" → "выключен"
LANG=en_US.UTF-8  → "Volume: %s" → "Volume: %s"
```

У владельца сейчас `LANG=en_US.UTF-8`, то есть интерфейс будет английским. `ru_RU.utf8`
в системе есть (`locale -a`), так что русский включается сменой локали системы, без
правки кода.

Две ловушки, обе уже обойдены, но легко сломать обратно:

- **`-DGETTEXT_PACKAGE` нужен в `c_args` цели** (`meson.build:102`), а не только в `config.h`:
  valac подключает `<glib/gi18n-lib.h>` в каждый файл с `_()`, а тот требует макрос на
  уровне препроцессора. Через `config.h` не работает — valac вставляет его только туда,
  где используется сам `Config.*`.
- **`.gitignore` прятал переводы**: шаблон `**.*o` подходил под `ru.po`/`en.po`.
  Исправлено на `*.o` + `po/*.pot`.

При добавлении строк: дописать файл в `po/POTFILES.in`, затем
`meson compile -C build way-shell-pot`, затем
`msgmerge --update --backup=none --no-fuzzy-matching po/ru.po po/way-shell.pot` (то же для
`en.po`, потом `msgen`). `msginit` не использовать — он генерирует заголовки с мусором
(«Английские переводы для пакета way-shell» в русском файле).

`get_time_text()` в `UpDevice` переписан со склейки «число + суффикс» на четыре целые фразы
(`"%lld h %lld min until empty"` и т.д.): иначе падежи в русском не выразить.

### 1.17. Взаимное закрытие подменю в шторке — сделано

Было: открытое подменю шапки (батарея / микшер / питание) и открытое подменю сетки
(Wi-Fi / Bluetooth / Ethernet) могли висеть одновременно, и шторка растягивалась до низа экрана.

Сделано сигналом на `Drawer`: `submenu_will_open(SubmenuOwner)` (`Drawer.vala:23`), enum
`SubmenuOwner { HEADER, GRID }` (`:7-9`). `Header.toggle_revealer` эмитит его перед
раскрытием (`Header.vala:117`), `Grid.on_cluster_will_reveal` — тоже (`Grid.vala:182`).
Каждый слушает и гасит своё, если владелец не он (`Header.vala:84-86`, `Grid.vala:37-42`).
Внутри шапки взаимное гашение было и раньше, внутри сетки — через `GridCluster.will_reveal`.

В обработчике сетки нет `shrink()` — размером распоряжается тот, кто открывается, иначе
шторка дёргается на переходе.

### 1.18. Tooltips на индикаторах панели — сделано

Проверено сначала, что подсказка на `Gtk.Image` **внутри** `Gtk.Button` вообще срабатывает:
`GtkImage.can_target = true`, и `win.pick()` над иконкой возвращает сам `GtkImage` с его
`tooltip_text`, а не кнопку-родителя. Значит отдельные подсказки на динамик и микрофон
работают, хотя оба лежат внутри общей кнопки quick settings.

- **Звук** (`StatusBar.vala:301-309`): на иконке динамика «Volume: 80%» либо «Sound: muted».
- **Микрофон** (`:287-299`): «Microphone in use: 41%» либо «Microphone in use, muted».
- **Сеть** (`:219-255`): Wi-Fi — SSID и сила сигнала («Wi-Fi: RT-GPON-FD10 (61%)»),
  Ethernet — IPv4-адрес («Wired: 192.168.0.154»), плюс состояния disconnected/connecting.
  Проверено на живом NM: SSID и адрес читаются (`wlp3s0`, `192.168.0.154`).
- **Шторка** (`Scales.vala:242-262`): подсказки и на слайдерах, и на кнопках mute, с теми же
  процентами; у яркости — на иконке и на слайдере.

Два хелпера, чтобы не дублировать разбор: `NetworkManagerService.ap_to_ssid()` (`:123-136`,
валидирует UTF-8 и обрезает по нулю — SSID в NM это `GBytes` без гарантий) и
`device_ip4()` (`:139-146`). Формат процентов один на весь проект —
`WirePlumberService.format_volume()` (`:650-653`).

Отдельно: `map_source_vol_icon` был скопирован в `Scales` и в `StatusBar` с **разными**
порогами (0.25/0.5 и ничего); теперь один статический метод в сервисе
(`WirePlumberService.vala:635-648`), пороги совпадают с `map_sink_vol_icon`.

### 1.19. Иконка микрофона теперь значит «микрофон занят» — сделано

Жалоба владельца: кнопка mute в шторке прячет сама себя, включить обратно можно только
через MixerMenu.

Причина: `is_microphone_active()` возвращал **`!mute`**, а не «используется». На этом имени
висели и видимость `default_source_container` в шторке, и видимость иконки в панели.
Итог: mute → `false` → регулятор и иконка исчезают, вернуть звук нечем. Заодно иконка в
панели горела постоянно, пока микрофон просто включён — то же самое, что владелец ранее
говорил про камеру («чтобы не горело всегда»).

Сделано:

- `is_microphone_active()` удалён. Вместо него `microphone_in_use()`
  (`WirePlumberService.vala:436-456`) — ищет узел `media.class == "Stream/Input/Audio"`, то есть
  реально пишущего клиента. Проверено: без записи `false`, под `pw-record` `true`.
- Сигнал `microphone_active(bool)` заменён на `default_source_changed(WirePlumberServiceNode?)`
  (`:72`): сервис отдаёт узел, решение показывать или нет остаётся за виджетом.
- Регулятор в шторке виден, пока в системе есть устройство записи (`Scales.vala:228`),
  независимо от mute. Иконка и подсказка пересчитываются сразу в обработчике клика
  (`:116-131`), а не по ответу с шины — иначе кадр запаздывает.
- Иконка в панели висит на `microphone_in_use()` (`StatusBar.vala:287-299`).

**Отдельный баг, найденный по ходу:** `set_mute`/`set_volume` всегда эмитили
`default_sink_volume_changed`, даже для источника. То есть mute микрофона показывал **OSD
громкости** с иконкой колонки и чужим значением. Теперь `notify_node_changed()` (`:484-490`)
выбирает сигнал по `media_class`.

Проверено разовой пробой на живой шине: mute → `id=57 mute=да`, источник не исчезает,
unmute возвращает состояние.

### 1.20. Слайдер яркости в quick settings — сделано

Третья строка в `Scales` под звуком и микрофоном, только если подсветка есть
(`Scales.vala:152-196`). Иконка не кнопка: у яркости нет состояния «выключено», нажимать
нечего. Диапазон начинается с `0.05`, а не с нуля — иначе слайдер позволяет погасить экран
насовсем.

**`brightnessctl` не в горячем пути, как просил владелец** («без использования brightnessctl
а то будет как wpctl фигня»). Порядок попыток в `write_sysfs_value`
(`BrightnessService.vala:191-222`):

1. Прямая запись в sysfs — работает, если есть udev-правило.
2. **logind `Session.SetBrightness`** (`:225-239`) — новое. Метод разрешён владельцу
   активной сессии без polkit-диалога, процессов не плодит. Вызов без ожидания ответа:
   яркость тянут слайдером, блокировать UI-поток на каждый шаг нельзя.
3. `brightnessctl` — остался последним фолбэком для чужих конфигураций.

На машине владельца работает именно шаг 2: `/sys/class/backlight/intel_backlight/brightness`
— `root:root 0644`, он в группе `video`, но udev-правила нет, так что прямая запись не проходит
(проверено `test -w`). Проверено на живой системе дважды: `busctl call … SetBrightness ssu
backlight intel_backlight 880` меняет значение, и разовая проба на самом сервисе тоже
прошла (`set_backlight_percent(0.80)` → sysfs `750` из 937, затем возврат).

Путь сессии — `/org/freedesktop/login1/session/auto`, logind сам разыменовывает его в сессию
вызывающего. **`/session/self` не существует** — проверено, `Unknown object`.

Слайдер догоняет горячие клавиши: `FileMonitor` в сервисе видит запись и от logind, и от
`brightnessctl` из niri-биндов (`XF86MonBrightnessUp` у владельца спавнит `brightnessctl set 5%+`)
— проверено `gio monitor`, событие приходит. Заодно в оба монитора добавлено сравнение с
прежним значением (`:97`, `:141`): `FileMonitor` шлёт `CHANGED` и `CHANGES_DONE_HINT`, то есть
**два события на одну запись**, и OSD со слайдером обновлялись дважды на каждый шаг
(видно в логе пробы: два `brightness_changed: 0.800` подряд).

### 1.21. Системный трей: `StatusNotifierService` реализован — сделано

Был стаб на 52 строки (пустой `HashTable`, четыре сигнала без эмиссии) — это был пункт 2.2.
Сейчас 667 строк, три класса, оболочка сама работает и watcher'ом, и host'ом.

- **`StatusNotifierWatcher`** (`:18-90`) — экспортируется на шину как
  `org.kde.StatusNotifierWatcher`, путь `/StatusNotifierWatcher`. `RegisterStatusNotifierItem`
  принимает и well-known имя, и путь объекта: часть приложений присылает
  `/StatusNotifierItem`, тогда именем считается `sender` (`:51-71`).
- **`StatusNotifierItem`** (`:93-336`) — свойства через `GetAll`, обновления по сигналам
  `NewIcon`/`NewStatus`/`NewToolTip`/`NewTitle`. Подписка одна на все: имя сигнала не
  фильтруется, в ответ всё равно перечитываются свойства целиком, а серия сигналов
  склеивается дебаунсом 80 мс (`:174-183`). Иконка — из `IconName`, а если приложение
  отдаёт пиксели — из `IconPixmap` (ARGB32 в сетевом порядке → `Gdk.MemoryTexture`, `:279-303`).
  `IconThemePath` добавляется в `Gtk.IconTheme`: Flatpak-приложения кладут иконки рядом
  с собой. `NeedsAttention` берёт `AttentionIconName`, `Passive` скрывает значок.
- **`DbusMenu`** (`:341-544`) — `com.canonical.dbusmenu` → `GLib.Menu` + `SimpleActionGroup`,
  потому что `PopoverMenu` умеет показывать только их. Разделители становятся границами
  секций (в GMenu отдельного элемента-разделителя нет), `children-display == "submenu"`
  — вложенным меню, `toggle-type` — stateful-действием (состояние переключается вручную:
  своя обработка `activate` отключает автоматику `GSimpleAction`). Клик уходит обратно
  методом `Event` с `eventId = "clicked"`. `LayoutUpdated` и `ItemsPropertiesUpdated`
  обрабатываются одинаково — перечитыванием дерева, с дебаунсом 100 мс.
- **`StatusNotifierService`** (`:546-666`) — владеет именем, следит за уходом приложений
  через `Bus.watch_name` (`Unregister` присылают не все), поднимает
  `org.kde.StatusNotifierHost-<pid>`: приложения из мира KDE проверяют наличие хоста
  отдельно от watcher.

`IndicatorBar.vala` переписан (180 строк): ЛКМ — `Activate` (или меню, если `ItemIsMenu`),
ПКМ — меню, СКМ — `SecondaryActivate`, колесо — `Scroll`. У кнопки есть и tooltip, и
accessible-метка из `ToolTip`/`Title`/`Id` — раньше этот файл был в списке 2.4 как «без
единой метки». `PopoverMenu` с `set_parent()` не входит в дерево детей и сам не убирается,
поэтому есть `dispose()` с `unparent()` и снятием подписок.

gschema-ключ `enable-tray-icons` снова `true` по умолчанию, описание переписано. Сервис
поднимается в `main.vala:29-37` **до** панелей: приложения регистрируются в watcher сразу,
как он появился на шине, и ждать создания виджета не будут. Ключ проверяется там же:
**владеть `org.kde.StatusNotifierWatcher` вхолостую опаснее, чем не владеть совсем** — пока
имя занято, другой трей его не получит. На `name_lost` мы молча уступаем (`:616-620`),
а не перехватываем.

Проверено на живой шине дважды — и отдельным тестовым бинарником, и собранным
`build/way-shell`:

```
GetNameOwner org.kde.StatusNotifierWatcher → ":1.294"
RegisteredStatusNotifierItems → as 1 ":1.296/org/blueman/sni"
IsStatusNotifierHostRegistered → b true
```

Меню blueman собирается полностью — 5 секций, 12 элементов («Turn Bluetooth _Off»,
«Audio and input profiles on D-Headset», «_Exit» и т.д.). Пиксельные иконки проверены
фальшивым SNI-приложением: `2x2` текстура распознаётся (`paintable=есть 2x2`).

Сейчас в сессии владельца единственное SNI-приложение — blueman (`org.blueman.Tray`).
До этого watcher в системе не держал никто (`The name does not have an owner`), то есть
перехватывать было не у кого.

**Что не проверено глазами:** сам виджет в панели. blueman отдаёт `blueman-tray`,
файл есть в `hicolor` (22…128 px, только PNG, не symbolic), но как он выглядит рядом
с symbolic-иконками панели — смотреть владельцу.

---

## 2. Что осталось

Нумерация сохранена прежней, чтобы ссылки в переписке оставались верными. Закрытые
пункты переехали в раздел 1: MPRIS (было 2.1) → 1.13, камера (было 2.7) → 1.14,
батарея (было 2.5) → 1.15, трей (половина 2.2) → 1.21.

Коротко, что осталось и насколько это важно:

| пункт | что это | приоритет |
|---|---|---|
| 2.2 | Стаб `WaylandGammaControlService` (трей закрыт, см. 1.21) | низкий, кнопка всегда скрыта |
| 2.3 | CSS-классы без определения и наоборот, цвета-пустышки | косметика, ничего не ломает |
| 2.4 | `accessible_role` нулевой, часть файлов UI без меток | средний, если нужен скринридер |
| 2.5 | Инфраструктура (тесты, CI, editorconfig, meson_options) | владелец отказался от трёх из четырёх |
| 2.6 | Оговорки в уже сделанном | мелкие хвосты |

**Блокеров и сломанного функционала в списке больше нет.** Всё, что было «работает не
так, как выглядит» — синхронный D-Bus в UI-потоке, утечки таймеров и процессов,
UB в биндинге, неработающая детекция камеры, врущий ингибитор простоя, запись в sysfs
через rename — закрыто и перечислено в разделе 1.

### 2.2. Стаб, который притворяется сервисом — остался один

`StatusNotifierService` больше не стаб — см. 1.21. Остался один:

- `WaylandGammaControlService` (31 строка) — стаб: `private WaylandGammaControlService () {}`
  (`:16`), `is_enabled` меняется только извне через `set_enabled()`, который никто не зовёт.
  На сервис ссылается `NightLightButton` в `StatusBar.vala`, поэтому не удалён.
  `enabled()` всегда `false`, кнопка всегда скрыта. Важно: C-биндинги `wlr-gamma-control`
  удалены (см. 1.12), так что реализация потребует вернуть протокол или шевелить внешний
  демон (`wlsunset`/`gammastep`).

### 2.3. CSS: остаточный рассинхрон — не сделано

Мусор и опечатки убраны (1.9), но сведение кода и темы не доведено.

**Восемь проектных классов используются в коде, но в CSS не определены** (было девять;
`panel-indicator-bar-widget-box` уш႑л вместе с переписанным `IndicatorBar`, см. 1.21):

| класс | где добавляется |
|---|---|
| `battery-progress-bar` | `…/header/BatteryMenu.vala:25` |
| `panel-button-label` | `Panel.vala:111` |
| `panel-clock` | `Clock.vala:20` |
| `panel-indicator-bar-list` | `IndicatorBar.vala:150` |
| `quick-settings-grid-button-revealer` | `GridButton.vala:108` |
| `quick-settings-menu-option` | `BluetoothButton.vala:239,310`; `EthernetButton.vala:223` |
| `uptime-badge` | `…/header/UptimeWidget.vala:12` |
| `with-revealer` | `GridButton.vala:88` |

Новые классы в этот список не попадают: `webcam-active` из 1.14 определён,
`needs-attention` из 1.21 тоже (CSS рядом с `#panel-indicator-bar-widget`).

Две ловушки при проверке грепом: для `panel-clock` в CSS есть только `.panel-clock-notif`
— это другой класс; для `quick-settings-menu-option` есть только суффиксные варианты
(`-wifi`, `-mixer`, `-power-profiles`, `-wifi-password-entry-container`) и одноимённый
`@define-color`, но правила для самого класса нет. Сравнивать надо с границей слова после
имени класса, иначе суффиксные совпадения дадут ложное «определён».

Не считать проблемой: `card`, `heading`, `caption`, `dim-label`, `flat`, `circular` — это
встроенные классы libadwaita/GTK, они работают без определения в теме.

**Обратный рассинхрон:** около 40 CSS-классов определены, но в Vala не встречаются.
Проектные из них: `notification-widget-app-icon`, `-app-name`, `-timer`, `-button`,
`-button-critical`, `-icon`, `-dismiss-button`, `-expand-button`, `-action-button`,
`-media-button`, `-media-buttons-container`, `notification-group-stack-effect-box1`/`box2`,
`-list-header`, `-conceal-button`, `-overlay-expand-button`, `-dismiss-button`,
`-notification-list`, `notifications-list-controls`, `notifications-list-clear`,
`media-player`, `mixer-link`, `no-revealer`, `quick-settings-menu-option-wifi`,
`quick-settings-menu-option-power-profiles`. Причина: `NotificationWidget.vala` переписан
на libadwaita-классы (`card`, `flat`, `circular`, `heading`) вместо собственных. Заодно мёртв
id `#notifications-list-controls` — в коде не выставляется нигде. В том же списке есть
ложные срабатывания грепа (`background`, `top`, `bottom`, `left`, `right`, `first`, `last`,
`view`, `title`, `subtitle`, `day-name`, `day-number`, `today`, `other-month`, `vala`) — это
встроенные классы GTK либо части селекторов, их трогать не надо.

**Цвета-пустышки** (пересчитано заново):

- `@underlay-background-heavy` (строка 10), `@workspace-button-start-gradient` (18),
  `@workspace-button-end-gradient` (19) — **нуль использований**, остатки от удалённых
  `#dialog-overlay` и `#workspaces-bar`.
- `@underlay-background` (строка 9) — ровно одно:
  `#message-tray { box-shadow: 0 2px 4px 0 @underlay-background; }` (строка 184). Значение
  `rgba(0,0,0,0.0)`, то есть тень полностью прозрачна и визуально не даёт ничего.
- `@workspace-bar-urgent` (20) больше не пустышка: его использует `needs-attention`
  из 1.21 (строка 173). Имя историческое, можно было бы переименовать в `@urgent`.

### 2.4. Доступность: что осталось

`accessible_role` — **ноль во всём проекте**, эта часть актуальна целиком.
Цифры выросли после 1.18 и 1.21: **27 `update_property`, 37 тултипов, 0 `accessible_role`**
(было 11 / 16 / 0).

Закрыто с прошлого раза: `IndicatorBar.vala` (1.21 — есть и tooltip, и метка),
`MessageTray.vala`, `NotificationWidget.vala`, `Calendar.vala`, `MixerMenu.mute_btn`,
`WifiButton.refresh_btn`, `BluetoothButton.unpair_btn`, `UptimeWidget`, `BatteryMenu`.

Что всё ещё без меток:

- `…/header/Header.vala` — `mixer_button` (`:43`) и `power_button` (`:47`), оба
  `Button.from_icon_name` без метки; состояние раскрытия ревелеров скринридеру не
  сообщается (в `GridButton` такое есть — `AccessibleState.EXPANDED`).
- `src/osd/Osd.vala` — три `osd-container` с `Image` + `Scale`; шкалы `sensitive = false`,
  ни `LABEL`, ни тултипов. Насколько это вообще нужно — спорно: OSD живёт две секунды
  и не принимает ввод.
- `src/osd/NotificationBanner.vala` — кнопок нет вовсе, только текст; формально в списке,
  по сути трогать нечего.
- `…/header/MixerMenu.vala` — `default_btn` (`:240`) и `default_dot` (`:395`, `:398`) имеют
  tooltip, но не `update_property`.
- `…/modules/BluetoothButton.vala:51` — `scan_btn` имеет tooltip без `update_property`;
  там же `btn` в списках (`:280`, `:342`).

Файлы без меток, которые **не надо** трогать: все сервисы в `src/services/` и `main.vala`,
`Mediator.vala`, `Drawer.vala`, `Grid.vala`, `GridCluster.vala`, `MenuWidget.vala` — в них
либо нет UI, либо он без интерактивных элементов. `EthernetButton.vala`, `DndButton.vala` и
`PowerMenu.vala` обходятся без своих меток законно: в первых двух текст идёт через
`GridButton` (там есть и метка стрелки, и `AccessibleState.PRESSED`), в `PowerMenu` —
`Button.with_label`, то есть текст внутри кнопки скринридер прочтёт сам.

**Устарело в этом пункте:** список «точечных пропусков» из прежней версии закрыт:
`MixerMenu.mute_btn` получил и tooltip, и `update_property` (`:189-190`),
`WifiButton.refresh_btn` тоже (`:72-73`), `BluetoothButton.unpair_btn` — тоже (`:299-300`),
и английская строка там больше не выбивается — весь интерфейс теперь английский в коде
и русский в `ru.po` (1.16).

### 2.5. Инфраструктура — не сделано, и владелец сознательно отказался

Состояние (проверено поиском по дереву):

| | | |
|---|---|---|
| `tests/` | нет | можно сделать, но см. ниже |
| CI (`.github/`, `.gitlab-ci.yml`, `.woodpecker*`, `.drone.yml`, `Jenkinsfile`, `.circleci`) | нет | **владелец отказался** |
| `.editorconfig` | нет | **владелец отказался** |
| `meson_options.txt` / `meson.options` | нет | **владелец отказался** |

Не предлагать снова без просьбы. Аргументы владельца:

- **CI** — «я nixos мне так и так надо будет билдить самому». Для проекта на одного
  человека с локальной сборкой это карго-культ; ошибки видны сразу при `meson compile`.
- **`.editorconfig`** — полезен, когда над кодом работают разные редакторы. Здесь один
  разработчик и один Zed.
- **`meson_options.txt`** — нужен, чтобы отключать части проекта флагами сборки.
  У владельца одна конфигурация, вариативность ему не нужна.

Про тесты разговора не было. Если делать, то смысл есть только в чистых функциях
без D-Bus и GTK: `UpDevice.get_time_text/get_icon_name/get_percent_text`,
`MediaPlayerService.get_display_text`, разбор `xesam:artist` в обоих видах,
`WirePlumberService.format_codec_name`, `format_volume`, `map_sink_vol_icon`,
`map_source_vol_icon`, `NetworkManagerService.ap_to_ssid`. Остальное — интеграция с живой
системой, её дешевле проверять разовыми пробами (как для 1.13, 1.14, 1.19–1.21), чем
держать в репозитории.

Способ, которым делались разовые пробы, полезно знать: отдельный `.vala`-файл с `main()`
в корне проекта, собранный напрямую valac с нужными файлами сервисов, потом удалён.
Минимальный рецепт (важны все три флага `-X`):

```
command nix-shell --run 'valac --pkg gtk4 --pkg gio-2.0 --pkg posix --pkg wireplumber-0.5 \
  --vapidir=vapi -X -DGETTEXT_PACKAGE=\"way-shell\" -X -Isrc/c -X -lm \
  -o /tmp/probe probe.vala src/services/WirePlumberService.vala src/c/way-shell-wp-helpers.c'
```

Затем `GSETTINGS_SCHEMA_DIR=$PWD/build/data /tmp/probe`, если сервис читает gschema.

В корне: `.gitignore`, `HANDOFF.md`, `LICENSE`, `README.md`, `gresources.xml`, `meson.build`,
`package.nix`, `shell.nix`, каталоги `data/`, `po/`, `src/`, `vapi/`, `.vscode/`, `build/`.

### 2.6. Оговорки в уже сделанном

Мелкие хвосты, которые сами по себе ничего не ломают, но про них лучше знать. Подробно
каждая описана в своём пункте раздела 1:

- **`IpcService`** (1.8): `chmod 0600` идёт после `add_address()`, то есть есть короткое окно
  с правами по umask; при остановке слушателя файл сокета не удаляется и IPC мёртв молча;
  вердикт о живости строится на connect с таймаутом 1 с — зависший экземпляр признается
  мёртвым.
- **`UpDevice`** (1.6): один синхронный проход по `/sys/class/power_supply/BAT0..3` всё же
  делается в конструкторе — первый снимок до ответа UPower.
- **`WebcamService`** (1.14): любой `open()` даёт `IN_OPEN`, включая чужие утилиты вроде
  `v4l2-ctl --list-devices`. Считается допустимым: если кто-то открыл камеру, показать
  иконку скорее правильно, чем нет.
- **`MediaPlayerService`** (1.13): приоритет плееров исправлен — играющий →
  `last_active_name` → любой с треком, плюс `can_go_next`/`can_go_previous` из MPRIS.
  Остаётся частный случай: если два плеера играют одновременно, выбирается первый из
  обхода `HashTable`.
- **`StatusNotifierService`** (1.21): владелец имени — мы, то есть второй трей в сессии
  работать не будет. Если владелец захочет пользоваться чужой панелью с треем —
  `gsettings set org.flaemer.way-shell.panel enable-tray-icons false` и перезапуск.
- **Запуск `way-shell` в живой панели после 1.13–1.21 не проверялся глазами.** Сборка
  чистая, бинарник стартует (в логе только известное предупреждение libadwaita, см.
  раздел 0), watcher поднимается и blueman в нём регистрируется, сервисы проверены
  разовыми пробами, но вид панели владелец ещё не смотрел. Смотреть в первую очередь:
  значок blueman в ряду (PNG рядом с symbolic), третью строку яркости в шторке,
  размер зелёного кружка камеры (`10px`), переводы в интерфейсе.
  Перезапуск заодно уберёт осиротевшие `playerctl` (владелец решил сделать это
  перезагрузкой системы).

---

## 3. Решения владельца — не откатывать

Это его осознанный выбор, а не недоделки:

- **`README.md`** — его стиль, он так пишет везде. Добавлена только одна строка
  с указанием на upstream (ldelossa) и GPL-2.0. Больше не трогать.
  Формально по GPL-2 §1/§2(a) это нужно: `LICENSE` — чистый GPL-2 с копирайтом FSF
  и без собственной строки копирайта.
- **Нет `.desktop`-файла и нет иконки.** Владелец: «это больше системная утилита
  в автозапуске это плохо чтобы в выборе приложений лежал .desktop
  для панели». В `package.nix:61` оставлен комментарий, что отсутствие намеренное.
- **Только тёмная тема.** `ThemeService` урезан с 75 до 47 строк: убраны enum `ThemeType`,
  сигнал `theme_changed` (нулевая подписка), светлая ветка (файл `way-shell-light.css`
  никогда не существовал на диске, так что включение ключа ломало тему),
  `trigger_script_async` с `bash -c`. Ключ `light-theme` удалён из gschema, тёмная
  форсируется через `Adw.StyleManager.color_scheme = FORCE_DARK` в `main.vala:20`.
- **Клик мимо трея его не закрывает.** См. 1.3.
- **Никакого `NiriClient`, `WindowManagerService`, sway.** Удалены. Оба класса были
  стабами: `request_workspaces_update()` эмитил вечно пустой массив,
  `WindowManagerService` хардкодил `new WMWorkspace("1", "eDP-1", …)`. Схема
  `org.flaemer.way-shell.window-manager` удалена целиком (в ней было
  `(default: sway)` и `Currently supported options are "sway"`, ни один ключ не читался).
  Вместе с ними ушли wlr-протоколы, см. 1.12.
- **Никакого media OSD.** См. 1.4.
- **Никакого управления музыкой в quick settings** — «дублирование в одно и то же место ибо
  на баре уже есть такое».
- **Три виджета батареи** (панель, quick settings, меню) — специально, чтобы видеть
  состояние в разных местах. См. 1.15: сводился только код.
- **Иконка камеры — зелёный кружок, как в MixerMenu**, и появляется только когда камера
  реально занята («чтобы небыло такого как всегда горит красный»). То же самое теперь
  сделано для иконки микрофона, см. 1.19.
- **Язык берётся из локали системы, своего переключателя нет** («переключаться системно
  через язык пользователя какой стоит в системе»). См. 1.16.

Состояние gschema после чистки (`data/org.flaemer.way-shell.gschema.xml`, −115 строк):
четыре схемы, пять ключей — `backlight-directory`, `keyboard-backlight-directory`
(`…system`), `do-not-disturb` (`…notifications`), `clock-format`, `enable-tray-icons`
(`…panel`). Схема верхнего уровня `org.flaemer.way-shell` пустая, без ключей —
она остаётся только как корень пути, это нормально для GSettings.
**Изменилось:** `enable-tray-icons` снова `true` по умолчанию — трей реализован (1.21).

---

## 4. Утверждения, которые владелец проверил и опроверг

Не повторять как факты:

- **Ввод пароля Wi-Fi работает**, несмотря на `KeyboardMode.NONE` в `Drawer.vala:45`.
  Утверждение, что он заблокирован, было выводом из кода, а не проверкой, и оказалось
  неверным. `ON_DEMAND` семантически корректнее, но это не блокер; оставлено как есть
  (так же в `NotificationBanner.vala:47`).
- **Мультимонитор работал** на его конфигурации из двух мониторов ещё до правок.
  Баг с `items_changed` (`Panel.vala:296`; обрабатывался только первый элемент
  `added`/`removed`, а индексы `GListModel` применялись к рассинхронизированному локальному
  `GenericArray`) был латентным — с двумя мониторами события приходят по одному. Переписан
  на диф по идентичности объектов `Gdk.Monitor`, но это была не текущая поломка.
- **OSD яркости появлялся** по горячим клавишам (`FileMonitor` видит запись `brightnessctl`).
  Сломан был только слайдер внутри шторки: `write_sysfs_value` использовал
  `replace_contents()`, то есть временный файл + rename, чего sysfs не поддерживает,
  и записи молча не срабатывали. Исправлено на `FileStream.open(…, "w")` + `printf` +
  `flush`. **Дополнено в 1.20:** на его машине и прямая запись не работает (sysfs
  `root:root 0644`, udev-правила нет), так что реально срабатывал именно фолбэк на
  `brightnessctl`. Теперь между ними стоит logind `SetBrightness`.

---

## 5. Подводные камни

- **`Posix.kill` требует `vala.find_library('posix')`** в зависимостях `meson.build`,
  иначе `error: The symbol 'Posix' could not be found`. Уже добавлено (`meson.build:20`).
  `Panel.shutdown()` больше не использует Posix (после 1.13 там только `win.destroy()`),
  но Posix нужен трём сервисам: `Posix.close` в `LogindService`, `Posix.getuid` в
  `IpcService`, `Posix.read`/`Posix.close` в `WebcamService`.
- **`vala.find_library('linux')`** добавлена рядом (`meson.build:21`) — нужна для
  `Linux.inotify_*` в `WebcamService`. Без неё `error: The namespace name 'Linux' could not be found`.
- **Не верить сырому выводу C-компилятора** как индикатору качества кода. Фильтровать
  на `^\.\./src/.*\.vala:`.
- `nix-shell` алиас у владельца сломан — вызывать `command nix-shell --run '…'` напрямую.
  Внутри `--run` шелл уже свой, там `command` нет — писать `timeout 20 env …`, а не
  `timeout 20 command …`, иначе `timeout: failed to run command 'command'`.
- `bwrap` в системе нет, терминальные команды идут без песочницы.
- **Не каждый `Timeout` — поллинг.** При проверке утверждений вида «таймер убран» не искать
  `Timeout` грепом и делать вывод по факту находки. Законные таймеры, которые легко
  принять за регрессию: `WifiButton.vala:181` (`add_seconds(3)`, одноразовый — снятие
  `ui_locked` после включения Wi-Fi, возвращает `Source.REMOVE`), `WifiButton.vala:271`
  (одноразовый рефреш списка после скана), `BluetoothButton.vala:177` (автостоп скана
  через 15 с), `BluetoothService.vala:362` (повтор после rfkill), `WirePlumberService.vala:224`
  и `:309` (дебаунс сигналов), `IpcService.vala:110` (backoff), `ClockService.vala:17,32`
  (синхронизация на границу минуты, затем тик раз в 60 с), `Osd.vala:135,178` и
  `NotificationBanner.vala:148` (таймауты автоскрытия), `NotificationWidget.vala:160`
  (обновление «N ago», снимается в `:166`), `PowerServices.vala:102` (sysfs-фолбэк,
  активен только когда UPower недоступен), `WebcamService.vala:222` (одноразовая
  задержка 400 мс перед показом иконки), `StatusNotifierService.vala:170` и `:392`
  (дебаунсы серий сигналов от значков трея). **Периодического опроса ядра в проекте
  больше не осталось** — был один, веб-камера, убран в 1.14.
- **Два разных `MediaPlayerService` в истории проекта.** Удалённый (1.4) обслуживал media OSD
  и был пустым стабом; текущий (1.13) реализует MPRIS для `media_btn`. Если владелец
  говорит «убрали плеер» — он про OSD, кнопкой в панели он пользуется.
  **Отдельно просил не возвращать OSD музыки** и не делать управление музыкой в
  quick settings: дублирование того, что уже есть на панели.
- **Детекция занятости камеры через `EBUSY` не работает**, и через PipeWire тоже неполна.
  Проверено опытом, подробности в 1.14. Не переделывать обратно.
- **А вот занятость микрофона как раз видна через PipeWire** — по узлам
  `media.class = Stream/Input/Audio` (1.19). Не переносить вывод про камеру на звук: у звука
  весь трафик идёт через PipeWire обязательно, а v4l2 можно открыть напрямую, минуя его.
- **Запись яркости в sysfs напрямую на машине владельца невозможна** без udev-правила:
  файл `root:root 0644`, группа `video` у пользователя есть, но она ничего не даёт.
  Рабочий путь — logind `Session.SetBrightness` на `/org/freedesktop/login1/session/auto`
  (1.20). Путь `/session/self` не существует, `GetSessionByPID` из шелла терминала тоже
  не работает («does not belong to any known session») — это особенность среды, а не баг.
- **`Граница между «микрофон включён» и «микрофон занят»`** — исторический источник
  путаницы. Имя `is_microphone_active` обозначало `!mute` и из-за этого сломало два виджета
  (1.19). При добавлении похожих предикатов называть их буквально.
- **В старом HANDOFF были утверждения-«мысли», написанные до правок и не обновлённые
  после.** Документ пересобран сверкой с кодом, а не редактурой прежнего текста.
  Если будете дописывать своё — пишите статус явно («сделано» / «сделано иначе» /
  «не сделано») и ссылку файл:строка, иначе следующая модель снова будет перепроверять всё.

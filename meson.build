project('way-shell', 'vala', 'c',
  version: '0.0.10',
  meson_version: '>= 0.59.0',
)

vala = meson.get_compiler('vala')

add_project_arguments(['--vapidir=' + join_paths(meson.current_source_dir(), 'vapi')], language: 'vala')
# config.vapi описывает GETTEXT_PACKAGE/LOCALEDIR из config.h; без --pkg valac
# про него не узнает, так как в sources его нет.
add_project_arguments(['--pkg', 'config'], language: 'vala')

dependencies = [
  dependency('glib-2.0'),
  dependency('gio-2.0'),
  dependency('gio-unix-2.0'),
  dependency('gobject-2.0'),
  dependency('gtk4'),
  dependency('libadwaita-1'),
  dependency('gtk4-layer-shell-0'),
  dependency('wireplumber-0.5'),
  dependency('libnm'),
  vala.find_library('posix'),
  vala.find_library('linux'),
  meson.get_compiler('c').find_library('m', required: false)
]

c_sources = [
  'src/c/way-shell-wp-helpers.c'
]

sources = [
  'src/main.vala',
  'src/services/ClockService.vala',
  'src/services/BrightnessService.vala',
  'src/services/ThemeService.vala',
  'src/services/IpcService.vala',
  'src/services/NotificationsService.vala',
  'src/services/PowerServices.vala',
  'src/services/WirePlumberService.vala',
  'src/services/NetworkManagerService.vala',
  'src/services/BluetoothService.vala',
  'src/services/WebcamService.vala',
  'src/services/MediaPlayerService.vala',
  'src/services/StatusNotifierService.vala',
  'src/services/WaylandGammaControlService.vala',
  'src/panel/quick_settings/Drawer.vala',
  'src/panel/quick_settings/Scales.vala',
  'src/panel/quick_settings/Grid.vala',
  'src/panel/quick_settings/GridButton.vala',
  'src/panel/quick_settings/GridCluster.vala',
  'src/panel/quick_settings/MenuWidget.vala',
  'src/panel/quick_settings/modules/header/BatteryButton.vala',
  'src/panel/quick_settings/modules/header/UptimeWidget.vala',
  'src/panel/quick_settings/modules/header/BatteryMenu.vala',
  'src/panel/quick_settings/modules/header/PowerMenu.vala',
  'src/panel/quick_settings/modules/header/MixerMenu.vala',
  'src/panel/quick_settings/modules/header/Header.vala',
  'src/panel/quick_settings/modules/WifiButton.vala',
  'src/panel/quick_settings/modules/EthernetButton.vala',
  'src/panel/quick_settings/modules/BluetoothButton.vala',
  'src/panel/quick_settings/modules/DndButton.vala',
  'src/osd/Osd.vala',
  'src/osd/NotificationBanner.vala',
  'src/panel/Panel.vala',
  'src/panel/Clock.vala',
  'src/panel/IndicatorBar.vala',
  'src/panel/StatusBar.vala',
  'src/panel/Mediator.vala',
  'src/panel/message_tray/Calendar.vala',
  'src/panel/message_tray/NotificationWidget.vala',
  'src/panel/message_tray/MessageTray.vala'
]

gnome = import('gnome')
i18n = import('i18n')

resources = gnome.compile_resources('gresources',
  'gresources.xml',
  source_dir: '.'
)

# Имя домена и путь к переводам уезжают в config.h, оттуда их берёт
# vapi/config.vapi и дальше main.vala в bindtextdomain().
gettext_package = meson.project_name()
conf = configuration_data()
conf.set_quoted('GETTEXT_PACKAGE', gettext_package)
conf.set_quoted('LOCALEDIR', get_option('prefix') / get_option('localedir'))
configure_file(output: 'config.h', configuration: conf)

subdir('data')
subdir('po')

executable('way-shell',
  sources,
  c_sources,
  resources,
  dependencies: dependencies,
  # valac подключает <glib/gi18n-lib.h> в каждый файл с _(), а тот требует
  # GETTEXT_PACKAGE уже на уровне препроцессора. config.h сюда не помогает:
  # его valac вставляет только там, где используется сам Config.*.
  c_args: ['-DGETTEXT_PACKAGE="' + gettext_package + '"'],
  include_directories: [include_directories('src/c'), include_directories('.')],
  install: true
)

gnome.post_install(glib_compile_schemas: true)
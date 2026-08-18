project('way-shell', 'vala', 'c',
  version: '0.0.10',
  meson_version: '>= 0.59.0',
)

vala = meson.get_compiler('vala')

add_project_arguments(['--disable-warnings', '--disable-assert'], language: 'vala')
add_project_arguments(['--vapidir=' + join_paths(meson.current_source_dir(), 'vapi')], language: 'vala')

dependencies = [
  dependency('glib-2.0'),
  dependency('gio-2.0'),
  dependency('gio-unix-2.0'),
  dependency('gobject-2.0'),
  dependency('gtk4'),
  dependency('libadwaita-1'),
  dependency('json-glib-1.0'),
  dependency('gtk4-layer-shell-0'),
  dependency('wireplumber-0.5'),
  dependency('libnm'),
  dependency('libpulse'),
  dependency('libpulse-mainloop-glib'),
  dependency('wayland-client'),
  meson.get_compiler('c').find_library('m', required: false)
]

c_sources = [
  'src/c/wlr-foreign-toplevel-management-unstable-v1.c',
  'src/c/wlr-gamma-control-unstable-v1.c',
  'src/c/way-shell-wp-helpers.c'
]

sources = [
  'src/main.vala',
  'src/services/ClockService.vala',
  'src/services/BrightnessService.vala',
  'src/services/ThemeService.vala',
  'src/services/IpcService.vala',
  'src/services/NiriClient.vala',
  'src/services/NotificationsService.vala',
  'src/services/PowerServices.vala',
  'src/services/WirePlumberService.vala',
  'src/services/NetworkManagerService.vala',
  'src/services/WlrWaylandBindings.vapi',    
  'src/services/WindowManagerService.vala',
  'src/services/StatusNotifierService.vala',
  'src/services/MediaPlayerService.vala',
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
resources = gnome.compile_resources('gresources',
  'gresources.xml',
  source_dir: '.'
)

executable('way-shell',
  sources,
  c_sources,
  resources,
  dependencies: dependencies,
  include_directories: include_directories('src/c'),
  install: true
)
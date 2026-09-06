{ lib
, stdenv
, meson
, ninja
, pkg-config
, vala
, wrapGAppsHook4
, glib
, gettext
, gtk4
, libadwaita
, gtk4-layer-shell
, wireplumber
, networkmanager
, upower
, brightnessctl
, util-linux
, fetchFromGitHub
}:

stdenv.mkDerivation rec {
  pname = "way-shell";
  version = "0.0.10";

  src = fetchFromGitHub {
    owner = "flaemer-idk";
    repo = "way-shell-maybe-forkflaemer";
    # Пин по коммиту: rev = "main" не воспроизводится, main двигается.
    rev = "5a7827c";
    hash = "sha256-Ifkrh+zLEgK6IbuHBkEYRPGASLEZ6DPoAr9MjP+0mPA=";
  };

  nativeBuildInputs = [
    meson
    ninja
    pkg-config
    vala
    wrapGAppsHook4
    glib
    # msgfmt: компиляция po/*.po в .mo на этапе сборки.
    gettext
  ];

  buildInputs = [
    glib
    gtk4
    libadwaita
    gtk4-layer-shell
    wireplumber
    networkmanager
    upower
  ];

  mesonFlags = [
    "-Db_lto=true"
    "-Dstrip=true"
    "-Db_ndebug=true"
  ];

  # -march=native убран: ломает переносимость бинарника и кэш подстановок.
  env.NIX_CFLAGS_COMPILE = "-O3 -flto";

  # Нет .desktop и иконки сознательно: это системная оболочка в автозапуске
  # композитора, а не приложение для меню запуска.
  # gschema устанавливается и компилируется самим meson (data/meson.build
  # + gnome.post_install), поэтому ручной postInstall больше не нужен.

  # bluez из PATH убран: BluetoothService говорит с BlueZ по D-Bus, спавна
  # bluetoothctl больше нет. rfkill (из util-linux) нужен только чтобы снять
  # софт-блок, когда сам BlueZ отвечает org.bluez.Error.Blocked.
  preFixup = ''
    gappsWrapperArgs+=(
      --prefix XDG_DATA_DIRS : "$out/share"
      --prefix PATH : "${lib.makeBinPath [ brightnessctl util-linux ]}"
    )
  '';

  meta = with lib; {
    description = "Lightweight Wayland shell for Niri";
    longDescription = ''
      Fork of way-shell by ldelossa (https://github.com/ldelossa/way-shell),
      rewritten from C to Vala.
    '';
    homepage = "https://github.com/flaemer-idk/way-shell-maybe-forkflaemer";
    license = licenses.gpl2Only;
    platforms = platforms.linux;
    mainProgram = "way-shell";
  };
}

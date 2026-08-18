{ lib
, stdenv
, fetchFromGitHub
, meson
, ninja
, pkg-config
, vala
, wrapGAppsHook4
, glib
, gtk4
, libadwaita
, json-glib
, gtk4-layer-shell
, wireplumber
, networkmanager
, libpulseaudio
, wayland
, upower
, wayland-protocols
}:

stdenv.mkDerivation rec {
  pname = "way-shell";
  version = "6.7.67";

  src = fetchFromGitHub {
    githubBase = "codeberg.org";
    owner = "flaemer";
    repo = "way-shell-maybeforkflaemer";
    rev = "v${version}"; # либо "main", если собираете прямо из ветки main
    hash = "sha256-AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA="; # Замените на реальный хэш
  };

  nativeBuildInputs = [
    meson
    ninja
    pkg-config
    vala
    wrapGAppsHook4
  ];

  buildInputs = [
    glib
    gtk4
    libadwaita
    json-glib
    gtk4-layer-shell
    wireplumber
    networkmanager
    libpulseaudio
    wayland
    upower
    wayland-protocols
  ];

  mesonFlags = [
    "-Dbuildtype=release" 
    "-Db_lto=true"          
    "-Dstrip=true"         
    "-Db_ndebug=true"       
  ];

  NIX_CFLAGS_COMPILE = [
    "-O3"                 
    "-flto"                   
  ];

  meta = with lib; {
    description = "Lightweight Wayland shell for Niri";
    homepage = "https://github.com/flaemer-idk/way-shell-maybe-forkflaemer";
    license = licenses.gpl2Only;
    platforms = platforms.linux;
  };
}
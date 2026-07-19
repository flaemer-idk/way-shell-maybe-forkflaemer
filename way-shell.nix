{ lib
, stdenv
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
  version = "6.7";
  src = fetchFromGitHub {
    githubBase = "codeberg.org";
    owner = "flaemer";
    repo = "way-shell-maybeforkflaemer";
    rev = "main";
    hash = "sha256-";
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
    "-march=native"         
    "-flto"                   
  ];

  meta = with lib; {
    description = "Lightweight Wayland shell for Niri";
    homepage = "https://codeberg.org/flaemer/way-shell-maybeforkflaemer";
    license = licenses.gpl2Only;
    platforms = platforms.linux;
  };
}

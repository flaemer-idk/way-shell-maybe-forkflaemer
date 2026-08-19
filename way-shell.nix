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
, fetchFromGitHub
}:

stdenv.mkDerivation rec {
  pname = "way-shell";
  version = "6.7";
  src = fetchFromGitHub {
    owner = "flaemer-idk";
    repo = "way-shell-maybe-forkflaemer";
    rev = "main"; 
    hash = "sha256-Ifkrh+zLEgK6IbuHBkEYRPGASLEZ6DPoAr9MjP+0mPA="; 
  };


  nativeBuildInputs = [
    meson
    ninja
    pkg-config
    vala
    wrapGAppsHook4
    glib
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
    "-Db_lto=true"          
    "-Dstrip=true"         
    "-Db_ndebug=true"       
  ];

  NIX_CFLAGS_COMPILE = [
    "-O3"                 
    "-march=native"         
    "-flto"                   
  ];
    postInstall = ''
    mkdir -p $out/share/glib-2.0/schemas
    cp -r $src/data/*.gschema.xml $out/share/glib-2.0/schemas/
    glib-compile-schemas $out/share/glib-2.0/schemas/
  '';

  preFixup = ''
    gappsWrapperArgs+=(
      --prefix XDG_DATA_DIRS : "$out/share"
      --set ADW_DEBUG_COLOR_SCHEME "prefer-dark"
    )
  '';

  meta = with lib; {
    description = "Lightweight Wayland shell for Niri";
    homepage = "https://github.com/flaemer-idk/way-shell-maybe-forkflaemer";
    license = licenses.gpl2Only;
    platforms = platforms.linux;
  };
}

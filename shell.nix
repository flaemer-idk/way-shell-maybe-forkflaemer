{ pkgs ? import <nixpkgs> {} }:

pkgs.mkShell {
  nativeBuildInputs = with pkgs; [
    pkg-config
    meson
    ninja
    vala
    gcc
    glib
    gettext
    wrapGAppsHook4
  ];

  buildInputs = with pkgs; [
    libadwaita
    gtk4-layer-shell
    upower
    wireplumber
    pipewire
    networkmanager
  ];

  shellHook = ''
    export GIO_EXTRA_MODULES=${pkgs.glib-networking}/lib/gio/modules
    export GSETTINGS_SCHEMA_DIR=$PWD/build/data
    export WAY_SHELL_LOCALEDIR=$PWD/build/po
    export CPATH="${pkgs.pipewire.dev}/include/pipewire-0.3:${pkgs.pipewire.dev}/include/spa-0.2:$CPATH"
  '';
}

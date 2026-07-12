{ pkgs ? import <nixpkgs> {} }:

pkgs.mkShell {
  nativeBuildInputs = with pkgs; [
    pkg-config
    gnumake
    gcc
    wayland-scanner
    glib
    wrapGAppsHook4
  ];

  buildInputs = with pkgs; [
    libadwaita
    gtk4-layer-shell
    upower
    wireplumber
    pipewire        # Этого пакета достаточно, он содержит и pipewire, и spa
    json-glib
    networkmanager
    libpulseaudio
    wayland
    wayland-protocols
  ];

  shellHook = ''
    export GIO_EXTRA_MODULES=${pkgs.glib-networking}/lib/gio/modules
    export GSETTINGS_SCHEMA_DIR=$PWD/data
    
    # Берем пути для pipewire-0.3 и spa-0.2 из одного пакета pipewire.dev
    export CPATH="${pkgs.pipewire.dev}/include/pipewire-0.3:${pkgs.pipewire.dev}/include/spa-0.2:$CPATH"
  '';
}
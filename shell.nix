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
    # Схема теперь компилируется meson-ом в build/data/, а не лежит в репо.
    export GSETTINGS_SCHEMA_DIR=$PWD/build/data
    # То же для переводов: msgfmt кладёт .mo в build/po/<lang>/LC_MESSAGES/,
    # а установленного префикса при запуске из дерева ещё нет.
    export WAY_SHELL_LOCALEDIR=$PWD/build/po
    export CPATH="${pkgs.pipewire.dev}/include/pipewire-0.3:${pkgs.pipewire.dev}/include/spa-0.2:$CPATH"
  '';
}
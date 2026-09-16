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
, systemd
}:

stdenv.mkDerivation rec {
  pname = "way-shell";
  version = "67";

  # src = ./. копирует в стор всё дерево целиком, включая локальный build/ —
  # а там лежит уже сконфигурированный meson-каталог с абсолютными путями
  # хоста. Meson видит «Directory already configured», идёт в reconfigure
  # вместо чистого setup и падает с FileNotFoundError по путям вида
  # /home/.../build/meson-info/tmp_dump.json. Поэтому вырезаем build/,
  # прочие gitignored артефакты (.nix-cache, *.pot) и VCS-мусор.
  src = lib.cleanSourceWith {
    src = ./.;
    filter = name: type:
      let
        rel = lib.removePrefix (toString ./.) (toString name);
        isBuildTree = rel == "/build" || lib.hasPrefix "/build/" rel;
        isNixCache = rel == "/.nix-cache" || lib.hasPrefix "/.nix-cache/" rel;
        isGeneratedPot = lib.hasSuffix "/way-shell.pot" rel;
      in
      lib.sources.cleanSourceFilter name type
      && !isBuildTree
      && !isNixCache
      && !isGeneratedPot;
  };

  nativeBuildInputs = [
    meson
    ninja
    pkg-config
    vala
    wrapGAppsHook4
    glib
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

  env.NIX_CFLAGS_COMPILE = "-O3 -flto";

  preFixup = ''
    gappsWrapperArgs+=(
      --prefix XDG_DATA_DIRS : "$out/share"
      --prefix PATH : "${lib.makeBinPath [ brightnessctl util-linux systemd ]}"
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

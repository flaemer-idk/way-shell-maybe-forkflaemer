# NixOS-модуль оболочки.
#
# Использование через flake (configuration.nix):
#
#   inputs.way-shell.url = "github:flaemer-idk/way-shell-maybe-forkflaemer";
#   inputs.way-shell.inputs.nixpkgs.follows = "nixpkgs";  # собирать системным nixpkgs
#
#   outputs = { self, nixpkgs, way-shell }: {
#     nixosConfigurations.хост = nixpkgs.lib.nixosSystem {
#       modules = [
#         way-shell.nixosModules.default
#         { programs.way-shell.enable = true; }
#       ];
#     };
#   };
#
# После переключения бинарник доступен в PATH как `way-shell`. Автозапуск
# остаётся за конфигом композитора (niri: `spawn-at-startup "way-shell"`),
# потому что layer-shell-оболочка — это не desktop-приложение и .desktop-файла
# у неё намеренно нет.
{ lib, pkgs, config, ... }:

let
  cfg = config.programs.way-shell;
in
{
  meta.maintainers = [ ];

  options.programs.way-shell = {
    enable = lib.mkEnableOption "way-shell, a Wayland shell for Niri";

    package = lib.mkOption {
      type = lib.types.package;
      # Пакета в самом nixpkgs нет — по умолчанию собираем из этого репо.
      default = pkgs.callPackage ../package.nix { };
      defaultText = lib.literalExpression "pkgs.callPackage ../package.nix {}";
      description = "Пакет way-shell, который ставить в systemPackages.";
    };
  };

  config = lib.mkIf cfg.enable {
    environment.systemPackages = [ cfg.package ];
  };
}

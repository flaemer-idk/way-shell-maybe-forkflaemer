{
  description = "Lightweight Wayland shell for Niri (Vala fork of way-shell)";

  inputs = {
    # Можно перекрыть из своего флейка (inputs.way-shell.inputs.nixpkgs.follows = "nixpkgs"),
    # чтобы оболочка собиралась той же версией nixpkgs, что и система.
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
  };

  outputs =
    { self, nixpkgs }:
    let
      systems = [
        "x86_64-linux"
        "aarch64-linux"
      ];
      forAllSystems = nixpkgs.lib.genAttrs systems;
    in
    {
      packages = forAllSystems (
        system:
        let
          pkgs = nixpkgs.legacyPackages.${system};
          way-shell = pkgs.callPackage ./package.nix { };
        in
        {
          inherit way-shell;
          default = way-shell;
        }
      );

      # nix develop — то же окружение, что и старый добрый `nix-shell shell.nix`.
      devShells = forAllSystems (
        system:
        let
          pkgs = nixpkgs.legacyPackages.${system};
        in
        {
          default = import ./shell.nix { inherit pkgs; };
        }
      );

      # programs.way-shell.enable = true;
      nixosModules.default = import ./nix/way-shell.nix;
      # Прежнее имя модуля, для совместимости.
      nixosModule = self.nixosModules.default;

      # Удобный алиас для overlay-стиля использования:
      #   environment.systemPackages = [ way-shell.packages.${system}.default ];
      overlays.default = final: _prev: {
        way-shell = self.packages.${final.system}.default;
      };
    };
}

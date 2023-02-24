{
  description = "Redis server explorer. Explore the keys within your redis server as if it was a directory structure.";

  inputs = {
    flake-utils.url = "github:numtide/flake-utils";
    gitignore = {
      url = "github:hercules-ci/gitignore.nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
    zigpkgs.url = "github:mitchellh/zig-overlay";
  };

  outputs = { self, nixpkgs, gitignore, flake-utils, zigpkgs }:
  let
    systems = [ "x86_64-linux" ];
    inherit (gitignore.lib) gitignoreSource;
  in flake-utils.lib.eachSystem systems (system:
    let
      pkgs = nixpkgs.legacyPackages.${system};
      zig = zigpkgs.packages.${system}.master;
    in rec {
      packages.default = packages.redex;
      packages.redex = pkgs.stdenvNoCC.mkDerivation {
        name = "redex";
        src = gitignoreSource ./.;
        nativeBuildInputs = [zig];
        dontConfigure = true;
        dontInstall = true;
        buildPhase = ''
          mkdir -p "$out"
          zig build install -Doptimize=ReleaseSafe --prefix "$out"
        '';
        XDG_CACHE_HOME = ".cache";
      };

      devShell = pkgs.mkShell {
        nativeBuildInputs = with pkgs; [
          zls
        ] ++ [zig];
      };
    }
  );
}

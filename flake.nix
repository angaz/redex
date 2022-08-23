{
  description = "";
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";

    gitignore.url = "github:hercules-ci/gitignore.nix";
    gitignore.inputs.nixpkgs.follows = "nixpkgs";

    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs = { self, nixpkgs, gitignore, flake-utils }:
  let
    systems = [ "x86_64-linux" ];
    inherit (gitignore.lib) gitignoreSource;
  in flake-utils.lib.eachSystem systems (system:
    let
      pkgs = nixpkgs.legacyPackages.${system};
    in rec {
      packages.default = packages.redex;
      packages.redex = pkgs.stdenvNoCC.mkDerivation {
        name = "redex";
        src = gitignoreSource ./.;
        nativeBuildInputs = [ pkgs.zig ];
        dontConfigure = true;
        dontInstall = true;
        buildPhase = ''
          mkdir -p "$out"
          zig build install -Drelease-safe=true --prefix "$out"
        '';
        XDG_CACHE_HOME = ".cache";
      };
    }
  );
}

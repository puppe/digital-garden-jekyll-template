{
  inputs = {
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs = inputs@{ self, nixpkgs, flake-utils }:
    flake-utils.lib.eachDefaultSystem (system:
      let
        pkgs = nixpkgs.legacyPackages.${system};

        gems = pkgs.bundlerEnv {
          name = "gemset";
          inherit (pkgs) ruby;
          gemfile = ./Gemfile;
          lockfile = ./Gemfile.lock;
          gemset = ./gemset.nix;
          groups = [ "default" "production" "development" "test" ];
        };
      in {
        devShell = with pkgs;
          mkShell {
            buildInputs = [
              gems
              gems.wrappedRuby
              bundix
            ];
          };
      });
}

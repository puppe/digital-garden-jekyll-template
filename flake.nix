{
  inputs = { flake-utils.url = "github:numtide/flake-utils"; };

  outputs = inputs@{ self, nixpkgs, flake-utils }:
    {
      overlay = final: prev:
        let

          mpuppe-notes-env-fn = { bundlerEnv, ruby }:
            bundlerEnv {
              inherit ruby;
              name = "mpuppe-notes-env";
              gemdir = ./.;
              groups = [ "default" "production" "development" "test" ];
            };

          mpuppe-notes-fn = { stdenv, mpuppe-notes-env }:
            stdenv.mkDerivation {
              name = "mpuppe-notes";
              buildInputs =
                [ mpuppe-notes-env mpuppe-notes-env.wrappedRuby prev.pandoc ];
              src = ./.;
              phases = [ "unpackPhase" "buildPhase" "installPhase" ];
              buildPhase = ''
                jekyll build
              '';
              installPhase = ''
                mkdir "$out"
                cp -r _site/* "$out"
              '';

              # This is broken, and I cannot figure out why.
              # Error message:
              # incompatible character encodings: UTF-8 and ASCII-8BIT (Encoding::CompatibilityError)
              meta.broken = true;
            };
        in {
          mpuppe-notes-env = prev.callPackage mpuppe-notes-env-fn { };
          mpuppe-notes = prev.callPackage mpuppe-notes-fn {
            inherit (final) mpuppe-notes-env;
          };
        };
    } // flake-utils.lib.eachDefaultSystem (system:
      let
        pkgs = nixpkgs.legacyPackages.${system};
        packages = nixpkgs.lib.fix (final: self.overlay final pkgs);
        finalPkgs = pkgs // (nixpkgs.lib.fix (final: self.overlay final pkgs));
      in {
        inherit packages;
        devShell = with finalPkgs;
          mkShell {
            shellHook = ''
              ${finalPkgs.rsync}/bin/rsync -rlt --delete ${finalPkgs.nodePackages.katex}/lib/node_modules/katex/dist/ assets/katex
            '';
            buildInputs = [ bundix ];
            inputsFrom = [
              (mpuppe-notes.overrideAttrs (oldAttrs: { meta.broken = false; }))
            ];
          };
      });
}

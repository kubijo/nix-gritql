{
  description = "Reproducible GritQL package";

  inputs = {
    nixpkgs-pinned.url = "github:NixOS/nixpkgs/nixpkgs-unstable";

    gritql-src = {
      url = "github:biomejs/gritql/v0.0.3";
      flake = false;
    };

    tree-sitter-facade-src = {
      url = "github:getgrit/tree-sitter-facade/a26c147cea7049a5d2c42006499371b346b52648";
      flake = false;
    };

    tree-sitter-gritql-src = {
      url = "github:getgrit/tree-sitter-gritql/f9d98660bd7ae78c9211cb52e295bcd6531a8121";
      flake = false;
    };

    web-tree-sitter-src = {
      url = "github:getgrit/web-tree-sitter/9a01e452ec7288851405722e13aca08d9d90b6b1";
      flake = false;
    };
  };

  outputs =
    {
      nixpkgs-pinned,
      gritql-src,
      tree-sitter-facade-src,
      tree-sitter-gritql-src,
      web-tree-sitter-src,
      ...
    }:
    let
      inherit (nixpkgs-pinned) lib;
      artifactRelease = import ./nix/artifacts.nix;

      supportedSystems = [
        "x86_64-linux"
        "aarch64-linux"
        "aarch64-darwin"
      ];
      eachSystem = lib.genAttrs supportedSystems;
      toolPkgsFor = system: nixpkgs-pinned.legacyPackages.${system};
      sourceFor =
        toolPkgs:
        toolPkgs.callPackage ./nix/grit.nix {
          inherit
            gritql-src
            tree-sitter-facade-src
            tree-sitter-gritql-src
            web-tree-sitter-src
            ;
        };
      mkGritPrebuilt =
        { toolPkgs }:
        let
          system = toolPkgs.stdenv.hostPlatform.system;
          artifact = artifactRelease.hashes.${system} or null;
        in
        if !lib.elem system supportedSystems then
          throw "grit: unsupported platform ${system}; supported platforms are ${lib.concatStringsSep ", " supportedSystems}"
        else if !artifactRelease.enabled || artifact == null then
          throw "grit: no published prebuilt artifact for ${system}; select the source build with lib.mkGrit { inherit toolPkgs; fromSource = true; }"
        else
          toolPkgs.callPackage ./nix/grit-prebuilt.nix {
            expectedSystem = system;
            expectedSourceRev = gritql-src.rev;
            archive = toolPkgs.fetchurl {
              url = "https://github.com/kubijo/nix-gritql/releases/download/${artifactRelease.tag}/grit-${artifactRelease.version}-${system}.tar.gz";
              hash = artifact;
            };
          };
      mkGrit =
        {
          toolPkgs,
          fromSource ? false,
        }:
        let
          system = toolPkgs.stdenv.hostPlatform.system;
        in
        if !lib.elem system supportedSystems then
          throw "grit: unsupported platform ${system}; supported platforms are ${lib.concatStringsSep ", " supportedSystems}"
        else if fromSource || !artifactRelease.enabled then
          sourceFor toolPkgs
        else
          mkGritPrebuilt { inherit toolPkgs; };
      grit = eachSystem (system: mkGrit { toolPkgs = toolPkgsFor system; });
      gritSource = eachSystem (
        system:
        mkGrit {
          toolPkgs = toolPkgsFor system;
          fromSource = true;
        }
      );
      gritArtifact = eachSystem (
        system:
        import ./nix/grit-artifact.nix {
          pkgs = toolPkgsFor system;
          source = gritSource.${system};
          sourceRev = gritql-src.rev;
          nixpkgsRev = nixpkgs-pinned.rev;
          inherit system;
        }
      );
      gritLocalPrebuilt = eachSystem (
        system:
        (toolPkgsFor system).callPackage ./nix/grit-prebuilt.nix {
          archive = gritArtifact.${system};
          expectedSystem = system;
          expectedSourceRev = gritql-src.rev;
        }
      );
      runnable = package: {
        type = "app";
        program = lib.getExe package;
      };
    in
    {
      lib = {
        inherit mkGrit mkGritPrebuilt;
      };

      packages = eachSystem (system: {
        default = grit.${system};
        grit = grit.${system};
        grit-source = gritSource.${system};
        grit-artifact = gritArtifact.${system};
        grit-local-prebuilt = gritLocalPrebuilt.${system};
      });

      apps = eachSystem (system: {
        default = runnable grit.${system};
        grit = runnable grit.${system};
      });

      checks = eachSystem (system: {
        build = grit.${system};
        equivalence =
          (toolPkgsFor system).runCommand "grit-equivalence"
            {
              nativeBuildInputs = [
                gritSource.${system}
                gritLocalPrebuilt.${system}
              ];
            }
            ''
              bash ${./tests/cli-equivalence.sh} \
                ${lib.getExe gritSource.${system}} \
                ${lib.getExe gritLocalPrebuilt.${system}}
              touch "$out"
            '';
      });

      formatter = eachSystem (system: (toolPkgsFor system).nixfmt);

      devShells = eachSystem (system: {
        default = (toolPkgsFor system).mkShellNoCC {
          packages = [
            grit.${system}
            (toolPkgsFor system).just
            (toolPkgsFor system).nixfmt
          ];
        };
      });
    };
}

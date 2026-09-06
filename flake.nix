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

      supportedSystems = [
        "x86_64-linux"
        "aarch64-linux"
        "aarch64-darwin"
      ];
      eachSystem = lib.genAttrs supportedSystems;
      toolPkgsFor = system: nixpkgs-pinned.legacyPackages.${system};
      mkGrit =
        { toolPkgs }:
        toolPkgs.callPackage ./nix/grit.nix {
          inherit
            gritql-src
            tree-sitter-facade-src
            tree-sitter-gritql-src
            web-tree-sitter-src
            ;
        };
      grit = eachSystem (system: mkGrit { toolPkgs = toolPkgsFor system; });
      runnable = package: {
        type = "app";
        program = lib.getExe package;
      };
    in
    {
      lib = { inherit mkGrit; };

      packages = eachSystem (system: {
        default = grit.${system};
        grit = grit.${system};
      });

      apps = eachSystem (system: {
        default = runnable grit.${system};
        grit = runnable grit.${system};
      });

      checks = eachSystem (system: {
        build = grit.${system};
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

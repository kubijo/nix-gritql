{
  description = "nix-gritql repository QA";

  inputs = {
    repository = {
      url = "path:..";
      flake = false;
    };

    nix-tools.url = "github:kubijo/nix-tools/v0.3.0";
  };

  outputs =
    {
      nix-tools,
      repository,
      ...
    }:
    let
      inherit (nix-tools.inputs.nixpkgs-pinned) lib;
      eachSystem = lib.genAttrs nix-tools.lib.supportedSystems;
      project = eachSystem (
        system:
        import ../nix/tooling.nix {
          inherit
            lib
            nix-tools
            system
            ;
          src = repository;
        }
      );
    in
    {
      checks = eachSystem (system: project.${system}.checks);

      formatter = eachSystem (system: project.${system}.formatter);

      apps = eachSystem (system: project.${system}.apps);

      devShells = eachSystem (system: {
        default = project.${system}.toolPkgs.mkShellNoCC {
          packages = project.${system}.packages ++ [ project.${system}.toolPkgs.just ];
        };
      });
    };
}

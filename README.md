# nix-gritql

`nix-gritql` reproducibly packages the canonical, unmodified GritQL CLI.

Run the packaged CLI:

```console
nix run github:kubijo/nix-gritql#grit -- --version
```

Use a shared package set:

```nix
{
  inputs.nix-gritql = {
    url = "github:kubijo/nix-gritql";
    inputs.nixpkgs-pinned.follows = "nixpkgs-pinned";
  };

  outputs =
    { nix-gritql, nixpkgs-pinned, ... }:
    let
      system = "x86_64-linux";
      toolPkgs = nixpkgs-pinned.legacyPackages.${system};
      grit = nix-gritql.lib.mkGrit { inherit toolPkgs; };
    in
    {
      packages.${system}.grit = grit;
    };
}
```

The flake exports `packages.<system>.default`, `packages.<system>.grit`, `apps.<system>.default`, `apps.<system>.grit`,
`checks.<system>.build`, `formatter.<system>`, `devShells.<system>.default`, and `lib.mkGrit`.

`nix fmt` formats Nix files. Maintainers run `just format`, `just lint`, `just check`, `just build`, and `just smoke`.

Original repository work is Unlicensed. GritQL is MIT licensed; bundled components retain their licenses. See the
[third-party notices](THIRD_PARTY_NOTICES.md).

# nix-gritql

`nix-gritql` packages the canonical, unmodified GritQL CLI as a consumable Nix flake. Parsers are compiled in, and the
public input graph does not include repository QA tooling.

Run the packaged CLI:

```console
nix run github:kubijo/nix-gritql#grit -- --version
```

Consume the package from a shared package set:

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

The root flake exports `packages.<system>.grit`, `apps.<system>.grit`, and `lib.mkGrit`. Policy discovery, checks,
codemods, and consumer-facing runners belong in the consuming integration rather than this packaging flake.

The root `nix fmt` formats Nix files only. Maintainers use `just format`, `just lint`, `just check`, `just build`, and
`just smoke`. Repository QA uses a separate flake, keeping `nix-tools` out of the public input graph.

Repository work is Unlicensed. GritQL remains MIT licensed; parsers and dependencies keep their licenses. See the
[third-party notices](THIRD_PARTY_NOTICES.md).

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

The flake exports `packages.<system>.default`, `packages.<system>.grit`, `packages.<system>.grit-source`,
`apps.<system>.default`, `apps.<system>.grit`, `checks.<system>.build`, `checks.<system>.equivalence`,
`formatter.<system>`, `devShells.<system>.default`, and `lib.mkGrit`. Select the source build with
`lib.mkGrit { inherit toolPkgs; fromSource = true; }` or `packages.<system>.grit-source`.

Prebuilt CLI archives are staged for x86_64 Linux, aarch64 Linux, and aarch64 Darwin. Until their GitHub Release assets
and hashes are committed in `nix/artifacts.nix`, the normal package remains source-built. To bootstrap, run the manual
**Build Grit CLI artifacts** workflow on the intended commit and review its native equivalence and closure checks. Run
**Publish Grit CLI artifacts** with that successful build run ID to publish the exact tested archives. Download each
release asset, record its `nix hash file --sri` value in `nix/artifacts.nix`, set `enabled = true`, and run all three
native CI jobs before updating consumers. Artifact production always selects the source package explicitly.

`nix fmt` formats Nix files. Maintainers run `just format`, `just lint`, `just check`, `just build`, and `just smoke`.

Original repository work is Unlicensed. GritQL is MIT licensed; bundled components retain their licenses. See the
[third-party notices](THIRD_PARTY_NOTICES.md).

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
`formatter.<system>`, `devShells.<system>.default`, and `lib.mkGrit`. When the source pin matches the published archive,
`checks.<system>.published-equivalence` is also available. Select the source build with
`lib.mkGrit { inherit toolPkgs; fromSource = true; }` or `packages.<system>.grit-source`.

The default package fetches the pinned CLI archive for x86_64 Linux, aarch64 Linux, or aarch64 Darwin using the hashes
in `nix/artifacts.nix`. An unavailable or mismatched archive fails instead of compiling Rust. Release production always
selects the source package explicitly; pull request CI verifies CLI equivalence and runtime closure before publication.

To release, choose the repository version in `VERSION` and add its `CHANGELOG.md` section in a pull request. After its
native CI jobs pass, run **Release and merge** with the pull request number. The workflow publishes the verified bytes
under an immutable CLI artifact tag, commits their hashes to the same pull request, reruns native CI, then rebases the
pull request onto `main`. The repository version tag points to the hash-bearing commit and its release carries the
tested archives. Merge this workflow into `main` normally before using its button for the first release.

`nix fmt` formats Nix files. Maintainers run `just format`, `just lint`, `just check`, `just build`, and `just smoke`.

Original repository work is Unlicensed. GritQL is MIT licensed; bundled components retain their licenses. See the
[third-party notices](THIRD_PARTY_NOTICES.md).

# nix-gritql

`nix-gritql` packages canonical, unmodified GritQL. Its Nix library builds read-only checks and explicit codemod apps
from consumer-owned patterns and paths. Parsers are compiled in; checks use no remote modules.

Run the standalone CLI:

```console
nix run github:kubijo/nix-gritql#grit -- --version
```

Configure a consumer flake:

```nix
{
  inputs.grit-runner.url = "github:kubijo/nix-gritql";
  inputs.grit-runner.inputs.nixpkgs-pinned.follows = "nixpkgs-pinned";

  outputs =
    { self, grit-runner, ... }:
    let
      system = "x86_64-linux";
      project = grit-runner.lib.configure {
        inherit system;
        src = self;
        patterns = ./infra/grit;
        paths = [
          "Cargo.toml"
          "crates"
          "apps"
        ];
        exclude = [ "apps/generated/**" ];
      };
    in
    {
      checks.${system}.grit = project.checks.grit;
      apps.${system} = project.apps;
    };
}
```

`patterns` accepts a `.grit` or Markdown file, or a directory. Existing `grit.yaml` and `grit.yml` files are honored;
otherwise the runner discovers patterns and creates a store-backed Grit config. `paths` and `exclude` accept relative
paths or globs. Extra arguments use `gritArgs.common`, `.check`, and `.apply` lists.

`project.checks.grit` validates an immutable source copy. `nix run .#grit-check` checks the working tree;
`nix run .#grit-apply` alone passes `--fix`. Both find the configured root from the current directory. Telemetry and
caching are disabled.

Use named profiles when policies and codemods need separate scopes:

```nix
grit-runner.lib.configureProfiles {
  inherit system src toolPkgs;
  profiles = {
    policy = {
      patterns = ./.config/grit/policy;
      paths = [ "crates" ];
      gate = true;
    };
    rename-widget-api = {
      patterns = ./.config/grit/codemods/rename-widget-api;
      paths = [ "widgets" ];
      gate = false;
    };
  };
}
```

Every profile exports `grit-NAME-check` and `grit-NAME-apply` apps and packages. The check app previews without writing;
the apply app rewrites explicitly. Profiles default to gated and export `checks.grit-NAME`; `gate = false` omits it.

Override wrapper packages with `toolPkgs`, the CLI with `gritPackage`, or its build package set with
`lib.mkGrit { toolPkgs = ...; }`. Wrappers retain only `fd` and GNU coreutils at runtime.

Repository work is Unlicensed. GritQL remains MIT licensed; parsers and dependencies keep their licenses. See
[third-party notices](THIRD_PARTY_NOTICES.md) and the tested [`capability matrix`](tests/capabilities.json).

{
  lib,
  nix-tools,
  src,
  system,
}:

let
  toolPkgs = nix-tools.lib.toolPkgsFor system;
in

nix-tools.lib.configure {
  inherit system;
  inherit (toolPkgs) nodejs;

  inherit src;
  treeRootFile = "justfile";
  exclude = [
    "LICENSE"
    "tests/fixtures/patterns/*.grit"
    "tests/fixtures/**/untouched.txt"
  ];

  format = {
    css = true;
    html = true;
    javascript = true;
    json = true;
    justfile = true;
    markdown = true;
    nix = true;
    rust.exe = lib.getExe toolPkgs.rustfmt;
    toml = true;
    typescript = true;
    yaml = true;
  };

  lint = {
    javascript = true;
    links = {
      enable = true;
      ignoreLinks = [ "^https?://" ];
    };
    nix = true;
    typescript = true;
    workflows = true;
    yaml = true;
  };
}

{
  nix-tools,
  src,
  system,
  ...
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
    "VERSION"
  ];

  format = {
    justfile = true;
    markdown = true;
    nix = true;
    python = true;
    yaml = true;
  };

  lint = {
    links = {
      enable = true;
      ignoreLinks = [ "^https?://" ];
    };
    nix = true;
    python = true;
    workflows = true;
    yaml = true;
  };
}

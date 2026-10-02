{
  pkgs,
  source,
  sourceRev,
  nixpkgsRev,
  system,
}:

let
  inherit (builtins) toJSON;
  inherit (source) version;
  metadata = toJSON {
    format = 1;
    gritVersion = version;
    inherit sourceRev nixpkgsRev system;
    rustc = pkgs.rustc.version;
    cargo = pkgs.cargo.version;
  };
in
pkgs.runCommand "grit-${version}-${system}.tar.gz"
  {
    nativeBuildInputs = [
      pkgs.gnutar
      pkgs.gzip
    ];
  }
  ''
    mkdir -p stage/bin stage/share/licenses/grit
    cp ${source}/bin/grit stage/bin/grit
    cp ${source}/share/licenses/grit/LICENSE stage/share/licenses/grit/LICENSE
    printf '%s\n' '${metadata}' > stage/metadata.json
    chmod 755 stage/bin/grit
    tar --sort=name --mtime='@1' --owner=0 --group=0 --numeric-owner \
      -cf - -C stage . | gzip -n > "$out"
  ''

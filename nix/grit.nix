{
  lib,
  rustPlatform,
  pkg-config,
  perl,
  zlib,
  stdenv,
  libiconv,
  gritql-src,
  tree-sitter-facade-src,
  tree-sitter-gritql-src,
  web-tree-sitter-src,
}:

let
  preparedSrc = stdenv.mkDerivation {
    pname = "gritql-source";
    version = "0.0.3";
    src = gritql-src;
    dontBuild = true;
    dontFixup = true;
    installPhase = ''
      runHook preInstall
      cp -R . "$out"
      chmod -R u+w "$out"
      mkdir -p \
        "$out/vendor/tree-sitter-facade" \
        "$out/vendor/tree-sitter-gritql" \
        "$out/vendor/web-tree-sitter"
      cp -R ${tree-sitter-facade-src}/. "$out/vendor/tree-sitter-facade/"
      cp -R ${tree-sitter-gritql-src}/. "$out/vendor/tree-sitter-gritql/"
      cp -R ${web-tree-sitter-src}/. "$out/vendor/web-tree-sitter/"
      runHook postInstall
    '';
  };
in
rustPlatform.buildRustPackage {
  pname = "grit";
  version = "0.0.3";
  src = preparedSrc;

  cargoHash = "sha256-crK2HXhYTqfzYgLS+TJVm9MEN/oDw9QtVfYG3Jl0tHM=";
  cargoBuildFlags = [
    "--package"
    "grit"
  ];
  # cargo-auditable 0.7.5 misreads locked `dep:` features.
  auditable = false;
  doCheck = false;

  nativeBuildInputs = [
    perl
    pkg-config
  ];
  buildInputs = [ zlib ] ++ lib.optionals stdenv.hostPlatform.isDarwin [ libiconv ];

  postInstall = ''
    install -Dm644 LICENSE "$out/share/licenses/grit/LICENSE"
  '';

  passthru = {
    inherit preparedSrc;
    upstreamSrc = gritql-src;
    upstreamTag = "v0.0.3";
    vendorSources = {
      tree-sitter-facade = tree-sitter-facade-src;
      tree-sitter-gritql = tree-sitter-gritql-src;
      web-tree-sitter = web-tree-sitter-src;
    };
  };

  meta = {
    description = "Structural search, lint, and codemod CLI";
    homepage = "https://docs.grit.io/";
    license = lib.licenses.mit;
    mainProgram = "grit";
    platforms = [
      "x86_64-linux"
      "aarch64-linux"
      "aarch64-darwin"
    ];
    sourceProvenance = [ lib.sourceTypes.fromSource ];
  };
}

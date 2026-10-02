{
  lib,
  stdenv,
  autoPatchelfHook,
  jq,
  zlib,
  libiconv,
  darwin,
  archive,
  expectedSystem,
  expectedSourceRev,
}:

stdenv.mkDerivation {
  pname = "grit";
  version = "0.0.3";
  src = archive;

  dontConfigure = true;
  dontBuild = true;
  doInstallCheck = true;
  nativeBuildInputs = [
    jq
  ]
  ++ lib.optionals stdenv.hostPlatform.isLinux [ autoPatchelfHook ]
  ++ lib.optionals stdenv.hostPlatform.isDarwin [ darwin.autoSignDarwinBinariesHook ];
  buildInputs = [
    stdenv.cc.cc.lib
    zlib
  ]
  ++ lib.optionals stdenv.hostPlatform.isDarwin [ libiconv ];

  unpackPhase = ''
    runHook preUnpack
    mkdir source
    tar -xzf "$src" -C source
    cd source
    runHook postUnpack
  '';
  installPhase = ''
    runHook preInstall
    jq -e \
      --arg system '${expectedSystem}' \
      --arg rev '${expectedSourceRev}' \
      '.format == 1 and .gritVersion == "0.0.3" and .system == $system and .sourceRev == $rev' \
      metadata.json > /dev/null
    install -Dm755 bin/grit "$out/bin/grit"
    install -Dm644 share/licenses/grit/LICENSE "$out/share/licenses/grit/LICENSE"
    install -Dm644 metadata.json "$out/share/grit/metadata.json"
    runHook postInstall
  '';
  postFixup = lib.optionalString stdenv.hostPlatform.isDarwin ''
    while read -r dependency; do
      case "$dependency" in
        /nix/store/* | @rpath/*)
          name="''${dependency##*/}"
          replacement=""
          for root in ${libiconv} ${zlib} ${stdenv.cc.cc.lib}; do
            if test -f "$root/lib/$name"; then
              replacement="$root/lib/$name"
              break
            fi
          done
          if test -z "$replacement"; then
            echo "grit: unresolved Darwin library $dependency" >&2
            exit 1
          fi
          install_name_tool -change "$dependency" "$replacement" "$out/bin/grit"
          ;;
      esac
    done < <(otool -L "$out/bin/grit" | awk 'NR > 1 { print $1 }')
    while read -r rpath; do
      case "$rpath" in
        /nix/store/*) install_name_tool -delete_rpath "$rpath" "$out/bin/grit" ;;
      esac
    done < <(otool -l "$out/bin/grit" | awk '/cmd LC_RPATH/ { getline; getline; print $2 }')
  '';
  installCheckPhase = ''
    "$out/bin/grit" --version > /dev/null
  '';

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
  };
}

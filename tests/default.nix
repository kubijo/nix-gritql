{
  api,
  lib,
  qualityChecks,
  self,
  system,
  toolPkgs,
}:

let
  fixtureRoot = ./fixtures;
  patterns = fixtureRoot + "/patterns";
  gritPackage = self.packages.${system}.grit;
  configure =
    src:
    api.configure {
      inherit
        patterns
        src
        system
        ;
      paths = [
        "src one"
        "src-two"
      ];
      exclude = [ "src-two/excluded.js" ];
      gritArgs.common = [
        "--log-level"
        "info"
      ];
    };
  cleanProject = configure (fixtureRoot + "/clean");
  violationProject = configure (fixtureRoot + "/violation");
  singleFileProject = api.configure {
    inherit system;
    src = fixtureRoot + "/clean";
    patterns = patterns + "/javascript.grit";
    paths = [ "src one/example.js" ];
  };
  fakeGrit = toolPkgs.writeShellApplication {
    name = "grit";
    text = ''
      : > "''${FAKE_GRIT_MARKER:?}"
    '';
    meta.mainProgram = "grit";
  };
  overriddenProject = api.configure {
    inherit patterns system;
    src = fixtureRoot + "/clean";
    gritPackage = fakeGrit;
    paths = [ "src one/example.js" ];
  };
  customFd = toolPkgs.writeShellApplication {
    name = "fd";
    text = ''
      : > "''${CUSTOM_FD_MARKER:?}"
      root=.
      for argument in "$@"; do
        root=$argument
      done
      printf '%s\0' "$root/flake.nix"
    '';
    meta.mainProgram = "fd";
  };
  minimalToolPkgs = {
    inherit (toolPkgs)
      coreutils
      formats
      runCommandLocal
      writeShellApplication
      ;
    fd = customFd;
  };
  toolSetProject = api.configure {
    inherit patterns system;
    src = fixtureRoot + "/clean";
    gritPackage = fakeGrit;
    paths = [ "." ];
    toolPkgs = minimalToolPkgs;
  };
  closure = toolPkgs.closureInfo { rootPaths = [ gritPackage ]; };
in
toolPkgs.runCommandLocal "grit-runner-tests"
  {
    nativeBuildInputs = with toolPkgs; [
      coreutils
      diffutils
      findutils
      gnugrep
      jq
    ];
  }
  ''
    echo 'test: packaged CLI and license'
    test -e ${qualityChecks.formatting}
    test -e ${qualityChecks.linting}
    test -e ${cleanProject.checks.grit}
    test -e ${singleFileProject.checks.grit}

    test -x ${lib.getExe gritPackage}
    ${lib.getExe gritPackage} --version | grep -Fx 'grit 0.1.1'
    test -f ${gritPackage}/share/licenses/grit/LICENSE

    echo 'test: runtime closure'
    ! grep -E '/(nodejs|tree-sitter)-' ${closure}/store-paths

    echo 'test: capability matrix'
    jq -e '
      (.schemaVersion == 1) and
      (.languages | keys | length == 9) and
      ([.languages[] |
        .filenameDetection,
        .structuralMatching,
        .lintDiagnostics,
        .rewrites,
        .preservesUnrelatedText] | all) and
      (.packagedLanguages | sort == ([
        "css", "json", "solidity", "yaml", "hcl", "javascript",
        "typescript", "tsx", "html", "java", "kotlin", "csharp",
        "python", "markdown", "go", "rust", "ruby", "elixir", "sql",
        "vue", "toml", "php"
      ] | sort))
    ' ${./capabilities.json} >/dev/null

    echo 'test: canonical source assembly'
    mkdir "$TMPDIR/upstream" "$TMPDIR/prepared"
    cp -R ${gritPackage.upstreamSrc}/. "$TMPDIR/upstream/"
    cp -R ${gritPackage.preparedSrc}/. "$TMPDIR/prepared/"
    chmod -R u+w "$TMPDIR/upstream" "$TMPDIR/prepared"
    rm -rf "$TMPDIR/upstream/vendor" "$TMPDIR/prepared/vendor"
    diff -qr "$TMPDIR/upstream" "$TMPDIR/prepared"
    diff -qr ${gritPackage.vendorSources.tree-sitter-facade} \
      ${gritPackage.preparedSrc}/vendor/tree-sitter-facade
    diff -qr ${gritPackage.vendorSources.tree-sitter-gritql} \
      ${gritPackage.preparedSrc}/vendor/tree-sitter-gritql
    diff -qr ${gritPackage.vendorSources.web-tree-sitter} \
      ${gritPackage.preparedSrc}/vendor/web-tree-sitter

    echo 'test: read-only violation check'
    work="$TMPDIR/read-only"
    mkdir "$work"
    cp -R ${fixtureRoot + "/violation"}/. "$work/"
    chmod -R u+w "$work"
    before=$(find "$work" -type f -print0 | sort -z | xargs -0 sha256sum)
    cd "$work/src one"
    if ${lib.getExe violationProject.packages.grit-check} \
      >"$TMPDIR/check.out" 2>&1; then
      echo 'expected the violation check to fail' >&2
      exit 1
    fi
    after=$(find "$work" -type f -print0 | sort -z | xargs -0 sha256sum)
    if [[ "$before" != "$after" ]]; then
      echo 'read-only check changed the source tree' >&2
      diff -qr ${fixtureRoot + "/violation"} "$work" || true
      exit 1
    fi
    for file in \
      example.css example.html example.js example.ts example.tsx \
      example.json example.yaml example.rs example.toml
    do
      if ! grep -F "$file" "$TMPDIR/check.out" >/dev/null; then
        echo "missing diagnostic for $file" >&2
        cat "$TMPDIR/check.out" >&2
        exit 1
      fi
    done
    if grep -F excluded.js "$TMPDIR/check.out" >/dev/null; then
      echo 'excluded.js unexpectedly appeared in diagnostics' >&2
      cat "$TMPDIR/check.out" >&2
      exit 1
    fi
    diff -qr ${fixtureRoot + "/violation"} "$work"

    echo 'test: explicit golden codemod'
    work="$TMPDIR/apply"
    mkdir "$work"
    cp -R ${fixtureRoot + "/violation"}/. "$work/"
    chmod -R u+w "$work"
    cd "$work/src-two"
    ${lib.getExe violationProject.packages.grit-apply}
    diff -qr ${fixtureRoot + "/golden"} "$work"
    grep -F 'legacyJs(99)' "$work/src-two/excluded.js" >/dev/null
    ${lib.getExe violationProject.packages.grit-check}

    echo 'test: package and tool-set overrides'
    export FAKE_GRIT_MARKER="$TMPDIR/fake-grit"
    cd ${fixtureRoot + "/clean"}
    ${lib.getExe overriddenProject.packages.grit-check}
    test -e "$FAKE_GRIT_MARKER"

    rm "$FAKE_GRIT_MARKER"
    export CUSTOM_FD_MARKER="$TMPDIR/custom-fd"
    ${lib.getExe toolSetProject.packages.grit-check}
    test -e "$FAKE_GRIT_MARKER"
    test -e "$CUSTOM_FD_MARKER"

    echo 'test: all consumer fixtures passed'
    touch "$out"
  ''

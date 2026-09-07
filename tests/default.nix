{
  api,
  lib,
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
      gritArgs = {
        common = [
          "--log-level"
          "info"
        ];
        check = [ "--verbose" ];
        apply = [ "--verbose" ];
      };
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
      printf 'fd\n' >> "''${CUSTOM_FD_MARKER:?}"
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
  discoverySource = fixtureRoot + "/discovery/input";
  discoveryProject = api.configure {
    inherit system;
    src = discoverySource;
    patterns = patterns + "/javascript.grit";
    paths = [ "targets with spaces" ];
    exclude = [ "targets with spaces/excluded.js" ];
  };
  profileSource = fixtureRoot + "/profiles/input";
  profileProject = api.configureProfiles {
    inherit system toolPkgs;
    src = profileSource;
    profiles = {
      js-policy = {
        patterns = patterns + "/javascript.grit";
        paths = [ "policy one" ];
        exclude = [ "policy one/excluded.js" ];
        gate = true;
      };
      rust-policy = {
        patterns = patterns + "/rust.grit";
        paths = [ "policy two" ];
        exclude = [ "policy two/excluded.rs" ];
        gate = true;
      };
      rename-js = {
        patterns = patterns + "/javascript.grit";
        paths = [ "codemods one" ];
        exclude = [ "codemods one/excluded.js" ];
        gate = false;
      };
      rename-rust = {
        patterns = patterns + "/rust.grit";
        paths = [ "codemods two" ];
        exclude = [ "codemods two/excluded.rs" ];
        gate = false;
      };
      override-probe = {
        patterns = patterns + "/javascript.grit";
        paths = [ "codemods one/change.js" ];
        gritPackage = profileGrit;
        gritArgs = {
          common = [ "--log-level=debug" ];
          check = [ "--verbose" ];
          apply = [ "--log-level=warn" ];
        };
        gate = false;
      };
    };
  };
  profileGrit = toolPkgs.writeShellApplication {
    name = "grit";
    text = ''
      printf '%s\n' "$@" > "''${PROFILE_ARGS_MARKER:?}"
      echo 'profile diagnostic' >&2
      exit "''${PROFILE_EXIT_CODE:-37}"
    '';
    meta.mainProgram = "grit";
  };
  toolSetProfiles = api.configureProfiles {
    inherit system;
    src = fixtureRoot + "/clean";
    toolPkgs = minimalToolPkgs;
    profiles = {
      tool-a = {
        inherit patterns;
        paths = [ "." ];
        gritPackage = fakeGrit;
        gate = false;
      };
      tool-b = {
        inherit patterns;
        paths = [ "." ];
        gritPackage = fakeGrit;
        gate = false;
      };
    };
  };
  invalidProfileName = builtins.tryEval (
    builtins.deepSeq (api.configureProfiles {
      inherit system toolPkgs;
      src = profileSource;
      profiles."bad/name" = {
        inherit patterns;
      };
    }) true
  );
  sharedProfileOverride = builtins.tryEval (
    builtins.deepSeq (api.configureProfiles {
      inherit system toolPkgs;
      src = profileSource;
      profiles.bad = {
        inherit patterns;
        src = fixtureRoot + "/clean";
      };
    }) true
  );
  invalidGate = builtins.tryEval (
    builtins.deepSeq (api.configureProfiles {
      inherit system toolPkgs;
      src = profileSource;
      profiles.bad = {
        inherit patterns;
        gate = "yes";
      };
    }) true
  );
  emptyProfiles = builtins.tryEval (
    builtins.deepSeq (api.configureProfiles {
      inherit system toolPkgs;
      src = profileSource;
      profiles = { };
    }) true
  );
  invalidProfileValue = builtins.tryEval (
    builtins.deepSeq (api.configureProfiles {
      inherit system toolPkgs;
      src = profileSource;
      profiles.bad = "not an attribute set";
    }) true
  );
  invalidArgs =
    gritArgs:
    builtins.tryEval (
      builtins.deepSeq (api.configure {
        inherit
          gritArgs
          patterns
          system
          ;
        src = fixtureRoot + "/clean";
        paths = [ "." ];
      }) true
    );
  helpArgs = invalidArgs { common = [ "--help" ]; };
  positionalArgs = invalidArgs { check = [ "../outside" ]; };
  scopeReducingArgs = invalidArgs {
    apply = [
      "--only-in-json"
      "[]"
    ];
  };
  missingLogLevelValue = invalidArgs { common = [ "--log-level" ]; };
  githubActionsArgs = invalidArgs { check = [ "--github-actions" ]; };
  legacyNames =
    builtins.attrNames singleFileProject.checks == [ "grit" ]
    &&
      builtins.attrNames singleFileProject.apps == [
        "grit-apply"
        "grit-check"
      ]
    &&
      builtins.attrNames singleFileProject.packages == [
        "grit-apply"
        "grit-check"
      ];
  profilePackageNames = builtins.attrNames profileProject.packages;
  profileNames =
    builtins.attrNames profileProject.checks == [
      "grit-js-policy"
      "grit-rust-policy"
    ]
    && builtins.attrNames profileProject.apps == profilePackageNames
    &&
      profilePackageNames == [
        "grit-js-policy-apply"
        "grit-js-policy-check"
        "grit-override-probe-apply"
        "grit-override-probe-check"
        "grit-rename-js-apply"
        "grit-rename-js-check"
        "grit-rename-rust-apply"
        "grit-rename-rust-check"
        "grit-rust-policy-apply"
        "grit-rust-policy-check"
      ]
    && lib.all (
      name:
      profileProject.apps.${name}.program == lib.getExe profileProject.packages.${name}
      && profileProject.packages.${name}.name == name
    ) profilePackageNames;
  closure = toolPkgs.closureInfo { rootPaths = [ gritPackage ]; };
in
assert legacyNames;
assert profileNames;
assert !invalidProfileName.success;
assert !sharedProfileOverride.success;
assert !invalidGate.success;
assert !emptyProfiles.success;
assert !invalidProfileValue.success;
assert !helpArgs.success;
assert !positionalArgs.success;
assert !scopeReducingArgs.success;
assert !missingLogLevelValue.success;
assert !githubActionsArgs.success;
toolPkgs.runCommandLocal "grit-runner-tests"
  {
    nativeBuildInputs = with toolPkgs; [
      coreutils
      diffutils
      findutils
      gitMinimal
      gnugrep
      jq
    ];
  }
  ''
    echo 'test: public input graph'
    jq -e '
      (.nodes.root.inputs | has("nix-tools") | not) and
      ([.nodes[] |
        select(.locked.owner? == "kubijo" and .locked.repo? == "nix-tools")
      ] | length == 0)
    ' ${../flake.lock} >/dev/null

    echo 'test: packaged CLI and license'
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

    echo 'test: deterministic target discovery'
    work="$TMPDIR/discovery"
    project="$work/project"
    consumer_home="$work/home"
    mkdir -p "$project" "$consumer_home"
    cp -R ${discoverySource}/. "$project/"
    chmod -R u+w "$project"

    HOME="$consumer_home" git -C "$project" init -q
    HOME="$consumer_home" git -C "$project" add .
    HOME="$consumer_home" git -C "$project" \
      -c user.name=Fixture -c user.email=fixture@example.invalid \
      -c commit.gpgsign=false commit -qm initial

    printf 'global.js\n' > "$consumer_home/global-ignore"
    HOME="$consumer_home" git config --global \
      core.excludesFile "$consumer_home/global-ignore"
    printf 'parent.js\n' > "$work/.ignore"
    printf 'private.js\n' > "$project/.git/info/exclude"
    printf 'const hidden = legacyJs(5);\n' > "$project/.git/hidden.js"

    for file in global.js parent.js private.js excluded.js; do
      HOME="$consumer_home" git -C "$project" ls-files --error-unmatch \
        "targets with spaces/$file" >/dev/null
    done

    ${lib.getExe toolPkgs.fd} --hidden --no-require-git --type file \
      --absolute-path --exclude .git . "$project" > "$TMPDIR/ambient-fd.out"
    for file in global.js parent.js private.js; do
      ! grep -F "/$file" "$TMPDIR/ambient-fd.out" >/dev/null
    done

    cd "$project/targets with spaces"
    before=$(find "$project" -type f -print0 | sort -z | xargs -0 sha256sum)
    set +e
    HOME="$consumer_home" ${lib.getExe discoveryProject.packages.grit-check} \
      > "$TMPDIR/discovery-check.out" 2>&1
    status=$?
    set -e
    test "$status" -ne 0
    after=$(find "$project" -type f -print0 | sort -z | xargs -0 sha256sum)
    test "$before" = "$after"

    HOME="$consumer_home" ${lib.getExe discoveryProject.packages.grit-apply} \
      > "$TMPDIR/discovery-apply.out" 2>&1
    diff -qr --exclude=.git ${fixtureRoot + "/discovery/golden"} "$project"
    grep -F 'legacyJs(5)' "$project/.git/hidden.js" >/dev/null

    for file in global.js parent.js private.js; do
      grep -F "$file" "$TMPDIR/discovery-check.out" >/dev/null
      grep -F "$file" "$TMPDIR/discovery-apply.out" >/dev/null
    done
    ! grep -F 'excluded.js' "$TMPDIR/discovery-check.out" >/dev/null
    ! grep -F 'excluded.js' "$TMPDIR/discovery-apply.out" >/dev/null
    ! grep -F '.git/hidden.js' "$TMPDIR/discovery-check.out" >/dev/null
    ! grep -F '.git/hidden.js' "$TMPDIR/discovery-apply.out" >/dev/null
    HOME="$consumer_home" ${lib.getExe discoveryProject.packages.grit-check}

    echo 'test: named profiles'
    test -e ${profileProject.checks.grit-js-policy}
    test -e ${profileProject.checks.grit-rust-policy}
    cd "${profileSource}/policy one"
    ${lib.getExe profileProject.packages.grit-js-policy-check}
    cd "${profileSource}/policy two"
    ${lib.getExe profileProject.packages.grit-rust-policy-check}

    echo 'test: codemod preview and isolation'
    work="$TMPDIR/profile"
    mkdir "$work"
    cp -R ${profileSource}/. "$work/"
    chmod -R u+w "$work"
    before=$(find "$work" -type f -print0 | sort -z | xargs -0 sha256sum)
    cd "$work/codemods one"

    set +e
    ${lib.getExe profileProject.packages.grit-rename-js-apply} ../codemods\ two \
      >"$TMPDIR/runtime-scope.out" 2>&1
    status=$?
    set -e
    test "$status" -eq 2
    grep -F 'runtime arguments are not supported' "$TMPDIR/runtime-scope.out" >/dev/null
    after=$(find "$work" -type f -print0 | sort -z | xargs -0 sha256sum)
    test "$before" = "$after"

    set +e
    ${lib.getExe profileProject.packages.grit-rename-js-check} \
      >"$TMPDIR/profile-preview.out" 2>&1
    status=$?
    set -e
    if [[ $status -eq 0 ]]; then
      echo 'expected the codemod preview to find a rewrite' >&2
      exit 1
    fi
    after=$(find "$work" -type f -print0 | sort -z | xargs -0 sha256sum)
    test "$before" = "$after"
    diff -qr ${profileSource} "$work"

    ${lib.getExe profileProject.packages.grit-rename-js-apply}
    diff -qr ${fixtureRoot + "/profiles/after-rename-js"} "$work"
    ${lib.getExe profileProject.packages.grit-rename-js-check}
    if ${lib.getExe profileProject.packages.grit-rename-rust-check} \
      >"$TMPDIR/other-profile.out" 2>&1; then
      echo 'expected the untouched Rust codemod to find a rewrite' >&2
      exit 1
    fi
    grep -F 'change.rs' "$TMPDIR/other-profile.out" >/dev/null
    ! grep -F 'excluded.rs' "$TMPDIR/other-profile.out" >/dev/null

    echo 'test: profile arguments and exit codes'
    export PROFILE_ARGS_MARKER="$TMPDIR/profile-args"
    cd ${profileSource}
    set +e
    PROFILE_EXIT_CODE=37 \
      ${lib.getExe profileProject.packages.grit-override-probe-check} \
      >"$TMPDIR/profile-exit.out" 2>&1
    status=$?
    set -e
    test "$status" -eq 37
    test "$(cat "$TMPDIR/profile-exit.out")" = 'profile diagnostic'
    grep -Fx -- '--log-level=debug' "$PROFILE_ARGS_MARKER" >/dev/null
    grep -Fx -- '--verbose' "$PROFILE_ARGS_MARKER" >/dev/null
    ! grep -Fx -- '--log-level=warn' "$PROFILE_ARGS_MARKER" >/dev/null
    ! grep -Fx -- '--fix' "$PROFILE_ARGS_MARKER" >/dev/null

    set +e
    PROFILE_EXIT_CODE=41 \
      ${lib.getExe profileProject.packages.grit-override-probe-apply} \
      >"$TMPDIR/profile-exit.out" 2>&1
    status=$?
    set -e
    test "$status" -eq 41
    test "$(cat "$TMPDIR/profile-exit.out")" = 'profile diagnostic'
    grep -Fx -- '--log-level=debug' "$PROFILE_ARGS_MARKER" >/dev/null
    grep -Fx -- '--log-level=warn' "$PROFILE_ARGS_MARKER" >/dev/null
    grep -Fx -- '--fix' "$PROFILE_ARGS_MARKER" >/dev/null
    ! grep -Fx -- '--verbose' "$PROFILE_ARGS_MARKER" >/dev/null

    echo 'test: shared profile tool set'
    export FAKE_GRIT_MARKER="$TMPDIR/fake-grit"
    export CUSTOM_FD_MARKER="$TMPDIR/profile-fd"
    : > "$CUSTOM_FD_MARKER"
    cd ${fixtureRoot + "/clean"}
    ${lib.getExe toolSetProfiles.packages.grit-tool-a-check}
    ${lib.getExe toolSetProfiles.packages.grit-tool-b-check}
    test "$(grep -c '^fd$' "$CUSTOM_FD_MARKER")" -eq 2

    echo 'test: read-only violation check'
    work="$TMPDIR/read-only"
    mkdir "$work"
    cp -R ${fixtureRoot + "/violation"}/. "$work/"
    chmod -R u+w "$work"
    before=$(find "$work" -type f -print0 | sort -z | xargs -0 sha256sum)
    cd "$work/src one"
    set +e
    ${lib.getExe violationProject.packages.grit-check} --help \
      >"$TMPDIR/runtime-help.out" 2>&1
    status=$?
    set -e
    test "$status" -eq 2
    grep -F 'runtime arguments are not supported' "$TMPDIR/runtime-help.out" >/dev/null

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

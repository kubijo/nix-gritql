{
  lib,
  mkGrit,
  supportedSystems,
  toolPkgsFor,
}:
let
  isRelative =
    value:
    lib.isString value
    && value != ""
    && !(lib.hasPrefix "/" value)
    && lib.all (part: part != "..") (lib.splitString "/" value);

  rejected =
    args: names:
    lib.filter (arg: lib.any (name: arg == name || lib.hasPrefix "${name}=" arg) names) args;

  runnable = package: {
    type = "app";
    program = lib.getExe package;
  };
in
rec {
  inherit mkGrit;

  configure =
    {
      system,
      src,
      patterns,
      paths ? [ "." ],
      exclude ? [ ],
      treeRootFile ? "flake.nix",
      level ? "info",
      gritArgs ? { },
      toolPkgs ? toolPkgsFor system,
      gritPackage ? mkGrit { inherit toolPkgs; },
    }:
    let
      commonArgs = gritArgs.common or [ ];
      checkArgs = gritArgs.check or [ ];
      applyArgs = gritArgs.apply or [ ];
      patternPath = toString patterns;
      patternType = builtins.readFileType patterns;
      patternName = builtins.baseNameOf patternPath;
      extension = name: lib.last (lib.splitString "." name);
      supportedPatternFile =
        name:
        lib.elem (extension name) [
          "grit"
          "md"
        ];
      walk =
        directory: prefix:
        lib.concatLists (
          lib.mapAttrsToList (
            name: type:
            if type == "directory" then
              walk (directory + "/${name}") "${prefix}${name}/"
            else
              lib.optional (type == "regular" && supportedPatternFile name) {
                path = directory + "/${name}";
                relative = "${prefix}${name}";
              }
          ) (builtins.readDir directory)
        );
      discovered =
        if patternType == "directory" then
          walk patterns ""
        else
          [
            {
              path = patterns;
              relative = patternName;
            }
          ];
      canonicalConfig =
        patternType == "directory"
        && (builtins.pathExists (patterns + "/grit.yaml") || builtins.pathExists (patterns + "/grit.yml"));
      configEntries = map (
        file:
        if extension file.relative == "md" then
          {
            file = "patterns/${file.relative}";
            inherit level;
          }
        else
          {
            name = "runner_${builtins.substring 0 16 (builtins.hashString "sha256" file.relative)}";
            inherit level;
            body = builtins.readFile file.path;
          }
      ) discovered;
      generatedConfig = (toolPkgs.formats.yaml { }).generate "grit.yaml" {
        version = "0.0.3";
        patterns = configEntries;
      };
      patternRoot = toolPkgs.runCommandLocal "grit-runner-patterns" { } (
        if canonicalConfig then
          ''
            mkdir -p "$out/.grit"
            cp -R ${patterns}/. "$out/.grit/"
          ''
        else
          ''
            mkdir -p "$out/.grit/patterns"
            ${
              if patternType == "directory" then
                ''cp -R ${patterns}/. "$out/.grit/patterns/"''
              else
                ''cp ${patterns} "$out/.grit/patterns/"''
            }
            cp ${generatedConfig} "$out/.grit/grit.yaml"
          ''
      );
      selectors = lib.escapeShellArgs paths;
      exclusions = lib.escapeShellArgs exclude;
      mkRunner =
        {
          name,
          fix,
          extraArgs,
        }:
        toolPkgs.writeShellApplication {
          inherit name;
          excludeShellChecks = [ "SC2053" ];
          runtimeInputs = [
            toolPkgs.coreutils
            toolPkgs.fd
          ];
          runtimeEnv.GRIT_TELEMETRY_DISABLED = "true";
          text = ''
            root=$PWD
            root_marker=${lib.escapeShellArg treeRootFile}
            while [[ ! -e "$root/$root_marker" ]]; do
              if [[ "$root" == / ]]; then
                echo "${name}: could not find project root marker '$root_marker' above '$PWD'" >&2
                exit 1
              fi
              root="''${root%/*}"
              [[ -n "$root" ]] || root=/
            done

            selectors=( ${selectors} )
            exclusions=( ${exclusions} )
            selected=()
            declare -A seen=()

            while IFS= read -r -d ''' file; do
              relative="''${file#"$root"/}"
              include_file=false
              for selector in "''${selectors[@]}"; do
                normalized="''${selector#./}"
                if [[ "$selector" == "." ]]; then
                  include_file=true
                elif [[ -f "$root/$selector" && "$relative" == "$normalized" ]]; then
                  include_file=true
                elif [[ -d "$root/$selector" && "$relative" == "$normalized/"* ]]; then
                  include_file=true
                elif [[ "$relative" == $normalized ]]; then
                  include_file=true
                fi
                $include_file && break
              done
              $include_file || continue

              excluded=false
              for exclusion in "''${exclusions[@]}"; do
                normalized="''${exclusion#./}"
                if [[ -d "$root/$exclusion" && "$relative" == "$normalized/"* ]]; then
                  excluded=true
                elif [[ "$relative" == $normalized ]]; then
                  excluded=true
                fi
                $excluded && break
              done
              $excluded && continue

              if [[ -z "''${seen[$file]+present}" ]]; then
                selected+=("$file")
                seen[$file]=1
              fi
            done < <(fd --hidden --no-require-git --type file --print0 --absolute-path --exclude .git . "$root")

            if [[ ''${#selected[@]} -eq 0 ]]; then
              echo "${name}: no files matched the configured paths"
              exit 0
            fi

            state=$(mktemp -d "''${TMPDIR:-/tmp}/${name}.XXXXXX")
            trap 'rm -rf "$state"' EXIT
            export HOME="$state/home"
            export XDG_CACHE_HOME="$state/cache"
            export GRIT_CACHE_DIR="$state/grit-cache"
            mkdir -p "$HOME" "$XDG_CACHE_HOME" "$GRIT_CACHE_DIR"
            cd ${patternRoot}

            set +e
            ${lib.getExe gritPackage} ${lib.escapeShellArgs commonArgs} check \
              --no-cache --level ${lib.escapeShellArg level} \
              ${lib.optionalString fix "--fix"} \
              ${lib.escapeShellArgs extraArgs} -- "''${selected[@]}"
            status=$?
            set -e
            exit "$status"
          '';
          meta = {
            license = lib.licenses.unlicense;
            mainProgram = name;
          };
        };
      checkRunner = mkRunner {
        name = "grit-check";
        fix = false;
        extraArgs = checkArgs;
      };
      applyRunner = mkRunner {
        name = "grit-apply";
        fix = true;
        extraArgs = applyArgs;
      };
      check = toolPkgs.runCommandLocal "grit-validation" { } ''
        cd ${src}
        ${lib.getExe checkRunner}
        touch "$out"
      '';
    in
    assert lib.assertMsg (lib.elem system supportedSystems)
      "unsupported system `${system}`; supported systems: ${lib.concatStringsSep ", " supportedSystems}";
    assert lib.assertMsg (
      patternType == "directory" || supportedPatternFile patternName
    ) "patterns must be a .grit/.md file or a directory";
    assert lib.assertMsg (
      canonicalConfig || discovered != [ ]
    ) "pattern directory contains no .grit or .md files";
    assert lib.assertMsg (
      paths != [ ] && lib.all isRelative paths
    ) "paths must contain non-empty relative paths or globs without '..' segments";
    assert lib.assertMsg (lib.all isRelative exclude)
      "exclude must contain relative paths or globs without '..' segments";
    assert lib.assertMsg (isRelative treeRootFile)
      "treeRootFile must be a non-empty relative path without '..' segments";
    assert lib.assertMsg (lib.elem level [
      "info"
      "warn"
      "error"
    ]) "level must be info, warn, or error";
    assert lib.assertMsg (lib.all lib.isString (
      commonArgs ++ checkArgs ++ applyArgs
    )) "gritArgs values must be lists of strings";
    assert lib.assertMsg (
      rejected (commonArgs ++ checkArgs ++ applyArgs) [
        "--fix"
        "--grit-dir"
        "--json"
        "--jsonl"
        "--level"
        "--no-cache"
        "--refresh-cache"
      ] == [ ]
    ) "gritArgs cannot override runner-owned safety arguments";
    {
      checks.grit = check;
      apps = {
        grit-check = runnable checkRunner;
        grit-apply = runnable applyRunner;
      };
      packages = {
        grit-check = checkRunner;
        grit-apply = applyRunner;
      };
    };

  configureProfiles =
    {
      system,
      src,
      profiles,
      toolPkgs ? toolPkgsFor system,
    }:
    let
      profileNames = if lib.isAttrs profiles then builtins.attrNames profiles else [ ];
      validProfileName =
        name:
        builtins.stringLength name <= 64 && builtins.match "^[a-z]([a-z0-9-]*[a-z0-9])?$" name != null;
      namedRunner =
        name: package:
        toolPkgs.writeShellApplication {
          inherit name;
          text = ''
            exec ${lib.getExe package} "$@"
          '';
          meta = {
            license = lib.licenses.unlicense;
            mainProgram = name;
          };
        };
      configuredProfiles = lib.mapAttrs (
        name: profile:
        if !lib.isAttrs profile then
          throw "profile `${name}` must be an attribute set"
        else
          let
            forbidden = lib.filter (option: builtins.hasAttr option profile) [
              "src"
              "system"
              "toolPkgs"
            ];
            gate = profile.gate or true;
            configured = configure (
              builtins.removeAttrs profile [ "gate" ]
              // {
                inherit
                  src
                  system
                  toolPkgs
                  ;
              }
            );
            checkName = "grit-${name}-check";
            applyName = "grit-${name}-apply";
          in
          assert lib.assertMsg (
            forbidden == [ ]
          ) "profile `${name}` cannot override shared options: ${lib.concatStringsSep ", " forbidden}";
          assert lib.assertMsg (lib.isBool gate) "profile `${name}` gate must be a Boolean";
          {
            inherit gate;
            check = configured.checks.grit;
            checkPackage = namedRunner checkName configured.packages.grit-check;
            applyPackage = namedRunner applyName configured.packages.grit-apply;
          }
      ) profiles;
      merge =
        select:
        lib.foldl' (result: name: result // select name configuredProfiles.${name}) { } profileNames;
    in
    assert lib.assertMsg (
      lib.isAttrs profiles && profileNames != [ ]
    ) "profiles must be a non-empty attribute set";
    assert lib.assertMsg (lib.all validProfileName profileNames)
      "profile names must match ^[a-z]([a-z0-9-]*[a-z0-9])?$ and contain at most 64 characters";
    {
      checks = merge (
        name: profile:
        lib.optionalAttrs profile.gate {
          "grit-${name}" = profile.check;
        }
      );
      apps = merge (
        name: profile: {
          "grit-${name}-check" = runnable profile.checkPackage;
          "grit-${name}-apply" = runnable profile.applyPackage;
        }
      );
      packages = merge (
        name: profile: {
          "grit-${name}-check" = profile.checkPackage;
          "grit-${name}-apply" = profile.applyPackage;
        }
      );
    };
}

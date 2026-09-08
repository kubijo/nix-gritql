set default-list
set positional-arguments
set shell := ["bash", "-euo", "pipefail", "-c"]

# Run package and repository QA checks.
check:
    nix flake check --quiet
    nix flake check 'path:.?dir=qa' --quiet

# Format repository files.
format:
    nix run 'path:.?dir=qa#format'

# Lint repository files.
lint:
    nix run 'path:.?dir=qa#lint'

# Build Grit.
build:
    nix build .#grit

# Print Grit's version.
smoke:
    nix run .#grit -- --version

# Validate, commit, and tag a release; do not push.
release level:
    #!/usr/bin/env bash
    set -euo pipefail

    case "{{ level }}" in
        major | minor | patch) ;;
        *)
            echo "level must be major, minor or patch" >&2
            exit 1
            ;;
    esac

    if [[ -n $(git status --porcelain) ]]; then
        echo "working tree is dirty" >&2
        exit 1
    fi

    latest=$(git tag --list 'v*' --sort=-v:refname | head -1)
    IFS=. read -r major minor patch <<< "${latest#v}"
    major=${major:-0} minor=${minor:-0} patch=${patch:-0}

    case "{{ level }}" in
        major) major=$((major + 1)) minor=0 patch=0 ;;
        minor) minor=$((minor + 1)) patch=0 ;;
        patch) patch=$((patch + 1)) ;;
    esac
    version="$major.$minor.$patch"

    notes=$(awk '/^## \[Unreleased\]/ { f = 1; next } /^## / { f = 0 } f' CHANGELOG.md)
    if [[ -z ${notes//[[:space:]]/} ]]; then
        echo "nothing recorded under '## [Unreleased]'" >&2
        exit 1
    fi

    just check

    read -rp "tag v$version? [y/N] " reply
    [[ $reply == [yY]* ]] || exit 1

    sed -i "s/^## \[Unreleased\]$/## [Unreleased]\n\n## [$version] - $(date +%F)/" CHANGELOG.md
    git add CHANGELOG.md
    git commit -m "Release v$version"
    git tag -a "v$version" -m "v$version" -m "$notes"
    echo "tagged v$version — push it with: git push --follow-tags"

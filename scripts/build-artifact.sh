#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ne 1 ]]; then
    echo "usage: $0 <nix-system>" >&2
    exit 2
fi

system=$1
case "$system" in
x86_64-linux | aarch64-linux | aarch64-darwin) ;;
*)
    echo "unsupported system: $system" >&2
    exit 2
    ;;
esac

# Release production always selects the pinned source package.
nix build -L --no-update-lock-file --no-link .#grit-source
nix build -L --no-update-lock-file --no-link .#grit-artifact .#grit-local-prebuilt
nix build -L --no-update-lock-file --no-link ".#checks.$system.equivalence"
nix build -L --no-update-lock-file --no-link --offline ".#checks.$system.equivalence"

source_path=$(nix build --no-update-lock-file --no-link --print-out-paths .#grit-source)
prebuilt_path=$(nix build --no-update-lock-file --no-link --print-out-paths .#grit-local-prebuilt)
archive_path=$(nix build --no-update-lock-file --no-link --print-out-paths .#grit-artifact)
source_rev=$(jq -r '.nodes["gritql-src"].locked.rev' flake.lock)
nixpkgs_rev=$(jq -r '.nodes["nixpkgs-pinned"].locked.rev' flake.lock)

tar -xOzf "$archive_path" ./metadata.json \
    | jq -e --arg system "$system" \
        --arg source "$source_rev" --arg nixpkgs "$nixpkgs_rev" \
        '.format == 1 and .system == $system and
         .sourceRev == $source and .nixpkgsRev == $nixpkgs'

# The fixed-up executable must not retain the source package in its closure.
if nix-store -q --requisites "$prebuilt_path" | grep -Fx "$source_path"; then
    echo "prebuilt package still references the source package" >&2
    exit 1
fi
nix-store -q --requisites "$prebuilt_path" \
    | while IFS= read -r path; do test -e "$path"; done

"$source_path/bin/grit" --version
"$prebuilt_path/bin/grit" --version
if [[ $system == *-linux ]]; then
    readelf -l "$prebuilt_path/bin/grit" | grep 'interpreter'
    readelf -d "$prebuilt_path/bin/grit" | grep -E 'NEEDED|RUNPATH'
else
    otool -L "$prebuilt_path/bin/grit"
fi

mkdir -p dist
name="grit-0.0.3-$system.tar.gz"
cp "$archive_path" "dist/$name"
(cd dist && shasum -a 256 "$name" >"$name.sha256")

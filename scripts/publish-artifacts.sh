#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ne 1 ]]; then
    echo "usage: $0 <successful-build-run-id>" >&2
    exit 2
fi

build_run_id=$1
tag=$(nix eval --raw --impure --expr '(import ./nix/artifacts.nix).tag')
run=$(gh run view "$build_run_id" --json conclusion,event,headSha,workflowName)
test "$(jq -r '.conclusion' <<<"$run")" = success
test "$(jq -r '.event' <<<"$run")" = workflow_dispatch
test "$(jq -r '.workflowName' <<<"$run")" = 'Build Grit CLI artifacts'
head_sha=$(jq -r '.headSha' <<<"$run")
source_rev=$(jq -r '.nodes["gritql-src"].locked.rev' flake.lock)
nixpkgs_rev=$(jq -r '.nodes["nixpkgs-pinned"].locked.rev' flake.lock)

gh run download "$build_run_id" --dir downloads
mkdir release
for system in x86_64-linux aarch64-linux aarch64-darwin; do
    name="grit-0.0.3-$system.tar.gz"
    directory="downloads/grit-$system"
    test -f "$directory/$name"
    test -f "$directory/$name.sha256"
    (cd "$directory" && shasum -a 256 -c "$name.sha256")
    tar -xOzf "$directory/$name" ./metadata.json \
        | jq -e --arg system "$system" \
            --arg source "$source_rev" --arg nixpkgs "$nixpkgs_rev" \
            '.format == 1 and .gritVersion == "0.0.3" and
             .system == $system and .sourceRev == $source and
             .nixpkgsRev == $nixpkgs and
             (.rustc | length > 0) and (.cargo | length > 0)'
    cp "$directory/$name" "release/$name"
done

(cd release && shasum -a 256 ./*.tar.gz >SHA256SUMS)
gh release create "$tag" release/* \
    --target "$head_sha" \
    --title "$tag" \
    --notes "GritQL v0.0.3 CLI from $source_rev. See SHA256SUMS and archive metadata."

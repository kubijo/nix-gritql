#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ne 1 || ! $1 =~ ^[1-9][0-9]*$ ]]; then
    echo "usage: $0 <release-pull-request-number>" >&2
    exit 2
fi

pr_number=$1
repo=${GITHUB_REPOSITORY:?GITHUB_REPOSITORY is required}
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

publish_release() {
    local release_tag=$1 notes_file=$2 kind=$3 path name
    if ! gh release view "$release_tag" --repo "$repo" >/dev/null 2>&1; then
        local options=(--verify-tag --title "$release_tag" --notes-file "$notes_file" --draft)
        if [[ $kind == artifact ]]; then
            options+=(--prerelease --latest=false)
        fi
        gh release create "$release_tag" "$work/release"/* --repo "$repo" "${options[@]}"
    fi
    mkdir -p "$work/verified/$release_tag"
    for path in "$work/release"/*; do
        name=${path##*/}
        if ! gh release download "$release_tag" --repo "$repo" --pattern "$name" \
            --dir "$work/verified/$release_tag" >/dev/null 2>&1; then
            gh release upload "$release_tag" "$path" --repo "$repo"
            gh release download "$release_tag" --repo "$repo" --pattern "$name" \
                --dir "$work/verified/$release_tag"
        fi
        cmp "$path" "$work/verified/$release_tag/$name"
    done
    gh release edit "$release_tag" --repo "$repo" --draft=false
    for path in "$work/release"/*.tar.gz; do
        name=${path##*/}
        curl --fail --location --retry 5 --retry-all-errors --retry-delay 2 \
            --silent --show-error \
            "https://github.com/$repo/releases/download/$release_tag/$name" \
            --output "$work/$name"
        cmp "$path" "$work/$name"
    done
}

latest_ci_run() {
    gh run list --repo "$repo" --workflow ci.yml --commit "$1" \
        --event pull_request --limit 50 \
        --json attempt,databaseId,conclusion,event,headBranch,headSha,status \
        | jq -c --arg branch "$head_branch" \
            '[.[] | select(.headBranch == $branch and .event == "pull_request")] |
             sort_by(.databaseId) | last // empty'
}

pr=$(gh pr view "$pr_number" --repo "$repo" \
    --json state,isDraft,isCrossRepository,baseRefName,baseRefOid,headRefName,headRefOid,mergeCommit)
state=$(jq -r '.state' <<<"$pr")
head_sha=$(jq -r '.headRefOid' <<<"$pr")
head_branch=$(jq -r '.headRefName' <<<"$pr")
base_sha=$(jq -r '.baseRefOid' <<<"$pr")

if [[ $(jq -r '.isDraft' <<<"$pr") != false ||
$(jq -r '.isCrossRepository' <<<"$pr") != false ||
$(jq -r '.baseRefName' <<<"$pr") != main ||
$state != OPEN && $state != MERGED ]]; then
    echo "release requires a non-draft pull request from this repository into main" >&2
    exit 1
fi

git fetch --tags origin
git fetch origin "$head_sha"
git show "$head_sha:VERSION" >"$work/VERSION"
git show "$head_sha:CHANGELOG.md" >"$work/CHANGELOG.md"
version=$(cat "$work/VERSION")
[[ $version =~ ^(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)$ ]]
tag="v$version"
candidate_prefix="grit-cli-$tag-candidate-"

# A hash-only bot commit retains the original candidate's run and artifacts.
candidate_head=$head_sha
run=
manifest_tag=$(git show "$head_sha:nix/artifacts.nix" | sed -n 's/^  tag = "\(.*\)";$/\1/p')
if [[ $manifest_tag == "$candidate_prefix"* ]]; then
    suffix=${manifest_tag#"$candidate_prefix"}
    if [[ $suffix =~ ^([0-9]+)-([0-9]+)$ ]] \
        && git rev-parse -q --verify "refs/tags/$manifest_tag" >/dev/null; then
        tagged_run_id=${BASH_REMATCH[1]}
        tagged_attempt=${BASH_REMATCH[2]}
        tagged_head=$(git rev-parse "$manifest_tag^{commit}")
        changed_files=$(git diff --name-only "$tagged_head" "$head_sha")
        if git merge-base --is-ancestor "$tagged_head" "$head_sha" \
            && [[ -z $changed_files || $changed_files == nix/artifacts.nix ]]; then
            candidate_head=$tagged_head
            run=$(gh run view "$tagged_run_id" --attempt "$tagged_attempt" --repo "$repo" \
                --json attempt,databaseId,conclusion,event,headBranch,headSha,status)
            jq -e --arg head "$candidate_head" --arg branch "$head_branch" \
                --argjson id "$tagged_run_id" --argjson attempt "$tagged_attempt" \
                '.databaseId == $id and .attempt == $attempt and
                 .headSha == $head and .headBranch == $branch and
                 .event == "pull_request" and .conclusion == "success"' \
                <<<"$run" >/dev/null
        fi
    fi
fi
if [[ -z $run ]]; then
    run=$(latest_ci_run "$candidate_head")
fi
if [[ -z $run || $(jq -r '.conclusion' <<<"$run") != success ]]; then
    echo "latest CI run for candidate head $candidate_head is not green" >&2
    exit 1
fi
run_id=$(jq -r '.databaseId' <<<"$run")
run_attempt=$(jq -r '.attempt' <<<"$run")
[[ $run_id =~ ^[1-9][0-9]*$ && $run_attempt =~ ^[1-9][0-9]*$ ]]
artifact_tag="$candidate_prefix$run_id-$run_attempt"
gh run download "$run_id" --repo "$repo" --dir "$work/downloads"

# The tested base comes from CI, not from a parent of the rebased commit.
tested_base=$(jq -r '.baseSha' "$work/downloads/grit-x86_64-linux-$run_attempt/candidate.json")
if [[ ! $tested_base =~ ^[0-9a-f]{40}$ ]]; then
    echo "candidate CI has no valid base commit" >&2
    exit 1
fi
if [[ $state == OPEN && $tested_base != "$base_sha" ]]; then
    echo "pull request base changed since candidate CI" >&2
    exit 1
fi
base_sha=$tested_base
git fetch origin "$base_sha"
base_version=$(git show "$base_sha:VERSION" 2>/dev/null || true)
if [[ -z $base_version ]]; then
    base_version=$(git tag --list 'v*' --sort=-v:refname | head -1)
    base_version=${base_version#v}
fi
version_args=(--require-bump)
if [[ $state == MERGED ]]; then
    version_args+=(--allow-existing-tag)
fi
python3 scripts/pipeline.py check-version \
    "$work/VERSION" "$base_version" "$work/CHANGELOG.md" "${version_args[@]}"
if [[ $state == OPEN ]] && git rev-parse -q --verify "refs/tags/$tag" >/dev/null; then
    echo "release tag $tag already exists" >&2
    exit 1
fi

git show "$head_sha:flake.lock" >"$work/flake.lock"
source_rev=$(jq -r '.nodes["gritql-src"].locked.rev' "$work/flake.lock")
nixpkgs_rev=$(jq -r '.nodes["nixpkgs-pinned"].locked.rev' "$work/flake.lock")
[[ $source_rev =~ ^[0-9a-f]{40}$ && $nixpkgs_rev =~ ^[0-9a-f]{40}$ ]]

mkdir "$work/release"
upstream_version=
candidate_tree=
for system in x86_64-linux aarch64-linux aarch64-darwin; do
    shopt -s nullglob
    directory="$work/downloads/grit-$system-$run_attempt"
    archives=("$directory"/grit-*"-$system.tar.gz")
    shopt -u nullglob
    if [[ ${#archives[@]} -ne 1 ]]; then
        echo "expected exactly one CLI archive for $system in CI run $run_id" >&2
        exit 1
    fi
    archive=${archives[0]}
    name=${archive##*/}
    jq -e --arg head "$candidate_head" --arg base "$base_sha" \
        '.headSha == $head and .baseSha == $base' \
        "$directory/candidate.json" >/dev/null || {
        echo "candidate CI was run against a different pull request base or head" >&2
        exit 1
    }
    tree=$(jq -r '.treeSha' "$directory/candidate.json")
    [[ $tree =~ ^[0-9a-f]{40}$ ]]
    if [[ -n $candidate_tree && $candidate_tree != "$tree" ]]; then
        echo "candidate CI jobs were built from different trees" >&2
        exit 1
    fi
    candidate_tree=$tree
    (cd "${archive%/*}" && sha256sum -c "$name.sha256")
    metadata=$(tar -xOzf "$archive" ./metadata.json)
    jq -e --arg system "$system" --arg source "$source_rev" \
        --arg nixpkgs "$nixpkgs_rev" \
        '.format == 1 and .system == $system and
         .sourceRev == $source and .nixpkgsRev == $nixpkgs and
         (.gritVersion | test("^[0-9]+\\.[0-9]+\\.[0-9]+$")) and
         (.rustc | length > 0) and (.cargo | length > 0)' <<<"$metadata" >/dev/null
    archive_version=$(jq -r '.gritVersion' <<<"$metadata")
    if [[ -n $upstream_version && $upstream_version != "$archive_version" ]]; then
        echo "candidate archives disagree on upstream Grit version" >&2
        exit 1
    fi
    upstream_version=$archive_version
    [[ $name == "grit-$upstream_version-$system.tar.gz" ]]
    cp "$archive" "$work/release/$name"
    hash=$(nix hash file --sri "$archive")
    case "$system" in
    x86_64-linux) x86_hash=$hash ;;
    aarch64-linux) arm_hash=$hash ;;
    aarch64-darwin) darwin_hash=$hash ;;
    esac
done
(cd "$work/release" && sha256sum ./*.tar.gz >SHA256SUMS)

if [[ $state == OPEN && $candidate_head == "$head_sha" ]]; then
    git fetch origin "refs/pull/$pr_number/merge"
    if [[ $(git rev-parse 'FETCH_HEAD^{tree}') != "$candidate_tree" ]]; then
        echo "pull request merge tree changed since candidate CI" >&2
        exit 1
    fi
fi

awk -v version="$version" \
    'index($0, "## [" version "]") == 1 { found = 1; next } /^## / { found = 0 } found' \
    "$work/CHANGELOG.md" >"$work/notes"
if [[ ! -s "$work/notes" ]]; then
    echo "release changelog section is empty" >&2
    exit 1
fi

# Publish the immutable bytes before making the PR fetch them by fixed hash.
if ! git rev-parse -q --verify "refs/tags/$artifact_tag" >/dev/null; then
    git -c user.name='github-actions[bot]' \
        -c user.email='41898282+github-actions[bot]@users.noreply.github.com' \
        tag -a "$artifact_tag" "$candidate_head" -m "$artifact_tag"
    git push origin "refs/tags/$artifact_tag"
fi
if [[ $(git rev-parse "$artifact_tag^{commit}") != "$candidate_head" ]] \
    || ! git merge-base --is-ancestor "$candidate_head" "$head_sha"; then
    echo "artifact tag $artifact_tag is not on this release branch" >&2
    exit 1
fi
printf 'Pinned Grit CLI archives from source revision %s.\n' "$source_rev" >"$work/artifact-notes"
publish_release "$artifact_tag" "$work/artifact-notes" artifact

printf '%s\n' \
    '{' \
    "  version = \"$upstream_version\";" \
    "  tag = \"$artifact_tag\";" \
    "  sourceRev = \"$source_rev\";" \
    '  hashes = {' \
    "    x86_64-linux = \"$x86_hash\";" \
    "    aarch64-linux = \"$arm_hash\";" \
    "    aarch64-darwin = \"$darwin_hash\";" \
    '  };' \
    '}' >"$work/artifacts.nix"

needs_verification=false
if ! git show "$head_sha:nix/artifacts.nix" | cmp - "$work/artifacts.nix"; then
    if [[ $state != OPEN ]]; then
        echo "merged release is missing the tested artifact hashes" >&2
        exit 1
    fi
    git switch --detach "$head_sha"
    cp "$work/artifacts.nix" nix/artifacts.nix
    git add nix/artifacts.nix
    git -c user.name='github-actions[bot]' \
        -c user.email='41898282+github-actions[bot]@users.noreply.github.com' \
        commit -m "Pin Grit CLI artifacts for $tag"
    head_sha=$(git rev-parse HEAD)
    git push origin "HEAD:refs/heads/$head_branch"
    needs_verification=true
elif [[ $candidate_head != "$head_sha" ]]; then
    needs_verification=true
fi

if [[ $needs_verification == true ]]; then
    if [[ $state == OPEN ]]; then
        # GitHub updates the PR merge ref asynchronously after the branch push.
        ready=false
        for _ in {1..30}; do
            pr=$(gh pr view "$pr_number" --repo "$repo" --json state,baseRefOid,headRefOid)
            if [[ $(jq -r '.state' <<<"$pr") == OPEN &&
            $(jq -r '.baseRefOid' <<<"$pr") == "$base_sha" &&
            $(jq -r '.headRefOid' <<<"$pr") == "$head_sha" ]] \
                && git fetch origin "refs/pull/$pr_number/merge" \
                && [[ $(git rev-parse 'FETCH_HEAD^1') == "$base_sha" &&
                $(git rev-parse 'FETCH_HEAD^2') == "$head_sha" ]]; then
                ready=true
                break
            fi
            sleep 5
        done
        if [[ $ready != true ]]; then
            echo "pull request merge ref did not reach the hash commit" >&2
            exit 1
        fi

        previous_run=$(gh run list --repo "$repo" --workflow ci.yml --commit "$head_sha" \
            --event workflow_dispatch --limit 20 --json databaseId \
            | jq '[.[].databaseId] | max // 0')
        gh workflow run ci.yml --repo "$repo" --ref "$head_branch" \
            -f release_pr="$pr_number" -f candidate_head="$head_sha" -f candidate_base="$base_sha"
        rerun=
        for _ in {1..30}; do
            rerun=$(gh run list --repo "$repo" --workflow ci.yml --commit "$head_sha" \
                --event workflow_dispatch --limit 20 \
                --json attempt,databaseId,headBranch,headSha \
                | jq -c --arg branch "$head_branch" --argjson previous "$previous_run" \
                    '[.[] | select(.headBranch == $branch and .databaseId > $previous)] |
                     sort_by(.databaseId) | last // empty')
            [[ -n $rerun ]] && break
            sleep 5
        done
        if [[ -z $rerun ]]; then
            echo "dispatched native CI did not appear" >&2
            exit 1
        fi
        run_id=$(jq -r '.databaseId' <<<"$rerun")
        gh run watch "$run_id" --repo "$repo" --compact --exit-status --interval 20
    else
        rerun=$(gh run list --repo "$repo" --workflow ci.yml --commit "$head_sha" \
            --event workflow_dispatch --status success --limit 20 \
            --json attempt,databaseId,headBranch,headSha \
            | jq -c --arg branch "$head_branch" \
                '[.[] | select(.headBranch == $branch)] |
                 sort_by(.databaseId) | last // empty')
        if [[ -z $rerun ]]; then
            echo "merged release has no green CI run for its hash commit" >&2
            exit 1
        fi
        run_id=$(jq -r '.databaseId' <<<"$rerun")
    fi
    run=$(gh run view "$run_id" --repo "$repo" \
        --json attempt,conclusion,event,headBranch,headSha)
    jq -e --arg head "$head_sha" --arg branch "$head_branch" \
        '.conclusion == "success" and .event == "workflow_dispatch" and
         .headBranch == $branch and .headSha == $head' <<<"$run" >/dev/null
    gh run download "$run_id" --repo "$repo" --dir "$work/rerun"
    rerun_attempt=$(jq -r '.attempt' <<<"$run")
    [[ $rerun_attempt =~ ^[1-9][0-9]*$ ]]
    candidate_tree=
    for system in x86_64-linux aarch64-linux aarch64-darwin; do
        directory="$work/rerun/grit-$system-$rerun_attempt"
        name="grit-$upstream_version-$system.tar.gz"
        jq -e --arg head "$head_sha" --arg base "$base_sha" \
            '.headSha == $head and .baseSha == $base' \
            "$directory/candidate.json" >/dev/null
        tree=$(jq -r '.treeSha' "$directory/candidate.json")
        [[ $tree =~ ^[0-9a-f]{40}$ ]]
        if [[ -n $candidate_tree && $candidate_tree != "$tree" ]]; then
            echo "native CI jobs were built from different trees" >&2
            exit 1
        fi
        candidate_tree=$tree
        (cd "$directory" && sha256sum -c "$name.sha256")
        cmp "$directory/$name" "$work/release/$name"
    done
fi

if [[ $state == OPEN ]]; then
    pr=$(gh pr view "$pr_number" --repo "$repo" --json state,baseRefOid,headRefOid)
    if [[ $(jq -r '.state' <<<"$pr") != OPEN ||
    $(jq -r '.baseRefOid' <<<"$pr") != "$base_sha" ||
    $(jq -r '.headRefOid' <<<"$pr") != "$head_sha" ]]; then
        echo "pull request changed since native CI" >&2
        exit 1
    fi
    git fetch origin "refs/pull/$pr_number/merge"
    if [[ $(git rev-parse 'FETCH_HEAD^{tree}') != "$candidate_tree" ]]; then
        echo "pull request merge tree changed since native CI" >&2
        exit 1
    fi
    gh pr merge "$pr_number" --repo "$repo" --rebase --match-head-commit "$head_sha"
fi
pr=$(gh pr view "$pr_number" --repo "$repo" --json state,mergeCommit)
if [[ $(jq -r '.state' <<<"$pr") != MERGED ]]; then
    echo "pull request was not merged; release can be rerun after it merges" >&2
    exit 1
fi
release_sha=$(jq -r '.mergeCommit.oid' <<<"$pr")
git fetch origin "$release_sha"
if ! git merge-base --is-ancestor "$base_sha" "$release_sha"; then
    echo "rebased commit does not descend from the tested base" >&2
    exit 1
fi
if [[ $(git show "$release_sha:VERSION") != "$version" ]]; then
    echo "rebased result does not contain VERSION $version" >&2
    exit 1
fi
if [[ $(git rev-parse "$release_sha^{tree}") != "$candidate_tree" ]]; then
    echo "rebased tree differs from the tested candidate" >&2
    exit 1
fi
if ! git show "$release_sha:nix/artifacts.nix" | cmp - "$work/artifacts.nix"; then
    echo "rebased commit does not contain the tested artifact hashes" >&2
    exit 1
fi

if ! git rev-parse -q --verify "refs/tags/$tag" >/dev/null; then
    git -c user.name='github-actions[bot]' \
        -c user.email='41898282+github-actions[bot]@users.noreply.github.com' \
        tag -a "$tag" "$release_sha" -m "$tag"
    git push origin "refs/tags/$tag"
fi
if [[ $(git rev-parse "$tag^{commit}") != "$release_sha" ]]; then
    echo "release tag $tag does not target the rebased commit" >&2
    exit 1
fi
publish_release "$tag" "$work/notes" version
echo "released $tag from CI run $run_id with the artifact hashes in its tagged commit"

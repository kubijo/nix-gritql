#!/usr/bin/env bash
set -euo pipefail

source_grit=$1
prebuilt_grit=$2

run_success() {
    local output=$1
    local status
    shift

    if "$@" >"$output" 2>&1; then
        return
    else
        status=$?
        printf 'failed (%s): %s\n' "$status" "$*" >&2
        cat "$output" >&2
        return "$status"
    fi
}

run_suite() {
    local grit=$1
    local result=$2
    local work="$TMPDIR/work"

    rm -rf "$work"
    mkdir -p "$work/.grit/patterns" "$work/home" "$result"
    export HOME="$work/home"
    export XDG_CACHE_HOME="$work/cache"
    export GRIT_DOWNLOADS_DISABLED=true

    cat >"$work/.grit/grit.yaml" <<'EOF'
version: 0.0.1
patterns:
  - name: no_console
    level: error
    body: |
      `console.log($msg)`
EOF
    cat >"$work/.grit/patterns/rename_console.md" <<'EOF'
---
title: Rename console calls
---

```grit
language js
`console.log($msg)` => `console.info($msg)`
```

## Rename a call

```javascript
console.log("hello");
```

```javascript
console.info("hello");
```
EOF
    printf 'console.log("hello");\n' >"$work/example.js"

    cd "$work"
    run_success "$result/version" "$grit" --version
    run_success "$result/patterns" "$grit" patterns test --filter rename_console
    if "$grit" check --no-cache example.js >"$result/check" 2>&1; then
        printf '0\n' >"$result/check-status"
    else
        printf '%s\n' "$?" >"$result/check-status"
    fi
    if "$grit" format --write >"$result/format" 2>&1; then
        printf '0\n' >"$result/format-status"
    else
        printf '%s\n' "$?" >"$result/format-status"
    fi
    cp .grit/grit.yaml "$result/formatted.yaml"
    cp .grit/patterns/rename_console.md "$result/formatted.md"
    # shellcheck disable=SC2016
    run_success "$result/apply" "$grit" apply --output compact \
        '`console.log($msg)` => `console.info($msg)`' example.js
    cp example.js "$result/applied.js"
}

run_suite "$source_grit" "$TMPDIR/source-results"
run_suite "$prebuilt_grit" "$TMPDIR/prebuilt-results"
diff -ru "$TMPDIR/source-results" "$TMPDIR/prebuilt-results"
test "$(cat "$TMPDIR/source-results/check-status")" = 1
test "$(cat "$TMPDIR/source-results/applied.js")" = 'console.info("hello");'

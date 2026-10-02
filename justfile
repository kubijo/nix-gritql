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

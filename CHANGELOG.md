# Changelog

Notable changes follow [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

## [Unreleased]

### Added

- `just outdated` reports outdated flake inputs in the package and QA flakes, and GitHub Actions refs.
- Prepared native CLI release artifacts, fixed-output packaging, and source/prebuilt equivalence checks.y

### Changed

- Refreshed pinned nixpkgs, used by the source build.
- Moved repository QA to nix-tools v0.11.0 and bumped workflow actions.
- Use published CLI archives by default on supported platforms.
- Choose repository release versions in `VERSION` and publish retryable native artifacts from green pull requests.

## [0.5.0] - 2026-09-08

### Changed

- Rebuilt the flake as a small, reproducible package wrapper for unmodified GritQL.

# Changelog

Notable changes follow [Keep a Changelog](https://keepachangelog.com/en/1.1.0/). Before 1.0, minor releases may break
API.

## [Unreleased]

## [0.2.0] - 2026-09-07

### Added

- Named, isolated Grit profiles through `lib.configureProfiles`, with shared source and tool-set configuration.
- Per-profile patterns, paths, exclusions, arguments, and Grit package overrides.
- Read-only and explicit apply apps and packages for every profile. Gated profiles also export checks.
- Full compatibility with the existing `lib.configure` API and output names.

## [0.1.0] - 2026-09-06

### Added

- Reproducible, unmodified GritQL CLI builds.
- Language-agnostic checks and codemods through `lib.configure`.
- Consumer fixtures and a tested language capability matrix.
- Native CI for every supported system.

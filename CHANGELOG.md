# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]


## [2.1.2] - 2026-06-09

### Changed

- actions/checkout to v6.0.3 and resolve package paths (#38)

## [2.1.1] - 2026-03-21

### Changed

- checkout branch then reset to triggering commit sha
- clarify scope detection priority, dependency-order limits, and clean-commit parser behavior
- update README and examples for v2 with commit convention gate
- extract bot actor detection into dedicated script with ci tests
- add bot-safe validation job and document bot detection
- add Bun-native runtime, audit, and publish support without workflow Node setup (#34)
- Bump wgtechlabs/release-build-flow-action from 1.6.0 to 1.7.0 (#32)

## [2.1.0] - 2026-03-07

### Added

- add commit convention gate and bot detection inputs

### Changed

- add dependabot, funding, and release workflow
- ignore contributerc config file


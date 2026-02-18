# Litebar Repository Agent Guide

This file is for agents working on the Litebar codebase in this repository.

## Project Purpose

Litebar is a macOS menubar app that provides passive observability for SQLite-backed systems, with an agent-operated configuration model.

## Key Principles

- Prioritize operational reliability and signal quality.
- Keep refresh behavior lightweight and deterministic.
- Treat `~/.litebar/config.yaml` as agent-managed runtime state.
- Avoid introducing breaking changes to existing config schema without migration.

## Repository Layout

- `Sources/App/`: app lifecycle and shared app state
- `Sources/Models/`: config/state/data models
- `Sources/Services/`: SQLite inspection, health, watches, backups
- `Sources/Views/`: menu and settings UI
- `Sources/Resources/litebar/`: runtime template files copied to `~/.litebar/` on first run
- `Tests/LitebarTests/`: unit tests
- `Formula/litebar.rb`: Homebrew formula

## Runtime Template Contract

Litebar bootstraps runtime files from repository-tracked templates:

- `Sources/Resources/litebar/config.yaml`
- `Sources/Resources/litebar/AGENTS.md`

App bootstrap copies these to:

- `~/.litebar/config.yaml`
- `~/.litebar/AGENTS.md`

Important: bootstrap only writes missing files. Existing user files are preserved.

## Build and Test

```bash
swift build
swift test
```

## Change Guidelines

- Keep changes small and scoped.
- Maintain macOS 15+ compatibility baseline.
- Validate new config behavior with tests when feasible.
- If updating runtime semantics, update all three:
  1. `Sources/Resources/litebar/AGENTS.md`
  2. `README.md`
  3. relevant code paths in `Sources/Models/AppConfig.swift`

## Release Hygiene

Before publishing:

- Ensure local-only files are not tracked (`.claude/settings.local.json`, etc.).
- Verify README install instructions and GitHub URLs.
- Verify Homebrew formula metadata (`Formula/litebar.rb`).
- Run `swift build` and `swift test`.

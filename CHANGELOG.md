# Changelog

All notable changes to this project are documented in this file.

## Unreleased

### Added
- Single-binary companion behavior in `auto-ssl-tui` by embedding the Bash runtime and extracting it at runtime.
- Companion CLI commands in `auto-ssl-tui`:
  - `doctor` / `doctor --json`
  - `install-deps` / `install-deps --yes`
  - `dump-bash --output --force --print-path --checksum`
  - `exec -- <auto-ssl args...>`
- TUI dependency installer screen and menu entry.
- Linux validation script at `scripts/validate-linux.sh`.
- Missing docs page: `docs/concepts/certificate-lifecycle.md`.
- New safety-first reset command: `auto-ssl ca reset` for explicit "start over" workflows.

### Changed
- TUI now routes core workflows through the embedded runtime rather than requiring separately installed script directories.
- TUI styling updated toward a higher-contrast retro ops-console appearance.
- `auto-ssl` top-level help now includes `remote list`.
- Install/build packaging now defaults to single-binary deployment (`auto-ssl-tui`) with an `auto-ssl` compatibility wrapper.

### Fixed
- Bash config helpers now correctly read/write nested YAML keys when callers use dotted paths (e.g. `ca.url`).
- Remote enrollment packaging/install now deploys the proper runtime layout on remote hosts.
- Server non-interactive enrollment now enforces password-file requirements.
- Removed dead TUI navigation path to non-implemented settings screen.
- Replaced unsafe shell-interpolated secret-file writes in Go with secure temp-file handling.
- TUI now gives explicit root-privilege guidance for privileged workflows instead of failing with ambiguous errors.

### Notes
- macOS support is aimed at development/operator workflows.
- Linux remains the primary deployment target for full CA/server operations.

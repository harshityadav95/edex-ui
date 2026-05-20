# Changelog

All notable changes to this project will be documented in this file.

## [2.2.9] - 2026-05-20

### Added
- Created `.npmrc` and `src/.npmrc` with `node-linker=hoist` to support `pnpm`'s flat `node_modules` structure for compatibility with Electron.
- Added `pnpm` installation support in Linux installer script (`scripts/install-edex-service-linux.sh`).
- Added `pnpm` package to macOS installer script (`scripts/install-edex-service-darwin.sh`) dependencies via Homebrew.

### Changed
- Migrated the codebase from `npm` to `pnpm` project-wide.
- Deleted `package-lock.json` files and generated `pnpm-lock.yaml` files.
- Updated `package.json` scripts to run via `pnpm`.
- Updated GitHub Actions workflows (`.github/workflows/build-binaries.yaml`, `.github/workflows/pr-service-tests.yml`, `.github/workflows/release-macos-arm64.yml`) to use `pnpm/action-setup@v4`, caching under `cache: pnpm`, and calling `pnpm install --frozen-lockfile`.
- Updated documentation across `README.md` and `docs/*.md` files to refer to `pnpm` instructions.

### Fixed
- Fixed the macOS service runner (`scripts/run-edex-session-darwin.sh`) to check for the presence of the app directory *before* checking for the existence of commands, resolving the test-suite failure under missing-directory conditions.
- Updated `scripts/test-platform-support-spec.sh` to correctly check for `pnpm` usage and enforce lockfile consistency under regular expression checks.

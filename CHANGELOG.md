# Changelog

All notable changes to Aranet4 Logger are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and this
project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

When cutting a release, move the items under `[Unreleased]` into a new `## [x.y.z] - DATE`
section (the release workflow extracts that section into the GitHub release notes), then tag.

## [Unreleased]

## [1.0.5] - 2026-06-28
### Changed
- No functional changes from 1.0.4. Published to verify the self-signed auto-update pipeline
  end to end — an installed build updating itself to a newer release over the live appcast.

## [1.0.4] - 2026-06-28
### Changed
- Release builds are now signed with a stable self-signed certificate instead of an ad-hoc
  signature. This is required for Sparkle to install updates (it rejects an update whose code
  signature doesn't match the installed app), and it stops macOS from re-prompting for
  Bluetooth access after each update.

### Fixed
- The Sparkle updater no longer runs in Debug builds, so a development build can't silently
  replace itself with a published release.

## [1.0.3] - 2026-06-27
### Added
- Automatic updates via [Sparkle](https://sparkle-project.org): the app checks daily, installs
  in the background, and has a **Check for Updates…** menu item.

### Known issues
- Auto-updates do not install from this build because it is ad-hoc signed. Install 1.0.4 or
  later manually once to get onto the self-signed, self-updating track.

## [1.0.2] - 2026-06-27
### Changed
- Aranet sensors are now discovered automatically over Bluetooth and saved to the config; no
  devices are hardcoded. Device names are editable in Settings and are preserved across
  re-scans. (Note: the custom names set in the official Aranet app aren't exposed over
  Bluetooth, so names are set here instead.)

## [1.0.1] - 2026-06-27
### Changed
- The app's displayed version is templated from the build's marketing version.

## [1.0.0] - 2026-06-27
### Added
- Initial release. Native macOS menu bar app that continuously logs two Aranet4 sensors to a
  local SQLite database: live CO₂, temperature, humidity, pressure, battery, and signal
  strength per device; history backfill with connection retries and deduplication; Aranet Home
  CSV import; display-unit settings (°C/°F, hPa/inHg); a selectable menu-bar reading; and
  launch-at-login.

[Unreleased]: https://github.com/asmeurer/aranet4-data-saver/compare/v1.0.5...HEAD
[1.0.5]: https://github.com/asmeurer/aranet4-data-saver/compare/v1.0.4...v1.0.5
[1.0.4]: https://github.com/asmeurer/aranet4-data-saver/compare/v1.0.3...v1.0.4
[1.0.3]: https://github.com/asmeurer/aranet4-data-saver/compare/v1.0.2...v1.0.3
[1.0.2]: https://github.com/asmeurer/aranet4-data-saver/compare/v1.0.1...v1.0.2
[1.0.1]: https://github.com/asmeurer/aranet4-data-saver/compare/v1.0.0...v1.0.1
[1.0.0]: https://github.com/asmeurer/aranet4-data-saver/releases/tag/v1.0.0

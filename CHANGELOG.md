# Changelog

All notable changes to Aranet4 Logger are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and this
project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

When cutting a release, move the items under `[Unreleased]` into a new `## [x.y.z] - DATE`
section (the release workflow extracts that section into the GitHub release notes), then tag.

## [Unreleased]

## [1.5.0] - 2026-07-22
### Added
- Battery levels are now logged to a `battery_history` table in the database, sampled at
  each sync and stored only when the level changes. Over time this builds a per-device
  drain curve (e.g. to compare alkaline vs lithium AAs, or predict replacement time).
### Changed
- The low-battery warning now triggers at 10% instead of 20%. The Aranet4's AA
  batteries drain slowly enough that the old threshold kept the ⚠️ icon lit for months
  while the sensor was still working fine.
- Sparkle's update dialog now shows the release notes for the new version (rendered
  from the changelog) instead of an empty description.

## [1.4.0] - 2026-07-22
### Added
- Devices can now be removed in Settings (✕ next to the name, with confirmation). A
  removed device stops being logged and is put on an ignore list so the Bluetooth scan
  doesn't automatically re-add it — useful when a stranger's Aranet4 was picked up in
  passing. Its stored readings are kept in the database.

## [1.3.0] - 2026-07-07
### Added
- **Inline charts in the menu**: a "Last 24 Hours" section with a compact sparkline per
  metric (CO₂, temperature, humidity, pressure), both devices overlaid in their chart
  colors, with min–max summaries and CO₂ threshold lines. Rendered as menu item images
  (native menus can't host live chart views) that adapt to light/dark appearance.
- **Zoom in the Charts window**: drag horizontally across any chart to zoom every chart
  into the selected time window — data reloads at finer buckets, so zooming into a long
  range reveals detail down to the sensors' 5-minute grid. Double-click a chart or use
  the floating "Reset Zoom" button to zoom back out; switching the time-range preset
  also resets the zoom.

## [1.2.0] - 2026-07-05
### Added
- An **About** window (menu → About Aranet4 Logger) with the version and links to the
  project website and GitHub, and the version number shown at the bottom of the menu.
- A project website rendered from the README via GitHub Pages:
  <https://www.asmeurer.com/aranet4-data-saver/>
- An app icon: an Aranet4-style device face showing a CO₂ reading on a teal gradient,
  generated programmatically by `scripts/generate_icon.swift`.

## [1.1.0] - 2026-07-05
### Added
- Configurable high-CO₂ alerts: a ⚠️ warning in the menu bar and (optionally) a macOS
  notification when any sensor reads above a threshold (default 1400 ppm). Both are
  configured in Settings; notifications re-arm only after the reading falls 100 ppm below
  the threshold, so a value hovering at the limit doesn't fire repeatedly.
- A **Charts** window (menu → Charts…) that graphs the stored history: CO₂, temperature,
  humidity, and pressure, each device as its own line. Time-range presets from a day to the
  full history (long ranges are averaged into buckets, so they stay fast), per-device
  show/hide, hover for exact values, a min/avg/max summary per chart, CO₂ threshold lines
  (1000 ppm and the configured alert level), and lines that break across data gaps instead
  of bridging them. Respects the °C/°F and hPa/inHg display units and dark mode.
- The menu bar reading now shows its unit (ppm, °C/°F, %, hPa/inHg) in tiny type tucked
  under the number, so it's clear what the value represents without using any extra menu
  bar width.

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

[Unreleased]: https://github.com/asmeurer/aranet4-data-saver/compare/v1.5.0...HEAD
[1.5.0]: https://github.com/asmeurer/aranet4-data-saver/compare/v1.4.0...v1.5.0
[1.4.0]: https://github.com/asmeurer/aranet4-data-saver/compare/v1.3.0...v1.4.0
[1.3.0]: https://github.com/asmeurer/aranet4-data-saver/compare/v1.2.0...v1.3.0
[1.2.0]: https://github.com/asmeurer/aranet4-data-saver/compare/v1.1.0...v1.2.0
[1.1.0]: https://github.com/asmeurer/aranet4-data-saver/compare/v1.0.5...v1.1.0
[1.0.5]: https://github.com/asmeurer/aranet4-data-saver/compare/v1.0.4...v1.0.5
[1.0.4]: https://github.com/asmeurer/aranet4-data-saver/compare/v1.0.3...v1.0.4
[1.0.3]: https://github.com/asmeurer/aranet4-data-saver/compare/v1.0.2...v1.0.3
[1.0.2]: https://github.com/asmeurer/aranet4-data-saver/compare/v1.0.1...v1.0.2
[1.0.1]: https://github.com/asmeurer/aranet4-data-saver/compare/v1.0.0...v1.0.1
[1.0.0]: https://github.com/asmeurer/aranet4-data-saver/releases/tag/v1.0.0

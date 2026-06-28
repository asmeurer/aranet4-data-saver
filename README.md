# Aranet4 Logger

[![CI](https://github.com/asmeurer/aranet4-data-saver/actions/workflows/ci.yml/badge.svg)](https://github.com/asmeurer/aranet4-data-saver/actions/workflows/ci.yml)

A native macOS **menu bar app** that continuously and robustly logs readings from your
Aranet4 air-quality sensors into a local SQLite database.

It is built for the real-world case of one sensor nearby and another in a distant room with a
weak, flaky Bluetooth link. Rather than trying to catch every live reading, it periodically
connects and **downloads each device's on-device history log** (Aranet4 stores weeks of
readings internally), then deduplicates into SQLite. Whenever a device is reachable, any gap
since the last sync is backfilled automatically — so intermittent connectivity and app
downtime are both harmless.

## Features

- Menu bar app (no Dock icon) showing live CO₂, temperature, humidity, pressure, battery,
  signal strength, last-sync time, and stored-row count per device.
- **Selectable menu bar reading** — show one metric (CO₂ by default) from a chosen sensor
  directly in the menu bar title, or just the status icon. Configured in Settings (⌘,).
- **Passive advertisement scanning** for instant live values — works even when a device is
  refusing connections.
- **Robust history sync** with connection retries and backoff; incremental downloads bounded
  by the last stored timestamp.
- **SQLite storage** with `INSERT OR IGNORE` deduplication (`PRIMARY KEY (device, timestamp)`).
- **Launch at login** via `SMAppService`.
- Native CoreBluetooth — no Python, no third-party dependencies. The Aranet4 BLE/GATT
  protocol is reimplemented directly in `Aranet4Logger/BLE/AranetProtocol.swift`.

## Requirements

- macOS 14+ and Xcode 16+ (developed against macOS 26 / Xcode 26, Swift 6).
- Aranet4 devices with **"Smart Home integrations" enabled** in the Aranet Home app (required
  for both advertisements and history download).

## Tests & CI

```sh
xcodegen generate
xcodebuild test -project Aranet4Logger.xcodeproj -scheme Aranet4Logger -destination 'platform=macOS'
```

Unit tests for the hardware-independent logic (protocol decoding, history-packet parsing,
CSV import / °F→°C, time-grid snapping, SQLite dedup) live in `Aranet4LoggerTests/` and are
compiled directly into the test bundle — no Bluetooth or GUI needed. GitHub Actions
(`.github/workflows/ci.yml`) runs SwiftLint, builds, and tests on every push and PR.

## Releases

Pushing a `v*` tag triggers `.github/workflows/release.yml`, which builds a Release
`Aranet4Logger.app`, zips it, and publishes a GitHub Release with the artifact:

```sh
git tag v1.0.0
git push origin v1.0.0
```

The released app is ad-hoc signed (free Apple ID, not notarized), so first launch requires
right-click → Open to get past Gatekeeper.

### Auto-updates

The app updates itself via [Sparkle](https://sparkle-project.org). On each release the workflow
EdDSA-signs the zip and publishes an `appcast.xml` asset; the app's `SUFeedURL` points at
`releases/latest/download/appcast.xml`, so it always sees the newest release. Update integrity
is verified against the embedded `SUPublicEDKey` — independent of (and despite the lack of)
Apple notarization. The private signing key lives in the maintainer's Keychain and the
`SPARKLE_ED_PRIVATE_KEY` repo secret; it is never committed.

The app checks daily and installs automatically (`SUAutomaticallyUpdate`); there's also a
**Check for Updates…** menu item. Because the app is ad-hoc signed (no stable identity), an
update may re-trigger the one-time Bluetooth permission prompt. Existing installs from before
auto-updates were added must be updated manually once to a Sparkle-enabled release; subsequent
updates are automatic.

## Build

```sh
./build.sh
```

`build.sh` regenerates the Xcode project from `project.yml` (via
[xcodegen](https://github.com/yonaskolb/XcodeGen)) and builds with `xcodebuild`. It unsets
conda/pixi compiler environment variables (`LD`, `CC`, …) that otherwise hijack Xcode's
linker.

The built app is at `build/Build/Products/Debug/Aranet4Logger.app`. Launch it with:

```sh
open build/Build/Products/Debug/Aranet4Logger.app
```

On first launch, **approve the Bluetooth permission prompt** (or enable *Aranet4Logger* under
System Settings → Privacy & Security → Bluetooth).

### Signing

`project.yml` uses ad-hoc signing (`CODE_SIGN_IDENTITY = "-"`) so it builds with a free Apple
ID and no configuration. For a **stable** Bluetooth permission grant and login item that
survive rebuilds, open the project in Xcode and set Signing → Team to your free Personal Team
with Automatic signing. (Ad-hoc signatures change every build, which can re-trigger the
permission prompt.)

## Configuration

Configuration and data live under `~/Library/Application Support/Aranet4Logger/`:

- `config.json` — devices (CoreBluetooth UUID + name), poll interval, connect timeout,
  retries, and backoff. Aranet sensors are discovered automatically from the BLE scan and
  appended here as they're first seen; no devices are hardcoded. Rename a device in Settings
  (or by editing this file) — the chosen name is kept and never overwritten by a later scan.
  Note: the sensors only broadcast their factory `Aranet4 XXXXX` name over Bluetooth, so the
  custom names set in the official Aranet app are not visible to this app and must be set here.
- `aranet.sqlite` — the readings database (WAL mode).
- `aranet.log` — activity and error log.

Inspect the data anytime:

```sh
sqlite3 ~/Library/Application\ Support/Aranet4Logger/aranet.sqlite \
  "SELECT device, COUNT(*), MIN(timestamp), MAX(timestamp) FROM readings GROUP BY device;"
```

## Project layout

```
project.yml                       xcodegen project definition (source of truth)
build.sh                          regenerate project + build
Aranet4Logger/
  Aranet4LoggerApp.swift          @main; MenuBarExtra scene
  Models/Models.swift             Reading, DeviceConfig, AppConfig
  BLE/
    AranetProtocol.swift          UUIDs, decode + command builders (ported GATT protocol)
    BluetoothManager.swift        CBCentralManager: scan + serialized connections
    AranetSession.swift           per-connection GATT history download
    AsyncLock.swift               serializes radio access across devices
  Storage/Database.swift          libsqlite3 wrapper, dedup, lastTimestamp
  Collection/
    Coordinator.swift             per-device sync loops, retries, drives AppState
    ConfigStore.swift             JSON config load/save
  Menu/
    AppState.swift                @Observable UI state
    MenuView.swift                menu content
  LoginItem/LoginItemManager.swift  SMAppService login item
  Support/AppSupport.swift        paths + file logger
```

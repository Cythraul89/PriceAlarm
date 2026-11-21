# PriceAlarm

Watches the price of a product at one or more online shops once a day, at a
time you choose, and raises a local notification when the price reaches your
target. Offline-first, no account, no server.

## Features

**Items and offers**
- An item (e.g. "ASUS Radeon AI PRO R9700") has a target price, a daily check
  time and one or more shop offers (URLs).
- The alarm fires when the cheapest successfully read offer is at or below the
  target — once, when the price crosses it, not every day.
- **It rings like an alarm clock**: a looping alarm sound until you press
  Stop (auto-stop after 10 minutes) and a full-screen alarm screen.
  On Android it uses your alarm-clock sound at alarm-clock volume, also with
  the app closed and over the lock screen. Settings → Test alarm lets you
  hear it.

**Price retrieval**
- Prices are read from the schema.org structured data shops publish
  (JSON-LD `Product`/`Offer`, fallback Open Graph product meta tags).
- Per offer: `auto` (plain HTTP first, invisible WebView as fallback), `http`
  or `webview`. The method that worked is remembered.
- Every check outcome is stored: `ok`, `blocked`, `no price`, `network error`,
  `unsupported`. Failures are shown, never hidden.
- "Test" in the edit form fetches an offer once before saving.

**Data**
- Price history per offer (365 days).
- Local ZIP backup export/import.
- App log viewer (share, clear).

## Platforms

| Platform | Artifact | Scheduled check | Alarm | WebView fetch | Note |
|---|---|---|---|---|---|
| Android | `.apk` (debug + release) | background (WorkManager), may run minutes late | alarm-clock sound and volume, also with the app closed, full-screen over the lock screen | foreground only (see below) | release is debug-key-signed unless signing secrets are set |
| iOS | `.zip` of `Runner.app` (debug + release) | when the app is opened | loop sound while the app is open (plays with the silent switch on); media volume | yes | **unsigned** — not installable without re-signing |
| Linux | `.deb` amd64 (debug + release) | while the app runs / at next start | loop sound while the app runs; system volume | **no** | `flutter_inappwebview` has no stable Linux implementation |
| macOS | `.zip` of `.app` (debug + release) | while the app runs / at next start | loop sound while the app runs; system volume | yes | ad-hoc signed, not Gatekeeper-verified |
| Windows | `.zip` (debug + release) | while the app runs / at next start | loop sound while the app runs; system volume | yes | needs the WebView2 runtime (part of current Windows 10/11) |

Android background runs use plain HTTP only. An item with an offer that needs
the WebView (e.g. Galaxus) is checked at the next app start/resume instead.

## Known limitations

- **Galaxus** rejects plain HTTP requests (HTTP 403, verified 2026-11-21).
  Whether the WebView fallback gets through is **not yet verified**. If it
  does not, the offer stays `blocked` and the UI says so; the app does not try
  to evade bot protection.
- Automated reading of shop pages may conflict with a shop's terms of use. The
  app loads each offer once per day; checking the terms is up to the user.
- Offers in a currency other than the item's are shown but not compared.
- On iOS the alarm cannot ring while the app is closed (no background check
  in v0.1). On Android 14+, the full-screen alarm may need to be allowed once
  in Settings → "Allow alarm over lock screen"; without it, it still rings as
  a notification. The app never changes the system volume.

## Tech Stack

| Concern | Library |
|---|---|
| UI | Flutter, Material 3 |
| State | flutter_riverpod 2 (manual providers) |
| Navigation | go_router (`StatefulShellRoute.indexedStack`) |
| Database | drift (+ sqlite3 3.x) |
| Money | decimal |
| HTTP | dio |
| HTML / JSON-LD | html |
| WebView | flutter_inappwebview (`HeadlessInAppWebView`) |
| Notifications | flutter_local_notifications |
| Alarm sound | audioplayers (bundled, self-generated WAV) |
| Background (Android) | workmanager |
| Backup | archive, file_picker, share_plus |

## Getting Started

Prerequisites: Flutter (stable channel), plus the platform toolchain you build
for (Android SDK + Java 17, Xcode, or the Linux/Windows desktop toolchain).

```bash
cd src
flutter pub get
dart run build_runner build
flutter create --platforms=linux .     # platform folders are not committed
flutter run -d linux
```

Checks before a commit:

```bash
flutter analyze --fatal-infos
flutter test
```

Platform folders are generated, not committed. For a local Android build,
apply the same patches CI applies (permissions, desugaring) — see the Android
job in `.github/workflows/build.yml`.

## CI/CD

| Workflow | Trigger | What it does |
|---|---|---|
| `ci.yml` | push to `main`, `develop`, `feature/**`; PRs | analyse + test, then all builds via `build.yml` (version `<pubspec>-dev`) |
| `release.yml` | tag `vX.Y.Z` | same gate and builds, then a GitHub Release with all artifacts |
| `build.yml` | called by the two above | 5 platforms × debug + release, plus a CycloneDX SBOM |

Optional secrets: `ANDROID_RELEASE_KEYSTORE_B64`, `ANDROID_KEYSTORE_PASSWORD`,
`ANDROID_KEY_ALIAS`, `ANDROID_KEY_PASSWORD` (Android release key),
`MACOS_CERTIFICATE`, `MACOS_CERTIFICATE_PWD` (Developer ID). Without them the
builds still succeed with debug/ad-hoc signing.

No platform or mode is omitted. CI never contacts a shop; the extractor is
tested against a stored fixture.

## Project Structure

```
PriceAlarm/
├── doc/                 requirements, architecture, screens, class diagram
├── .github/workflows/   build.yml, ci.yml, release.yml
└── src/                 Flutter project
    ├── lib/core/        database, models, calculators, services, utils, widgets
    ├── lib/features/    items, item_detail, item_edit, settings
    ├── lib/shell/       adaptive navigation shell
    └── test/            unit, DAO, loopback-HTTP and widget tests
```

## Documentation

- [Requirements](doc/REQUIREMENTS.md)
- [Architecture](doc/ARCHITECTURE.md)
- [Screens](doc/SCREENS.md)
- [Class diagram](doc/CLASS_DIAGRAM.md)
- [Developer guide](CLAUDE.md) · [Contributing](CONTRIBUTING.md)

## License

GPL-3.0 — see [LICENSE](LICENSE).

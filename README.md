# TwinDrop

**Share once. Find it on either device.**

TwinDrop is a private Android ↔ Linux desktop text/link sharing app with a shared
categorized notepad. One Flutter/Dart codebase, a pure-Dart core, local-first
SQLite replicas on both devices, and a pinned-TLS WebSocket link over your own
Wi-Fi. No cloud, no account, no telemetry.

- **Desktop (Linux)** — hosts a pinned-TLS HTTPS/WSS endpoint, lives in the top
  bar, one-key popup (`--quick-send`), full Chat / Notepad / Settings window.
- **Phone (Android)** — share-sheet target (Instagram/Reels link → Inbox in one
  tap), chat, notepad, optional keep-alive foreground service so desktop→phone
  messages arrive with the app closed.

App id: `app.twindrop` · Default port: `47321` · Protocol version: `1`

## Repository layout

```
docs/                 Spec pack (source of truth) + DECISIONS/PROGRESS
design/               tokens.json, logo + tray SVGs
packages/core/        Pure Dart: drift DB, HLC, merge rules, sync engine,
                      TLS identity/pinning, pairing, validators, export
app/                  Flutter app (Android + Linux) and platform adapters
packaging/            AppImage build, generated icons
tool/                 doctor.sh, build_android.sh, build_linux.sh, build_all.sh,
                      fake_peer.dart, smoke tests
dist/                 Generated artifacts (gitignored)
BUILD_STATUS.md       Evidence log: commands, test counts, artifacts, blockers
```

## Build

```bash
./tool/doctor.sh                  # toolchain + Linux dependency report
cd packages/core && dart pub get
cd app && flutter pub get
dart run build_runner build --delete-conflicting-outputs   # drift codegen (in app or core)
./tool/build_all.sh               # analyze + test + APK + AppImage + smoke test
```

Outputs: `dist/twindrop.apk`, `dist/TwinDrop-x86_64.AppImage`, each with `.sha256`.

## Run (development)

```bash
cd app
flutter run -d linux              # desktop
flutter run -d <android-device>   # phone
```

## Docs

Start at [docs/00-product-brief.md](docs/00-product-brief.md), requirements in
[docs/01-requirements.md](docs/01-requirements.md), the work queue in
[docs/11-roadmap.md](docs/11-roadmap.md), and the design system in
[docs/13-design-system.md](docs/13-design-system.md). Build evidence and honest
status live in [BUILD_STATUS.md](BUILD_STATUS.md); implementation decisions in
[docs/DECISIONS.md](docs/DECISIONS.md).

## Status

See [BUILD_STATUS.md](BUILD_STATUS.md). Anything not verified there is not claimed
to work.

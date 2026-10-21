# 10 — Build & Release

Adapt commands to the actually installed versions; leave working scripts in `tool/`. Never report an artifact that isn't on disk.

## Prerequisites (`tool/doctor.sh` checks and prints them)
Flutter stable (pin version), Dart 3; Linux deps: `clang cmake ninja-build pkg-config libgtk-3-dev liblzma-dev libayatana-appindicator3-dev libsecret-1-dev libnotify-dev` (+ `libfuse2` to run AppImages on older distros), `appimagetool`, `linuxdeploy`; Android: JDK 17, SDK (current platform + build-tools), `adb`.

## First-time setup
```
flutter doctor -v                       # save sanitized summary to BUILD_STATUS.md
(cd packages/core && dart pub get)
(cd app && flutter pub get)
dart run build_runner build --delete-conflicting-outputs   # drift codegen
dart format --output=none --set-exit-if-changed packages app
dart analyze
(cd packages/core && dart test --coverage=coverage)
(cd app && flutter test)
```

## Android: `tool/build_android.sh`
Checks prerequisites → `flutter build apk --release` (uses `android/key.properties` if present, else debug signing with a loud warning) → verifies non-zero size → copies to `dist/twindrop.apk` → writes `.sha256` → prints `aapt dump badging` summary (package, version, permissions). Debug path: `flutter build apk --debug && adb install -r build/app/outputs/flutter-apk/app-debug.apk`. Never commit or fabricate signing keys.

## Linux: `tool/build_linux.sh` → `packaging/appimage/build.sh`
See `docs/07-linux.md` §AppImage. Output `dist/TwinDrop-x86_64.AppImage` + `.sha256`; print path, bytes, checksum, tool versions.

## All: `tool/build_all.sh`
Runs analyze + tests, then both builds, then `tool/smoke_test_appimage.sh` (launch with `--hidden`, wait for health endpoint on loopback, quit via `--quit`).

## Versioning
`pubspec.yaml` `MAJOR.MINOR.PATCH+BUILD`; shown in Settings → About; tag `v0.1.0`. Protocol version is separate (`protocolVersion` = 1).

## CI (optional)
`core-tests` (analyze+tests), `linux` (build AppImage on Ubuntu 22.04, upload), `android` (build APK, upload). CI must not contain tokens, signing keys, private certs, or real notes. GUI/tray/share-sheet E2E stay manual.

## Install notes (`INSTALL.md`)
Linux: put AppImage in `~/Applications`, `chmod +x`, run once; GNOME users may need the AppIndicator extension. Android: enable "Install unknown apps" for your file manager/browser, open the APK.

## Final report format
Toolchain versions · exact commands + results · artifact path/bytes/SHA-256 · tested devices/sessions · verified features · compiled-but-unverified features · blockers. Never call a blocked output "complete".

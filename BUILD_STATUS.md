# BUILD_STATUS.md — evidence log

> Rule: nothing here is marked ✔ unless the exact command was run and its real
> output recorded. Manual items that cannot run in this environment are marked
> **BLOCKED** with the reason. See `AGENTS.md`.

## Current state
- Phase: 0 — Inspect & scaffold (in progress)
- Date: 2026-10-21
- Commit: (pending first scaffold commit)
- Host: Fedora Linux 44 (Workstation), x86_64, GNOME/Wayland session on `DISPLAY=:0`
- Working dir: `/data/Projects/TwinDrop`
- Repo: https://github.com/nilaymallikk/twindrop

## Toolchain
- OS / kernel / arch: Fedora 44 / 7.2.11-200.fc44.x86_64 / x86_64
- Flutter / Dart: 3.47.7 stable, Dart 3.13.5 — userland at `/data/toolchain/flutter`
  (`flutter doctor -v`: Flutter ok, Android toolchain ok (SDK 36.0.0, build-tools
  36.0.0, JDK 17 Temurin, licenses accepted); Linux toolchain listed clang missing
  until `packaging/toolchain/bin` wrappers to GCC 16.2.1 were prepended to PATH)
- Standalone Dart: 3.13.6 at `/data/toolchain/dart/dart-sdk` (core package development)
- JDK: Temurin 17 (userland, `/data/toolchain/jdk17`) — host has JRE 25 only, no javac
- Android SDK: command-line tools at `/data/toolchain/android-sdk` (platform/build-tools to install)
- AppImage tooling: to download (`appimagetool`, no root; FUSE may be absent → extract-and-run)
- Linux desktop build deps: **not installed system-wide** (no sudo). A userland
  Fedora 44 sysroot at `/data/toolchain/sysroot` provides gtk3-devel,
  libsecret-devel, libnotify-devel, libayatana-appindicator-gtk3-devel,
  libdbusmenu-devel + recursive closure (pixman/dbus/libxml2/libmount/libblkid/
  sysprof-capture headers); `pkg-config --cflags` for gtk+-3.0/libsecret-1/
  libnotify/ayatana-appindicator3-0.1/dbusmenu-glib-0.4 resolves with every
  include dir present (verified). Builds use `PKG_CONFIG_SYSROOT_DIR` /
  `PKG_CONFIG_PATH` (see `tool/env.sh`, `docs/DECISIONS.md` D-002/D-005).
- clang/clang++: not installed; `packaging/toolchain/bin` wrappers to GCC 16.2.1
  (D-006).

## Implemented (by requirement ID)
- None yet.

## Commands run
| Command | Result | Notes |
|---|---|---|
| `dnf install --installroot=/data/toolchain/sysroot --use-host-config ...` | pass | non-root userland sysroot, 279 packages |
| `flutter --version` | pending | SDK download in progress |
| `dart --version` | pending | standalone SDK download in progress |

## Tests
| Suite | Passed | Failed | Skipped | Coverage |
|---|---:|---:|---:|---:|
| core unit | — | — | — | — |
| app widget | — | — | — | — |
| integration (two peers, loopback) | — | — | — | — |

## Artifacts
| Artifact | Path | Bytes | SHA-256 | Launched/installed? |
|---|---|---:|---|---|
| APK | not built | — | — | no |
| AppImage | not built | — | — | no |

## End-to-end verification (never mark ✔ without evidence)
| Check | Environment | Status | Evidence |
|---|---|---|---|
| Pair (QR + approve + code match) | | not tested | |
| Pin mismatch rejected | | not tested | |
| Revoke blocks old token | | not tested | |
| Phone → desktop message | | not tested | |
| Desktop → phone message (app closed, service on) | | not tested | |
| Share URL → Inbox (cold start) | | not tested | |
| Share URL → Inbox (warm start) | | not tested | |
| Offline share syncs once | | not tested | |
| Concurrent edit → conflict copy | | not tested | |
| Tray on GNOME Wayland (Fedora) | | not tested | |
| Tray on GNOME (Ubuntu) / KDE | | not tested | |
| AppImage runs on clean VM | | not tested | |
| AppImage without FUSE (extract-and-run) | | not tested | |

## Blockers / limitations
- No sudo on the host; system packages cannot be installed. Mitigation: userland
  sysroot + toolchain under `/data/toolchain` (see D-002).
- No physical Android device attached; emulator may be usable via `/dev/kvm`
  (TBD). Real-device-only checks will be marked BLOCKED in this file.
- Only one Linux desktop session available (Fedora GNOME Wayland); Ubuntu GNOME and
  KDE tray checks are BLOCKED unless additional sessions can be run.

## Next concrete task
- Phase 0 exit: themed blank app runs on Linux, debug APK builds, `dart test` runs in core.

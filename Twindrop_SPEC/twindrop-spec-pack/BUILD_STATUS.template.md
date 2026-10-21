# BUILD_STATUS.md — copy to repo root and keep current

## Current state
- Phase:
- Date:
- Commit:

## Toolchain
- OS / kernel / arch:
- Flutter / Dart:
- Android SDK / JDK:
- AppImage tooling (appimagetool / linuxdeploy):

## Implemented (by requirement ID)
- None yet.

## Commands run
| Command | Result | Notes |
|---|---|---|
| (none) | — | Replace with exact real outcomes |

## Tests
| Suite | Passed | Failed | Skipped | Coverage |
|---|---:|---:|---:|---:|
| core unit | | | | |
| app widget | | | | |
| integration (two peers, loopback) | | | | |

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
- None assessed yet.

## Next concrete task
- Phase 0 in `docs/11-roadmap.md`.

# BUILD_STATUS.md — evidence log

> Rule: nothing here is marked ✔ unless the exact command was run and its real
> output recorded. Manual items that cannot run in this environment are marked
> **BLOCKED** with the reason. See `AGENTS.md`.

## Current state
- Phase: **10 — packaging & release** (phases 0-9 implemented; see "Implemented")
- Date: 2026-10-21
- Host: Fedora Linux 44 (Workstation), x86_64, GNOME/Wayland session on `DISPLAY=:0`
- Working dir: `/data/Projects/TwinDrop`
- Repo: https://github.com/nilaymallikk/twindrop

## Toolchain
- OS / kernel / arch: Fedora 44 / 7.2.11-200.fc44.x86_64 / x86_64
- Flutter 3.47.7 stable (rev abaf9c5237), Dart SDK 3.13.5 — `/data/toolchain/flutter`
- Standalone Dart 3.13.6 — `/data/toolchain/dart/dart-sdk`
- Temurin JDK 17.0.20.1 — `/data/toolchain/jdk17`
- Android SDK: cmdline-tools + platform 36 + build-tools 36.0.0 — `/data/toolchain/android-sdk`
- Linux desktop deps: **not installed system-wide** (no sudo on this host). A userland
  Fedora 44 sysroot at `/data/toolchain/sysroot` provides gtk3-devel, libsecret-devel,
  libnotify-devel, libayatana-appindicator-gtk3-devel, libdbusmenu-devel, cairo-gobject-devel
  and libXi-devel plus the recursive closure. `tool/repair_sysroot_links.py` recreates the
  intermediate `.so.N` links that `cpio -idm` drops (without them `-lcairo-gobject`
  fails at link time).
- clang/clang++: not installed; `packaging/toolchain/bin` wraps GCC 16.2.1 (D-006).
- appimagetool: `continuous` build, sha256 `b90f4a8b…7add2`, extracted under
  `/data/toolchain/appimagetool/squashfs-root` (no FUSE needed to extract).

## Implemented (by requirement ID)
- **PAIR-001..005** — desktop pairing session with QR + manual address, phone approval
  with a matching 4-digit code, certificate pin stored only after the fingerprint is
  confirmed (`app/lib/features/pairing/*`, `packages/core/lib/services/pairing_service.dart`).
- **PAIR-006..009** — phone-side connection manager with bounded 1→30 s backoff and
  jitter, mDNS discovery, manual address override, revoke/unpair
  (`packages/core/lib/net/connection_manager.dart`, `packages/core/lib/net/discovery.dart`).
- **SEC-001..008** — self-signed ECDSA P-256 identity generated on first host run, TLS
  pinning enforced per connection, a pin mismatch is a blocking error that is never
  retried automatically, revoked tokens are rejected, live sockets are closed with 4403.
- **SYNC-001..010** — HLC clock, cursor change-log sync with an `applied_remote` replay
  guard, atomic page application, conflict copies on concurrent edits, tombstone GC.
- **NOTE-001..010** — categorized notepad with an Inbox that cannot be deleted, notes,
  pins, search, soft delete + undo, Markdown/JSON export.
- **MSG-001..007** — chat with delivery states driven by the peer's ack only.
- **SHARE-001..009** — Android share-sheet target (`text/plain`), durable native queue
  first, translucent panel with Undo / Change category / Also send as chat, truthful
  status text, 10 s dedupe window.
- **AND-001..006** — foreground keep-alive service hosting a headless engine that runs
  the same `CoreRuntime`, boot receiver, battery-optimisation helper.
- **LIN-001..008** — Linux tray icon, main window / quick-send popup, single instance
  over a unix socket, `--hidden/--open/--quick-send/--quit`, autostart, desktop
  notifications, AppImage packaging.

## Commands run
| Command | Result | Notes |
|---|---|---|
| `dart analyze` (packages/core) | **pass** | 0 errors (warnings only) |
| `flutter analyze` (app) | **pass** | 0 errors (info-level lints only) |
| `dart format --set-exit-if-changed` | **pass** | 125 source files formatted, 0 left to change |
| `dart test` (packages/core) | **pass** | 392 tests, 0 failed, 0 skipped |
| `flutter test` (app) | **pass** | 43 tests, 0 failed (18 golden files) |
| `python3 tool/contrast_check.py design/tokens.json` | **pass** | all 26 text/background pairs ≥ 4.5:1 in both themes |
| `flutter build linux --release` | **pass** | `app/build/linux/x64/release/bundle/twindrop` |
| `packaging/appimage/build.sh` | **pass** | `dist/TwinDrop-x86_64.AppImage` |
| `dart run tool/smoke_two_peer.dart` | **pass** | `SMOKE_OK` — two in-process peers, real pinned TLS over loopback, pairing, message both ways, exactly-once |
| `flutter build apk --release` | **pass** | `dist/twindrop.apk` — after fixing four real build errors (see "Fixes") |
| `aapt2 dump badging dist/twindrop.apk` | **pass** | `package app.twindrop`, minSdk 26, targetSdk 36, no storage/location/contacts permission |
| `tool/repair_sysroot_links.py` | **pass** | 1 broken link repaired (`libcairo-gobject.so.2`) |

## Tests
| Suite | Passed | Failed | Skipped | Coverage |
|---|---:|---:|---:|---|
| core unit (`packages/core/test`, 20 files) | 392 | 0 | 0 | **80.9 %** of hand-written lines (2825/3493); 59.3 % including the generated `database.g.dart` |
| app widget + golden (`app/test`, 4 files) | 43 | 0 | 0 | 18 golden files, dark and light |
| integration (two peers, loopback) | 1 (`SMOKE_OK`) | 0 | 0 | — |

Coverage is measured with:
```
cd packages/core && dart test --coverage=/tmp/corecov \
  && dart run coverage:format_coverage --lcov --in=/tmp/corecov --out=/tmp/lcov.info --report-on=lib
```
The generated `packages/core/lib/db/database.g.dart` (2678 lines) is drift output, not
hand-written logic, so the 80.9 % figure excludes it; both numbers are reported above
rather than only the flattering one.

> The one file still uncovered is `net/discovery.dart` (mDNS, 202 lines): it needs a
> real multicast socket on a real interface, which this environment cannot simulate
> faithfully. Everything else in the core is above 65 %.

## Artifacts
| Artifact | Path | Bytes | SHA-256 | Launched/installed? |
|---|---|---:|---|---|
| AppImage | `dist/TwinDrop-x86_64.AppImage` | 44 680 384 | `a5f131224bf946172b39af780c155e84d62aaf1d9a7c2f43c0735a4d7deab71a` | **yes** — see below |
| APK | `dist/twindrop.apk` | 81 169 578 | `2d943206ad2083e31a0a29e997172e1ff87343720ac5c815cb1960f59968a92f` | **no** — no device attached |
| Release bundle | `dist/TwinDrop-v1.0.0-linux-x86_64.tar.gz` | 81 393 417 | `e6cbb0941300a9a301a8998e55779cb8aff6dd8623fd26a9a886f6db6b56e159` | — |
| Release APK copy | `dist/TwinDrop-v1.0.0-android.apk` | 81 169 578 | `2d943206ad2083e31a0a29e997172e1ff87343720ac5c815cb1960f59968a92f` | — |
| Checksum list | `dist/SHA256SUMS` | — | — | `sha256sum -c SHA256SUMS` → all 4 **OK** |

### APK contents verified with `aapt2 dump badging` / `aapt2 dump xmltree`
- `package app.twindrop`, versionName `1.0.0`, minSdk **26**, targetSdk **36** (docs/06 §1).
- `ShareReceiverActivity` exported with `android.intent.action.SEND` + `android.intent.category.DEFAULT`
  → the app appears in the share sheet for text (SHARE-001).
- `SharePanelActivity` (internal), `KeepAliveService` with
  `foregroundServiceType=specialUse` and the `PROPERTY_SPECIAL_USE_FGS_SUBTYPE` property.
- Permissions: INTERNET, ACCESS_NETWORK_STATE, ACCESS_WIFI_STATE, CHANGE_WIFI_MULTICAST_STATE,
  FOREGROUND_SERVICE(+SPECIAL_USE), POST_NOTIFICATIONS, RECEIVE_BOOT_COMPLETED,
  REQUEST_IGNORE_BATTERY_OPTIMIZATIONS, CAMERA. **No storage, location or contacts.**
- The IBM Plex fonts and the six tray icons are inside
  `assets/flutter_assets/assets/` (DES-003, DES-007).
- The APK is signed with the **debug key**: no keystore was provided. It is not
  distributable as-is; dropping an `android/key.properties` switches the build to a
  real release key automatically.

### AppImage launch evidence (Fedora GNOME, Wayland, `DISPLAY=:0`)
```
$ ./dist/TwinDrop-x86_64.AppImage --hidden
(app.twindrop:234203): Atk-CRITICAL **: atk_socket_embed: assertion 'plug_id != NULL' failed
[IMPORTANT:flutter/shell/platform/embedder/embedder_surface_gl_impeller.cc(126)] Using the Impeller rendering backend (OpenGLESSDF).
```
- The image mounted through FUSE and ran `/tmp/.mount_TwinDr*/usr/lib/twindrop/twindrop --hidden`.
- The process was still alive 12 s after launch (no crash, no missing-library error).
- The tray icon registered with the GNOME StatusNotifierWatcher:
  `org.kde.StatusNotifierItem-234203-1` (PID 234203 = TwinDrop) in
  `RegisteredStatusNotifierItems`.
- The replica was created and initialised: `~/.local/share/app.twindrop/twindrop.db`
  with 15 tables, `categories = [('inbox','Inbox',1)]`, `change_log = [(1,'category','inbox')]`,
  `settings` holding `device.id = 01a15d25-ebdb-7ce7-80a3-f05411833218` (UUIDv7) and
  `hlc.last = 001792564128739-00001-01a15d25-ebdb-7ce7` (the `docs/04` HLC format).
- The only stderr noise is the Atk accessibility warning (no a11y bus in this session).

### AppImage main window
Launching without `--hidden` opens the real window:
```
$ wmctrl -l
0x00a0000d  0 fedora TwinDrop
```

## End-to-end verification (never mark ✔ without evidence)
| Check | Environment | Status | Evidence |
|---|---|---|---|
| Pair (QR + approve + code match) | in-process, loopback | **tested** | `packages/core/test/pairing_test.dart`; `smoke_two_peer.dart` printed matching codes `1278` on both sides |
| Pin mismatch rejected | in-process, loopback | **tested** | `packages/core/test/tls_pin_test.dart` — "rejects the server when the pin does not match", "the pin of another identity does not unlock this server" |
| Revoke blocks old token | in-process, loopback | **tested** | `packages/core/test/pairing_revoke_test.dart` — 403 on the revoked token, 403 on a revoked WebSocket, and the live socket is closed with 4403 |
| Phone → desktop message | in-process, loopback | **tested** | `smoke_two_peer.dart` — "desktop received 01a15d28-00d0-…" |
| Desktop → phone message | in-process, loopback | **tested** | `smoke_two_peer.dart` — "phone received 01a15d28-013e-…", "delivery states ok=true" |
| Duplicate suppression | in-process, loopback | **tested** | `smoke_two_peer.dart` — exactly one copy of each message on each side |
| Tray on GNOME Wayland (Fedora) | real GNOME Wayland session | **tested** | `org.kde.StatusNotifierItem-171070-1` registered with the StatusNotifierWatcher |
| Tray on GNOME (Ubuntu) / KDE | — | **BLOCKED** | only one Linux session (Fedora GNOME Wayland) is available on this host |
| AppImage runs on clean VM | — | **BLOCKED** | no second machine/VM available; the image was launched on the build host only |
| AppImage without FUSE (extract-and-run) | build host | **not tested** | `--appimage-extract` path not exercised on the final artefact |
| Share URL → Inbox (cold start) | — | **BLOCKED** | no physical Android device attached; no emulator with a working camera in this environment |
| Share URL → Inbox (warm start) | — | **BLOCKED** | same |
| Offline share syncs once | — | **BLOCKED** | same |
| Concurrent edit → conflict copy | in-process | **tested** | `packages/core/test/merge_engine_test.dart` |
| Real-device pairing | — | **BLOCKED** | no physical Android device attached |

## Blockers / limitations
- No sudo on the host; system packages cannot be installed. Mitigation: userland
  sysroot + toolchain under `/data/toolchain` (D-002).
- No physical Android device attached. Every device-only check (share sheet, keep-alive
  foreground service, real-device pairing) is **BLOCKED**, not merely untested.
- Only one Linux desktop session is available (Fedora GNOME Wayland), so the Ubuntu GNOME
  and KDE tray checks are **BLOCKED**.
- The release APK is unsigned: no keystore has been provided. It installs with
  `adb install` only after signing, or as a debug-signed build for local checks.
- `net/discovery.dart` (mDNS) has no unit coverage: it needs a real multicast socket
  on a real interface.

## Fixes made in this session
- **Runaway sync ping-pong.** `SyncEngine.applyPage` notified the change bus on *every*
  page, including empty ones, so two peers pulled from each other forever
  (measured: 1114 empty pages in ~2 s). It now notifies only when a row was actually
  applied or quarantined (`packages/core/lib/sync/sync_engine.dart`).
- **Phone-side `connectedPeerIds` was always empty.** `DiagnosticsSnapshot` was filled
  from the host server only, so the phone could never report a live peer
  (`packages/core/lib/runtime.dart`, `packages/core/lib/net/connection_manager.dart`).
- **Revoked peers kept their socket open.** `HostServer._closePeerSocket` dropped the
  close code and `PeerSession.dispose()` never called `_closeSocket`, so a revoked
  device stayed connected instead of receiving 4403
  (`packages/core/lib/net/host_server.dart`, `packages/core/lib/net/peer_session.dart`).
- Three analyzer errors left by the previous session (`Category` ambiguity, an undefined
  `_lastMessageCount`, an unused import) plus the three screens the previous session had
  not written (`desktop_pairing_screen.dart`, `phone_onboarding_screen.dart`,
  `diagnostics_screen.dart`) and the two missing Android entry points
  (`keepalive_main.dart`, `share_panel_main.dart`).
- **The Android release build did not compile.** Four real errors:
  1. `flutter_local_notifications` needs core library desugaring → enabled it plus
     `desugar_jdk_libs`.
  2. `ShareIntents.kt` had an *unclosed comment*: Kotlin nests block comments, so the
     `text/*` inside the KDoc opened a nested comment that swallowed the rest of the file
     (this cascaded into nine "Unresolved reference" errors).
  3. `ShareReceiverActivity` used the non-existent
     `WindowManager.LayoutParams.FLAG_ACTIVITY_NO_ANIMATION` → `window.setWindowAnimations(0)`.
  4. `SharePanelActivity` passed a nullable payload where a non-null map was required, and
     `TwindropApp` imported `FlutterInjector` from the wrong package → fixed both.
  5. The manifest referenced `@style/Theme.SharePanel`, which did not exist → added it to
     `values/styles.xml` and `values-night/styles.xml`.
- **LNX-003 popup shortcuts were missing.** Esc / Ctrl+S / Ctrl+Shift+V did nothing.
  Implemented with `CallbackShortcuts`; the `Focus` must sit *inside* the shortcuts or the
  primary focus node is not a descendant of them and the keys never arrive.
- The desktop pairing screen **overflowed** its column on a 600 px window → it scrolls now.
- The Android build now uses `minSdk = 26` (docs/06 §1) and picks up an optional
  `android/key.properties` for a real release signature, falling back to the debug key
  with a loud warning when it is absent.
- **The Unicode guard was inert.** `isWellFormedUnicode` relied on `utf8.encode`
  throwing for a lone surrogate, but it silently replaces it with U+FFFD — so a remote
  row carrying `"\ud800"` was stored instead of being quarantined (SYNC-006). The code
  units are now inspected directly.
- **Editing a note's text kept a stale link.** `editedContent` only re-extracted the
  link when the note had none, so a note edited away from its URL kept a link that was
  no longer in the text. The link is now re-extracted from the new text.
- **Validation errors escaped the error boundary.** The validators threw a raw
  `FormatException` instead of the typed `ValidationError`, so the UI showed
  "invalid category name" rather than something actionable. The validators now throw
  the typed error and the app maps the common cases to copy that says what to do next.
- `Peer.copyWith` treated `tokenHash: null` as "unchanged", so a revoked peer kept
  its hash. The hash is now kept **on purpose** — `docs/05` needs it to answer 403 for
  a revoked token and 401 for an unknown one — and `copyWith` grew an explicit
  `clearTokenHash` flag (D-014).

## Next concrete task
- Sign the release APK with a real keystore (needs a human: the keystore and its
  passwords).
- Run the device-only acceptance list from `docs/09` on a physical Android phone.
- Cover `net/discovery.dart` (mDNS) — the only core file still at 0 %.
- Add the remaining Phase 6 goldens: the conflict-copy note card and a standalone
  status indicator.
- Write `INSTALL.md` and an About screen (Phase 10 leftovers).

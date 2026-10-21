# DECISIONS.md — implementation decision log

Format: `D-NNN | date | question | choice | reason`. Deviations from the spec pack
are called out explicitly. Spec-level ADRs live in `docs/12-decisions-risks.md`.

## D-001 | 2026-10-21 | Repository base
**Question:** The GitHub repo `nilaymallikk/twindrop` contained only a README, while
the spec pack lives in `Twindrop_SPEC/`.
**Choice:** Keep the spec pack under `Twindrop_SPEC/` untouched; copy its `docs/`,
`design/`, `AGENTS.md` to the repo root where `docs/03-architecture.md` expects them;
build on top of the remote `main` commit.
**Reason:** Spec layout expects `docs/` and `design/` at repo root; the original pack
is preserved for diffing against `MANIFEST.md`.

## D-002 | 2026-10-21 | No sudo / system packages missing
**Question:** The build host is Fedora 44 without passwordless sudo and with no
Flutter, Dart, Android SDK, clang, GTK3 dev headers, libsecret/libnotify dev headers.
**Choice:** Install the entire toolchain in userland under `/data/toolchain`:
Flutter 3.47.7 stable, standalone Dart 3.13.6, Temurin JDK 17, Android command-line
tools, and a Fedora sysroot built with
`dnf install --installroot=/data/toolchain/sysroot --use-host-config` (works non-root)
containing `gtk3-devel`, `libsecret-devel`, `libnotify-devel`,
`libayatana-appindicator-gtk3-devel`, `libdbusmenu-glib-devel`. Builds point pkg-config
at the sysroot via `tool/env.sh`.
**Reason:** No destructive privileged action; reproducible; AppImage bundling needs the
same libs anyway. Never requires weakening TLS or stubbing features.

## D-003 | 2026-10-21 | Flutter/Dart version pin
**Question:** Spec says "Flutter 3.x stable, Dart 3".
**Choice:** Flutter 3.47.7 stable (Dart 3.13.5). Pubspec constraints `sdk: ^3.13.0`.
**Reason:** Current stable at build time; satisfies spec.

## D-004 | 2026-10-21 | TLS server implementation
**Question:** `shelf` + `shelf_web_socket` vs `dart:io` `HttpServer.bindSecure` directly.
**Choice:** `dart:io` `HttpServer.bindSecure` + `WebSocketTransformer` in
`packages/core`, wrapped behind a small `HostServer` interface.
**Reason:** Fewer dependencies, direct control over TLS `SecurityContext`, the exact
pin-fetch endpoint for manual pairing, upgrade headers (`Authorization` on WS upgrade),
and close codes. Spec explicitly allows this option.

## D-005 | 2026-10-21 | Linux GUI dev headers without sudo
**Question:** `gtk+-3.0`, `libsecret-1`, `libnotify`, `libayatana-appindicator3`,
`libdbusmenu` development files are absent and the host has no passwordless sudo.
**Choice:** A userland Fedora 44 sysroot under `/data/toolchain/sysroot`, populated
with `dnf download --resolve` + `rpm2cpio | cpio -idm` (no rpm transaction, no root).
`tool/env.sh` exports `PKG_CONFIG_SYSROOT_DIR`/`PKG_CONFIG_PATH` so pkg-config and
CMake resolve headers/libs there. Runtime libs not present on the host (appindicator,
dbusmenu) will be bundled into the AppImage.
**Reason:** Reproducible, non-destructive, no fake substitues; AppImage needs those
libraries bundled anyway.

## D-006 | 2026-10-21 | Flutter Linux build wants clang
**Question:** Flutter 3.47 passes `CC=clang` / `CXX=clang++` to CMake; the host has no
clang and cannot install packages.
**Choice:** `packaging/toolchain/bin/{clang,clang++}` are thin wrappers that exec
`gcc`/`g++` (GCC 16.2.1). `tool/env.sh` prepends that directory to `PATH`.
**Reason:** Flutter's Linux runner and plugins are plain C/C++ and build with GCC;
this avoids a 1GB LLVM download and keeps the toolchain userland. Recorded as a
deviation from `docs/10` ("clang" prerequisite).

## D-007 | 2026-10-21 | Android share flow: native queue + Flutter panel
**Question:** `docs/06` wants a share panel in <=1.5 s cold start but `docs/13`/`docs/09`
require the panel to be design-tested as a widget.
**Choice:** `ShareReceiverActivity` synchronously writes the share payload into a
durable native queue (SharedPreferences JSON, idempotent shareId) and launches a
translucent `SharePanelActivity` that hosts a minimal Flutter engine showing the
shared SharePanel widget. Dart imports the native queue into SQLite on start
(core `ShareIngest`, dedupe 10 s) and applies queued panel actions.
**Reason:** Nothing is lost even if the Flutter engine is slow or killed; panel UI
stays spec-compliant, reusable and widget-testable; single protocol/SQLite write path.

## D-008 | 2026-10-21 | The change bus is only notified on a real change
**Question:** `SyncEngine.applyPage` notified the change bus after every applied page,
including pages that changed nothing.
**Choice:** Notify only when at least one row was applied or quarantined.
**Reason:** The bus drives both the UI and the `notify` frame to the peer. Notifying on
an empty page made two peers pull from each other forever — measured at 1114 empty pages
in ~2 s, burning CPU and the network. The cursor sync is authoritative, so an empty page
carries no information the peer does not already have.

## D-009 | 2026-10-21 | The peer socket is closed with the right code
**Question:** `HostServer._closePeerSocket` took a close code and a reason but dropped
them, and `PeerSession.dispose()` never called `_closeSocket` at all.
**Choice:** `PeerSession.dispose({code, reason})` closes the socket with the given code;
`_closePeerSocket` forwards 4403 (`forbidden` / `revoked`) on revocation.
**Reason:** `docs/08` requires that revocation closes live sockets with 4403. Without it
a revoked device kept its socket open even though every new request was rejected.

## D-010 | 2026-10-21 | Phone-side diagnostics report the live session
**Question:** `DiagnosticsSnapshot.connectedPeerIds` was filled from the host server
only, so on the phone it was always empty.
**Choice:** `ConnectionManager` exposes `connectedPeerIds` (the peer of the live
session) and the runtime uses it on the phone and the host's own set on the desktop.
**Reason:** The diagnostics screen and the two-peer smoke test need to see the real
connection state, not a guess from the status enum.

## D-011 | 2026-10-21 | Release APK signing
**Question:** No release keystore was provided, but `dist/twindrop.apk` has to exist.
**Choice:** `app/android/app/build.gradle.kts` reads an optional
`android/key.properties` (`storeFile`, `storePassword`, `keyAlias`, `keyPassword`)
and uses a real `release` signing config when it exists. Without it the release build
is signed with the debug key and the build logs a warning.
**Reason:** The keystore and its passwords are the user's to provide (AGENTS.md, "Things
only a human can do"). The build must still produce an inspectable artefact, and the
signing path must be ready the moment the keystore appears.

## D-012 | 2026-10-21 | Desktop popup keyboard shortcuts
**Question:** `docs/01` LNX-003 requires Esc / Ctrl+S / Ctrl+Shift+V in the tray popup.
**Choice:** `ChatPopup` wraps its surface in `CallbackShortcuts`, with a `Focus`
**inside** the shortcuts. Ctrl+S saves the newest message to the Notepad;
Ctrl+Shift+V sends the clipboard.
**Reason:** The shortcut map is only consulted for focus nodes that are descendants of
the `Shortcuts` widget, so the `Focus` has to be the inner widget. Ctrl+S acts on the
newest message because the popup has no selection concept of its own.

## D-013 | 2026-10-21 | Userland sysroot library links
**Question:** `cpio -idm` extraction of the Fedora RPMs produced the versioned library
files but not always the intermediate `.so.N` symlink, so `-lcairo-gobject` failed at
link time.
**Choice:** `tool/repair_sysroot_links.py` recreates every missing intermediate link by
matching the versioned file in the same directory.
**Reason:** The sysroot has to satisfy the linker, not just `pkg-config`. The script is
idempotent and only ever creates links to files that already exist in the sysroot.

## D-014 | 2026-10-21 | The revoked token hash is kept on purpose
**Question:** `PeerRegistry.revoke` wrote `tokenHash: null`, but `Peer.copyWith` treats
`null` as "unchanged", so the hash was never actually cleared.
**Choice:** The hash is **kept** when a peer is revoked, and `Peer.copyWith` gained an
explicit `clearTokenHash` flag for the cases that really do want to drop it.
**Reason:** `docs/05` requires an unknown token to answer **401** and a *revoked* one to
answer **403**. The stored hash is the only way to tell the two apart. It is still only
`sha256(token)`, never the token, so nothing sensitive is retained.

## D-015 | 2026-10-21 | Validation failures throw the typed error
**Question:** The validators threw a raw `FormatException`, which escaped the service
boundary even though `models/errors.dart` says every failure that can cross a boundary
must be a `TwinDropError`.
**Choice:** `validateMessageText`, `validateNoteText`, `validateTitle` and
`validateCategoryName` throw `ValidationError`. The app maps the four common cases to
actionable copy in `AppController._messageFor`.
**Reason:** `docs/03` §Error boundary and `docs/02` ("every error says what to do
next"). The raw exception told the user "invalid category name" instead of "use a name
of 1 to 60 letters that is not already used".

## D-016 | 2026-10-21 | Only the plugins the app uses
**Question:** `app/pubspec.yaml` carried `flutter_riverpod`, `share_plus`,
`package_info_plus` and `cupertino_icons`, none of which the code imports. The app has
its own `ShareReceiverActivity`, its own `AppController` (a `ChangeNotifier`) and its
own `twindrop/app` channel for the version.
**Choice:** Those four are removed. `flutter_local_notifications` stays: it is the
Linux implementation of the desktop notifications.
**Reason:** Every Android plugin in the dependency list is registered at process start,
whether or not the app calls it. An unused plugin is startup surface for nothing — and
`share_plus` also added a `FileProvider` to the manifest. Cutting the surface is the
difference between "the app starts" and "the app starts unless a plugin I never use
misbehaves on your device".

## D-017 | 2026-10-21 | A startup failure must be visible
**Question:** The first Android build quits immediately on a real phone, with nothing
on screen. A silent exit is the worst possible failure: the user cannot tell a crash
from a mis-tap, and there is nothing in logcat to go on.
**Choice:** `main()` catches everything, shows a `StartupFailureApp` with the error
text, and `runZonedGuarded` logs uncaught asynchronous errors. On the native side
`TwindropApp` installs a default uncaught-exception handler and logs every startup
milestone under the `TwinDrop` logcat tag.
**Reason:** A failure that cannot be seen cannot be diagnosed. The native markers also
make `adb logcat -s TwinDrop` enough to tell how far the startup got.

## D-018 | 2026-10-21 | The app must render inside a Material
**Question:** Every text in the app was underlined in yellow and the composer
raised "No Material widget found. TextField widgets require a Material widget
ancestor". The theme and the type scale were provably clean, and the goldens were
clean, because the goldens wrapped the screens in a `Scaffold` while the app
does not.
**Choice:** `AppShell` renders a `Material` instead of a `ColoredBox`, the
`MaterialApp` wraps the navigator in one through its `builder`, and the type
scale sets `decoration: TextDecoration.none` on its base style.
**Reason:** A `Text` outside a `Material` inherits Flutter's fallback
`DefaultTextStyle` — yellow, double-underlined, 48 px monospace — because the
fallback exists to make the mistake visible. The fix belongs where the mistake
is: the shell that forgot the `Material`, plus a guard in the type scale so a
future widget outside a `Material` cannot silently underline the whole app.
`app/test/theme_material_test.dart` locks it in.

## D-019 | 2026-10-21 | Platform-channel calls happen on the main thread
**Question:** The Android app died ~40 ms after launch with
"Methods marked with @UiThread must be executed on the main thread".
**Choice:** `NetworkMonitor` posts every `ConnectivityManager` callback to the
main looper before it touches the platform channel.
**Reason:** Android delivers those callbacks on `ConnectivityThread`, and
Flutter's `MethodChannel.invokeMethod` must be called from the main thread. The
hop belongs inside `NetworkMonitor`, so every caller is safe by construction.

## D-020 | 2026-10-21 | The release tarball is byte-reproducible
**Question:** Two runs of `tool/package_release.sh` produced different checksums
for the same inputs.
**Choice:** The tarball is built with `--sort=name`, a fixed `--mtime`, a fixed
owner and `gzip -n`, and the `VERSION` file carries no timestamp.
**Reason:** A checksum that changes on every run cannot be used to verify
anything. The release assets are now reproducible from the same source.

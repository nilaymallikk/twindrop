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

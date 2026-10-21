# 11 — Roadmap (the work queue)

A phase is done only when its **exit criteria pass** and `BUILD_STATUS.md` has the evidence. Tick boxes as you go. Continue to the next phase without asking for approval.

## [ ] Phase 0 — Inspect & scaffold
Inspect repo/toolchain; preserve existing work. Create monorepo (`03`), `.gitignore`, `BUILD_STATUS.md`, `tool/doctor.sh`, icons generated from `design/`, lints.
**Exit:** `flutter run -d linux` shows a themed blank app; `flutter build apk --debug` works; `dart test` runs in `core`.

## [ ] Phase 1 — Core data layer
drift schema (`04`), HLC, validators (URL/category/size), `NotepadService`, `ChatService`, FTS, export, migrations, change log, quarantine.
**Exit:** unit tests for CRUD, tombstones, search, HLC skew, URL cases, validation; restart persistence test.

## [ ] Phase 2 — TLS identity & pinning spike (do early; it's the riskiest piece)
Generate self-signed ECDSA cert in pure Dart, serve HTTPS/WSS, client pin verifier, tests on **Linux and Android**.
**Exit:** correct pin connects; wrong pin refused; WebSocket works over pinned TLS on both platforms. If impossible → Appendix A of `05`, logged in `DECISIONS.md`.

## [ ] Phase 3 — Pairing
Pairing session/QR, strict parser, request/status/approve/reject, confirmation code, token issue/hash, revoke, rate-limit, manual pairing with short-fingerprint check, secure storage.
**Exit:** automated pairing flow incl. rejection, expiry, replay, lockout, revoke; token never logged (grep test).

## [ ] Phase 4 — Walking skeleton: messages both ways
`ConnectionManager`, `SyncEngine` (pull/notify/ack, backoff), delivery states, `tool/fake_peer.dart`; minimal chat UIs.
**Exit:** two-peer integration tests 2–5 pass; a real desktop and phone/emulator exchange a message.

## [ ] Phase 5 — Notepad + merge
Categories/notes CRUD, save-message-as-note, merge rules, conflict copies, tombstones, quarantine, resync.
**Exit:** integration tests 6–8, 11, 13 pass; both sides converge identically.

## [ ] Phase 6 — Full UI (both platforms)
Riverpod state, theme built from `design/tokens.json`, bundled IBM Plex fonts, Chat, Notepad, Settings, Diagnostics, pairing/onboarding, error copy from `02`, responsive layouts — all following `13-design-system.md`.
**Exit:** widget + golden tests green in dark and light; screenshots saved to `docs/screens/`; design acceptance checklist (`13` §11) ticked; no dead controls.

## [ ] Phase 7 — Android shell
Share receiver + panel, ShareIngest, intent-once guard, 10 s URL dedupe, keep-alive service with consent screen, boot receiver, battery helper, notifications, permissions flow.
**Exit:** adb share (cold+warm) → one Inbox note in ≤ 1.5 s (recorded); service survives screen-off; message arrives with app swiped away; offline share syncs once; reboot restart tested (emulator at minimum).

## [ ] Phase 8 — Linux shell
Tray + menu, popup, single instance + `--quick-send/--open/--quit/--hidden`, GNOME tray detection, close-to-tray rules, autostart, notifications, clipboard send, firewall hint.
**Exit:** manual checks on GNOME(+ext), KDE (and no-tray session) recorded; Quit frees the port; shortcut command works on Wayland.

## [ ] Phase 9 — Hardening
Security checklist (`08`) all ticked/BLOCKED; edge cases (IP change, sleep/wake, 100 KB text, emoji/RTL, 10k notes performance, duplicate-share dedupe); export; DB corruption backup path; log-redaction grep test.
**Exit:** all tests green; `docs/09` performance targets met or reported.

## [ ] Phase 10 — Packaging & release
`build_android.sh`, `build_linux.sh`/AppImage, `build_all.sh`, `INSTALL.md`, CI, About screen, checksums.
**Exit:** `./tool/build_all.sh` yields both artifacts; AppImage launched (normal + extract-and-run); release APK installed; share test passed; evidence in `BUILD_STATUS.md`.

## Backlog (v2+, do NOT build now)
Relay/off-LAN · file & image transfer · link previews · native global hotkey (X11) · Windows/macOS/iOS · multi-phone UI · browser extension · encrypted backup.

## Continuation loop
After each phase: format+analyze+smallest relevant tests → check against these docs → update `BUILD_STATUS.md` → commit `Phase <n>: <title>` → continue. Ask a question only when a decision is irreversible and unresolvable from the docs.

## When a package or platform issue appears
Read current docs; make the smallest reproducible test; try a maintained alternative; log it; never fake support with stubs; if hardware/GUI is unavailable, test what you can and mark the rest BLOCKED.

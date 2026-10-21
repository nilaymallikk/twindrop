# AGENTS.md — Rules for the Coding Agent

## Mission
Implement TwinDrop per `/docs`. Deliver working source plus a real Linux AppImage and Android APK. Not a scaffold, not mock screens, not a plan.

## Required reading order
`README.md` → `docs/00` … `docs/12` in numeric order.

## Operating rules
1. **Inspect first.** Check the repo and toolchain (`flutter doctor -v`). Preserve any existing user work; map it to these docs instead of overwriting.
2. **Work autonomously** through `docs/11-roadmap.md`, one phase at a time. Don't stop after a plan.
3. **Walking skeleton first:** DB → TLS-pinning spike → pairing → message both ways → notepad → share intent → tray → packaging. Polish UI only after the skeleton works end-to-end.
4. **Verify, never assume APIs.** Resolve current stable package versions, read their current docs, pin in lockfiles, log substitutions in `docs/DECISIONS.md`.
5. **Core logic lives in `packages/core`** (pure Dart, no Flutter imports) with unit tests. Platform code stays behind thin adapters.
6. **Security rules are not optional** (`docs/08`). Never weaken TLS validation to get past a problem. `badCertificateCallback` may only be used to compare the presented certificate's SHA-256 against the stored pin, never `=> true`.
7. **No dead controls.** Every visible button works or is disabled with an explanation.
8. **No TODO-only P0 features.** If blocked, document the blocker, continue with other work.
9. **Handle all states:** loading, empty, offline, error, success, at narrow phone width and normal desktop width.
10. **No cloud, accounts, analytics, telemetry, or third-party chat services.** Ever.
11. **Never log** message/note text, full URLs, tokens, pairing payloads, or keys.
12. **Follow the design system** (`docs/13-design-system.md`, `design/tokens.json`): dark-first, tokens only, no gradients/blur/glow/shadows/emoji, bundled fonts. Review your own screenshots against its anti-slop rules before closing Phase 6.
13. **Don't commit** keystores, certificates/keys, databases, pairing payloads, local config. Maintain `.gitignore`.

## Honesty rules (hard)
- Never claim a behavior is tested unless you actually ran that test. This includes: AppImage launch, GNOME tray, share-sheet, TLS pin rejection, foreground service, reconnect, real-device pairing.
- If a test can't run (no device, no display, no network), automate what you can, mark the manual test **BLOCKED** in `BUILD_STATUS.md`, and continue.
- A phase is done only when its **exit criteria pass** and `BUILD_STATUS.md` records the evidence (commands, results, artifact sizes, SHA-256).
- Never fake an artifact. If the APK or AppImage doesn't exist on disk, say so.

## `BUILD_STATUS.md` (create early, update every phase)
Use `BUILD_STATUS.template.md`. Must contain: phase, toolchain versions, implemented features, exact commands with pass/fail, test counts, artifact paths/bytes/SHA-256, end-to-end verification table, blockers, next task.

## Decision making
- Ambiguity → choose the simplest option that satisfies the product brief; record it in `docs/DECISIONS.md` (date, question, choice, reason). Don't ask.
- Ask the human only if a decision is both irreversible/destructive and unresolvable from the docs.
- Package abandoned/broken → replace with a maintained one (native Kotlin/C allowed for Android share intent and foreground service). Log it.

## Things only a human can do (report; don't fake)
- Test on a physical Android phone and real Linux desktop sessions (GNOME Wayland tray, KDE).
- Provide the Android release keystore and passwords.
- Approve final name/icon changes.

## Definition of done
All P0 requirements in `docs/01-requirements.md` are implemented or reported BLOCKED with evidence, and:
1. `dart analyze` / `flutter analyze` clean; `dart format` applied.
2. Unit tests (core ≥ 80% line coverage), widget tests, and the in-process two-peer integration test pass.
3. `./tool/build_all.sh` produces `dist/TwinDrop-x86_64.AppImage` and `dist/twindrop.apk` with `.sha256` files; the AppImage has actually been launched.
4. TLS pin mismatch is rejected (automated test). Revoked token is rejected (automated test).
5. Share URL → one Inbox note, syncs once (tested via adb intent at minimum).
6. Offline messages/shares sync exactly once after reconnect, even after process restart.
7. `docs/09` security checklist is fully ticked or items marked BLOCKED with reason.
8. Final report: artifacts, tested vs untested, exact run commands.

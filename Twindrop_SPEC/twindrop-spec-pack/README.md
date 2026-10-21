# TwinDrop — Agent Build Pack

Name: **TwinDrop** (app id `app.twindrop`).

**One line:** a private chat between *you on your phone* and *you on your desktop*, plus a shared categorized Notepad — over your home Wi-Fi, no cloud, no account.

**Deliverables:** `dist/TwinDrop-x86_64.AppImage` (Linux, top-bar tray icon) and `dist/twindrop.apk` (Android, share-sheet target), plus source, tests, and an honest `BUILD_STATUS.md`.

## Start here
1. Read `AGENTS.md` (rules for the agent).
2. Paste `AGENT_PROMPT.md` into your agent.
3. The agent reads `docs/` in the order below and works through `docs/11-roadmap.md`.

## Documents
| File | Purpose |
|---|---|
| `AGENTS.md` | Operating rules, honesty rules, definition of done |
| `AGENT_PROMPT.md` | Paste-ready kickoff prompt |
| `BUILD_STATUS.template.md` | Evidence log the agent maintains |
| `MANIFEST.md` | SHA-256 of every file in this pack |
| `docs/00-product-brief.md` | Problem, promise, principles, MVP boundaries, non-goals |
| `docs/01-requirements.md` | Numbered requirements (P0/P1/P2) with acceptance evidence |
| `docs/02-ux-flows.md` | Screens, flows, keyboard, exact error copy |
| `docs/03-architecture.md` | Stack, repo layout, lifecycle, error boundary |
| `docs/04-data-model.md` | Tables, change log, conflict policy, invariants |
| `docs/05-protocol.md` | Discovery, pairing, TLS pinning, replication, close codes |
| `docs/06-android.md` | Share panel, foreground service, permissions, APK |
| `docs/07-linux.md` | Tray, popup, quick-send shortcut, autostart, AppImage |
| `docs/08-security-privacy.md` | Threat model, controls, security checklist |
| `docs/09-testing-acceptance.md` | Unit/integration/widget tests, manual matrix, performance targets |
| `docs/10-build-release.md` | Commands, scripts, artifacts, signing, CI |
| `docs/11-roadmap.md` | Phases with checkboxes and exit criteria (the work queue) |
| `docs/12-decisions-risks.md` | ADRs, risks, limits users must understand |
| `docs/13-design-system.md` | Dark-first visual system, components, motion, copy voice, anti-slop rules |
| `design/` | `tokens.json`, `logo-mark.svg`, `tray-symbolic.svg` |

## Fixed decisions (don't re-debate; log deviations in `docs/DECISIONS.md`)
- **One Flutter/Dart codebase** for Android + Linux; pure-Dart `core` package holds data, sync, protocol.
- **Desktop = host** (TLS server). **Phone = client** (never listens). Both keep a **full local copy** (local-first), so everything works offline on both sides.
- **TLS with certificate pinning**, QR pairing + one-time token + **desktop approval + matching confirmation code**. Device tokens are revocable and stored hashed.
- **Never silently lose content:** concurrent edits keep both versions (conflict copy).
- **Share → Inbox in one tap** with a tiny confirmation panel (Undo / Change category / Also send as chat).
- **Background keep-alive on by default after explicit consent**, so desktop→phone messages arrive with the app closed.
- **Dark-first, restrained design** (off-white as contrast, hairlines, one accent, IBM Plex) — `docs/13-design-system.md`.
- LAN only. No cloud, analytics, or accounts.

## Truthfulness
This pack is a specification, not proof that anything works. The agent must build, test, and report exactly what was and wasn't verified (see `AGENTS.md`).

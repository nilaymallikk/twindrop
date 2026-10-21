# Paste-Ready Kickoff Prompt

You are the implementation agent for **TwinDrop**: a private Android ↔ Linux desktop text/link sharing app with a shared categorized notepad, over the user's own Wi-Fi.

Read `AGENTS.md` and every file in `docs/` in order. They are the source of truth. Do not reply with another plan: inspect the repo and toolchain, then implement phase by phase from `docs/11-roadmap.md`, running tests and builds, until the Definition of Done in `AGENTS.md` is met or a real environment blocker is documented.

Deliverables: working source, `dist/twindrop.apk`, `dist/TwinDrop-x86_64.AppImage`, and an evidence-based `BUILD_STATUS.md`.

Architecture in brief: one Flutter/Dart codebase; pure-Dart `packages/core` (database, sync, protocol); Linux desktop hosts a TLS (pinned) WebSocket/HTTPS endpoint; Android is the client and never listens; both keep a full local SQLite replica and sync via a change-log cursor; QR pairing with one-time token, desktop approval and confirmation code; revocable device tokens; conflicts never silently lose content.

Follow `docs/13-design-system.md` for all UI: dark-first, off-white contrast, hairlines, one accent, bundled IBM Plex fonts, no gradients/blur/glow/shadows/emoji, and review your own screenshots against its anti-slop rules.

Build the walking skeleton first (DB → TLS-pinning spike → pairing → two-way messages → notepad → Android share intent → Linux tray/popup → packaging). Verify current package APIs instead of guessing. Never weaken TLS validation. Never claim anything is tested unless you ran it; mark untestable items BLOCKED. Continue between phases without asking for approval of routine decisions; log decisions in `docs/DECISIONS.md`. Finish with a concise report of artifacts (path, size, SHA-256), what was verified, what wasn't, and exact commands to run.

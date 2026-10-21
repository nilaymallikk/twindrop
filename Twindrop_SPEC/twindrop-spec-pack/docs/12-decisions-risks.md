# 12 — Decisions, Risks, Limits

## ADRs
**ADR-001 One Flutter codebase.** Shared UI/logic for an agent-driven build; native code only behind adapters (share intent, foreground service, tray). *Trade-off:* OS integrations still need per-platform validation.
**ADR-002 Desktop hosts, phone dials; both hold full replicas.** No cloud cost/accounts; phone never listens (battery, security, NAT-free). Full replicas give offline create/edit everywhere. *Trade-off:* two devices must be online together to sync; merge logic is more complex than a single master — mitigated by deterministic rules and heavy tests.
**ADR-003 No cloud relay in v1.** Privacy and simplicity. *Trade-off:* no off-LAN delivery.
**ADR-004 TLS pinning + QR + desktop approval + confirmation code.** Same Wi-Fi isn't a boundary. *Trade-off:* cert generation/pinning needs early validation → Phase 2 spike with a documented fallback (Appendix A) so the agent can't stall.
**ADR-005 Change-log cursor sync + WebSocket notify.** Durable, recoverable, idempotent; events may be lost without data loss.
**ADR-006 Conflicts never lose content.** Concurrent edits keep both versions (conflict copy with deterministic id); delete-vs-edit restores. Preferred over silent last-write-wins.
**ADR-007 Share → Inbox with undo panel.** One tap for Instagram links; panel gives control without a blocking editor.
**ADR-008 Keep-alive service on by default after consent.** Delivering desktop→phone with the app closed is the core promise; honesty about OS limits in Settings.
**ADR-009 `--quick-send` instead of native global hotkeys.** Works on Wayland where app-level global shortcuts are blocked.
**ADR-010 Distro-agnostic.** Tested on Fedora GNOME, Ubuntu GNOME, KDE; AppImage built on an older base.

**ADR-011 Dark-first flat design, bundled fonts.** A quiet, tool-like look (hairlines, off-white contrast, one accent) fits a utility used many times a day and avoids the generic gradient/glass look. Fonts are bundled so the app makes zero external requests. *Trade-off:* custom theming work on top of Material; mitigated by tokens + golden tests.

## Limits users must understand
1. Same Wi-Fi isn't always enough (guest Wi-Fi, client isolation, VPN, VLAN, firewall).
2. The desktop app must be running for live sync; otherwise phone items wait locally.
3. Android may suspend or kill background work; force-stop prevents delivery. The keep-alive service helps but isn't a guarantee.
4. GNOME may hide tray icons without an AppIndicator extension; the app stays usable regardless.
5. AppImage portability depends on libc/FUSE/GTK libraries; hence the multi-distro tests.
6. Text and links only in v1; no files/images/video.
7. Local unpair on an offline phone doesn't revoke the token — revoke from the desktop.

## Risks & mitigations
| Risk | Mitigation |
|---|---|
| LAN device tries to read/write | Pin + approval + token + rate limits + server only when needed |
| Pinned TLS hard in Dart | Phase-2 spike first; Appendix A fallback; never `=> true` |
| Share handler fires twice / slow | Consume intent once; 10 s URL dedupe; native pre-queue fallback; measured ≤1.5 s |
| Lost data offline | Local commit before network; change log; idempotent apply |
| Sync resurrects deleted items | Tombstones; GC only after acks |
| Concurrent edits | Deterministic merge + conflict copies; tests on both sides |
| mDNS blocked | Last IP + manual address + Diagnostics |
| Tray missing on GNOME | Detection, guidance card, launcher, no hidden server |
| Android kills service | Consent + battery helper + honest messaging |
| AppImage missing libs | `ldd` inspection, multi-distro tests, extract-and-run test |
| Agent polishes UI before core works | Walking-skeleton ordering + exit criteria |
| Agent claims untested success | Honesty rules + evidence-only `BUILD_STATUS.md` |
| Log leaks | Redaction rules + grep test in CI |

## Future options (not commitments)
Multiple phones/desktops UI, files/images with size limits, optional encrypted backup, optional relay after an explicit privacy decision, link previews, iOS, browser extension, X11 native hotkey.

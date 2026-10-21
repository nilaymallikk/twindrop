# 09 — Testing & Acceptance

## Unit tests (`packages/core`, ≥ 80% line coverage)
- HLC ordering incl. ±10 min skew; counter rollover.
- URL extraction/validation (≥ 20 cases: Instagram reel with `igsh`, `javascript:`, `file:`, `data:`, `intent:`, relative, unicode, trailing punctuation); Instagram param cleaning.
- Category validator (empty, whitespace, 60-char max, case-insensitive duplicates, Inbox protection).
- Message/note size and Unicode/emoji/RTL handling.
- Merge rules (`04`): fast-forward, stale, concurrent edit (winner + deterministic conflict-copy id identical on both sides), meta LWW, delete-vs-edit restore, category-name collision, tombstone GC rules.
- Change-log: no echo to requester; `remote_seq` advances only after commit; replay guard.
- Validation vs quarantine; unknown schema → stop (not skip).
- Backoff: bounded 1→30 s with jitter; no tight loop.
- QR parser strictness; pairing token expiry, single use, rate-limit lockout; confirmation-code derivation (same on both sides).
- TLS: correct pin accepted, wrong pin rejected; cert generation/fingerprint stable across restarts.
- Token hashing/revocation; auth middleware (401 vs 403).
- Delivery-state machine: queued → sent → delivered only via ack.

## Design tests
- Golden tests (dark + light): chat bubble (sent/received/queued/delivered), note card (normal/pinned/conflict copy), status indicator (all states), share panel, approval code screen.
- CI greps: no hex literals outside `design/` tokens file; no `BoxShadow`, `LinearGradient`, `RadialGradient`, `BackdropFilter`; no emoji code points in `lib/` strings; no `google_fonts` network usage.
- Contrast check script over `design/tokens.json` (all text pairs ≥ 4.5:1) run in CI.
- Text scale 200% and 320 dp width render without overflow.

## Integration (in-process, two peers over loopback TLS, in-memory DBs)
1. Pair (approval + code) → connect → snapshot sync.
2. Chat both directions; exactly-once; states correct.
3. Disconnect phone; send 5 from desktop and 3 shares from phone; reconnect → all arrive once, in order; `Delivered` only after ack.
4. Process kill mid-sync → restart → no loss, no duplicates.
5. Drop `notify` events → cursor pull recovers.
6. Concurrent edit of same note on both sides while offline → identical final state on both + one conflict copy.
7. Delete on A vs edit on B → restored with `restored=1`.
8. Category delete moves notes to Inbox; concurrent category creation with same name merges.
9. Revoke → socket closed 4403; old token 403; re-pair works.
10. Wrong pin → connection refused with `certificate_mismatch`.
11. Quarantine: hand-crafted invalid remote change lands in quarantine and is visible.
12. Migration: open DB from previous schema fixture → data preserved.
13. Resync after DB restore.

## Widget tests
Empty/loading/offline/error/connected states; chat bubble states; save-to-notepad sheet; category CRUD + Inbox protection; note edit/move/pin/delete+undo; conflict-copy badge actions; pairing screens (QR parse errors, code display); share panel (Undo, Change category, Also send as chat); no dead/decorative buttons.

## Manual end-to-end matrix (record environment: emulator vs real phone; distro/version)
| Case | Steps | Expected |
|---|---|---|
| Pair | Pair session → scan → codes match → approve | Both connected; QR no longer works |
| Code mismatch | Tamper code in a test harness | Pairing aborts |
| Desktop → phone | Type `SN-001` in popup, Enter | Phone shows exactly one; ticks truthful |
| Phone → desktop | Send `SN-002` | Desktop shows exactly one |
| App closed | Swipe app away, service on, send from desktop | Heads-up notification; opens to message |
| Share cold start | Kill app; Instagram/browser → Share → TwinDrop | Panel "Saved to Inbox" ≤ 1.5 s; one note |
| Share warm start | App open; share URL | One note; state retained |
| Same URL twice | Share same URL twice within 10 s | One item |
| Share offline | Wi-Fi off → share → Wi-Fi on | "Will sync" then exactly one note on desktop |
| Undo / Change category / Also send | Use each on panel | Applies and syncs |
| Unsupported share | Share an image | "text and links only", no crash |
| Desktop off | Quit desktop; queue phone message | Waiting state; syncs on return |
| Close to tray | Close window (tray present) | Host keeps serving; menu reopens |
| No tray | Disable AppIndicator (GNOME) | Guidance card; closing exits; no hidden server |
| Quit | Tray → Quit | Port freed; phone shows offline |
| Quick-send shortcut | Bind OS shortcut to `--quick-send` | Popup opens in running instance (GNOME Wayland + KDE) |
| Autostart | Enable; log out/in | App starts hidden in tray; stale-path repair works |
| IP change | Renew DHCP lease | Reconnects via mDNS/last IP/manual; pin never bypassed |
| mDNS blocked | Disable mDNS | Manual address works; Diagnostics explains |
| Category sync | Create `Research`, move note there (offline then online) | Same on both |
| Delete category | Delete custom category | Notes in Inbox; content retained |
| Conflict | Edit same note offline on both | One winner + "Conflict copy" |
| Revoke | Revoke on desktop | Phone shows "removed"; token dead |
| Pin mismatch | Replace desktop cert | Phone refuses, offers re-pair |
| Reboot phone | Reboot | Service restarts (if enabled) |
| AppImage | Run built AppImage on Fedora GNOME, Ubuntu GNOME, KDE | UI, DB, TLS, tray/fallback, pairing, messaging OK |
| No FUSE | `--appimage-extract-and-run` | Launches |

## Environment notes
Use a private home LAN (not guest Wi-Fi). Same SSID ≠ reachable: AP client isolation, VPNs, VLANs, firewalls can block — the app must explain this, not claim pairing is broken. Emulator networking differs from a real phone. Test the **produced** AppImage and release APK, not only debug runs.

## Performance targets
Desktop→phone visible < 1 s (healthy LAN); share cold start → "Saved" ≤ 1.5 s; FTS search < 100 ms at 10k notes; lists virtualized (10k items scroll smoothly); UI never blocks during sync/retry.

## Release acceptance
- [ ] All P0 IDs implemented or BLOCKED with evidence
- [ ] `flutter analyze` / `dart analyze` clean; tests green; coverage target met
- [ ] APK built, installed (emulator or device), share test run
- [ ] AppImage built and launched at least once; FUSE-less launch tested
- [ ] Security checklist (`08`) ticked
- [ ] Design acceptance checklist (`13` §11) ticked
- [ ] `BUILD_STATUS.md` complete: commands, sizes, SHA-256, verified vs unverified, blockers

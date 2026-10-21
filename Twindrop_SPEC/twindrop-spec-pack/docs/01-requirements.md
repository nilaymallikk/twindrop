# 01 — Requirements

Priorities: **P0** = required for first usable release. **P1** = build after P0 if it doesn't block P0. **P2** = future.
Every P0 must be implemented or reported BLOCKED with evidence (`AGENTS.md`).

## Pairing & connectivity
| ID | Pri | Requirement | Acceptance evidence |
|---|---|---|---|
| PAIR-001 | P0 | Desktop starts a 5-minute pairing session and shows a QR (plus manual details). | QR holds hosts, port, TLS SHA-256 fingerprint, one-time token, expiry, protocol version. No long-lived secret inside. |
| PAIR-002 | P0 | Phone scans the QR; camera permission requested only at scan time; malformed/expired QR rejected. | Unit tests for strict QR parser; widget test for error states. |
| PAIR-003 | P0 | Desktop shows an approval prompt (device name, platform) with a **4-digit confirmation code** that must match the code on the phone. | Integration test: no API access before approval; code derivation test. |
| PAIR-004 | P0 | Device token stored in Android Keystore-backed secure storage; desktop stores only a hash; tokens are revocable. | Test: revoked token gets 403 and live socket closed (code 4403). |
| PAIR-005 | P0 | Pairing works with no cloud service. | Network audit: only paired-host traffic. |
| PAIR-006 | P0 | Visible connection states: Connected, Searching, Offline, Syncing, Pairing, Unpaired/Removed. | State-machine unit tests + widget tests. |
| PAIR-007 | P0 | Reconnect path: last-known IP → mDNS → manual address, with backoff. | Test with mDNS disabled still reconnects via last IP/manual. |
| PAIR-008 | P0 | Manual pairing when camera unavailable: type `IP:port` + pairing code; phone shows the cert's short fingerprint code; user confirms it matches the desktop's; then pin is stored. | Test: wrong short code → refuse; pin never accepted silently. |
| PAIR-009 | P0 | Desktop can revoke any device; phone can unpair; re-pair works. | Manual + automated test. |
| PAIR-010 | P0 | Pairing attempts are rate-limited (5 failures/60 s → 60 s lockout). | Unit test. |
| PAIR-011 | P1 | UI for multiple desktops (data model already supports N peers). | Manual. |

## Chat
| ID | Pri | Requirement | Acceptance evidence |
|---|---|---|---|
| MSG-001 | P0 | Desktop sends text from popup and full window. | Appears on phone once. |
| MSG-002 | P0 | Phone sends text from composer. | Appears on desktop once. |
| MSG-003 | P0 | History shows direction, device label, time, state, in consistent order on both. | Widget + integration tests. |
| MSG-004 | P0 | Retries/reconnects never duplicate messages. | Test: replay same change twice → one row. |
| MSG-005 | P0 | Message persisted locally **before** any network attempt. | Kill-process test keeps the message. |
| MSG-006 | P0 | States: Queued → Sent → Delivered (peer acknowledged applying it). Never show Delivered without ack. | State tests. |
| MSG-007 | P0 | Message actions: Copy, Delete, Save to Notepad, Select. | Widget test. |
| MSG-008 | P0 | URLs render as link chips; open system browser only on explicit tap. | Widget test. |
| MSG-009 | P0 | Background keep-alive service so desktop→phone arrives with app closed (consent at onboarding, default ON, user can disable). | adb test with app swiped away. |
| MSG-010 | P1 | Incoming-message notifications on both platforms (toggle). | Manual. |

## Notepad
| ID | Pri | Requirement | Acceptance evidence |
|---|---|---|---|
| NOTE-001 | P0 | Create, rename, reorder, delete categories; deleting moves notes to Inbox (never cascades). | Tests incl. concurrent delete. |
| NOTE-002 | P0 | `Inbox` exists with fixed id `inbox` on both devices; cannot be deleted. | Test. |
| NOTE-003 | P0 | Text notes and link notes (URL, title, source app, timestamp). | Persistence test. |
| NOTE-004 | P0 | Save any chat message as a note with category picker (links back to source). | Widget test. |
| NOTE-005 | P0 | Move, edit title/text, pin, delete with Undo. | Widget + sync tests. |
| NOTE-006 | P0 | Search (title, text, URL) + category filter; < 100 ms at 10k notes. | Performance test. |
| NOTE-007 | P0 | Create/edit/delete **offline on either device**; merged deterministically on reconnect. | Integration test. |
| NOTE-008 | P0 | Concurrent edits never lose content: loser kept as a "Conflict copy". | Integration test (see `04`). |
| NOTE-009 | P0 | Export Notepad as Markdown and JSON. | Test file contents. |
| NOTE-010 | P1 | Archive; tags. | Manual. |

## Android share target
| ID | Pri | Requirement | Acceptance evidence |
|---|---|---|---|
| SHARE-001 | P0 | App appears in the Share sheet for `text/plain` (URLs and text). | adb intent + real device. |
| SHARE-002 | P0 | Shared item is persisted locally before any network call; works with Wi-Fi off. | Airplane-mode test. |
| SHARE-003 | P0 | Default action: auto-save to Inbox with a compact confirmation panel: **Undo · Change category · Also send as chat**. Auto-dismiss ~4 s. | Widget/instrumentation test. |
| SHARE-004 | P0 | Setting for default action: Save to Notepad / Send as chat / Ask each time. | Test. |
| SHARE-005 | P0 | Status text is truthful ("Saved to Inbox" vs "Saved — will sync when desktop is online"). | Test. |
| SHARE-006 | P0 | Cold-start and warm-start both work; one insert per share intent. | adb tests both modes. |
| SHARE-007 | P0 | Same URL shared twice within 10 s → one item (intent-level guard); later re-shares are allowed. | Unit test. |
| SHARE-008 | P0 | Unsupported payload (image/file) → clear message, no crash. | Test. |
| SHARE-009 | P0 | Cold start to "Saved" ≤ 1.5 s on a mid-range phone, else native pre-queue fallback (`06`). | Timed run recorded. |
| SHARE-010 | P1 | `ACTION_SEND_MULTIPLE` text. | Manual. |

## Linux desktop
| ID | Pri | Requirement | Acceptance evidence |
|---|---|---|---|
| LNX-001 | P0 | Full window with Chat, Notepad, Settings. | Widget tests. |
| LNX-002 | P0 | Tray icon: left-click toggles popup; menu: Open, Send clipboard, status, Pause/Resume, Quit. | Manual on GNOME+ext, KDE. |
| LNX-003 | P0 | Popup: Enter sends, Shift+Enter newline, Esc hides, Ctrl+S saves to Notepad, Ctrl+Shift+V sends clipboard. | Widget tests. |
| LNX-004 | P0 | Close-to-tray **only if a tray is confirmed available**; otherwise closing exits normally (no hidden server). | Test on session without tray host. |
| LNX-005 | P0 | Server keeps running while hidden; Quit stops it and frees the port. | Manual + test. |
| LNX-006 | P0 | GNOME without AppIndicator: detect and show guidance; app stays usable from launcher. | Manual. |
| LNX-007 | P0 | `--quick-send` flag opens the popup in the running instance, so the user can bind **any** desktop keyboard shortcut (works on Wayland). Settings shows the exact command with Copy. | Manual. |
| LNX-008 | P0 | Single instance; second launch focuses first. | Test. |
| LNX-009 | P0 | Autostart offered after first pairing (per-user `.desktop`, no root, stale-path repair). | Test. |
| LNX-010 | P0 | Desktop notifications for incoming items when popup hidden (toggle). | Manual. |
| LNX-011 | P0 | Real AppImage artifact, launched and verified; no data inside the AppImage. | `BUILD_STATUS` evidence. |
| LNX-012 | P1 | Native global shortcut on X11. | Manual. |

## Sync & data
| ID | Pri | Requirement | Acceptance evidence |
|---|---|---|---|
| SYNC-001 | P0 | Local-first: each device has a full SQLite replica. | Test. |
| SYNC-002 | P0 | Change-log cursor pull + live `notify`; WebSocket events are optimization, cursor sync is authoritative. | Dropped-event recovery test. |
| SYNC-003 | P0 | Applying a change is idempotent; replay = no-op. | Test. |
| SYNC-004 | P0 | Tombstones prevent resurrection; GC only after peers acked. | Test. |
| SYNC-005 | P0 | Deterministic merge incl. deterministic conflict-copy IDs. | Two-peer test, both sides identical. |
| SYNC-006 | P0 | Invalid remote changes go to a visible **quarantine**, not silent drop. | Test. |
| SYNC-007 | P0 | Unknown protocol/schema version → stop with "Update the app" error; never skip-and-advance. | Test. |
| SYNC-008 | P0 | Retries use exponential backoff with jitter, bounded (1→30 s); no tight loops. | Unit test. |
| SYNC-009 | P0 | Cursor invalid / DB restored → safe full resync path. | Test. |
| SYNC-010 | P0 | Clock-skew tolerant ordering (hybrid logical clock). | Test with ±10 min skew. |

## Security & privacy (details in `08`)
| ID | Pri | Requirement |
|---|---|---|
| SEC-001 | P0 | HTTPS/WSS only, pinned self-signed cert; no plaintext fallback. |
| SEC-002 | P0 | Every non-pairing endpoint needs a valid, unrevoked device token. |
| SEC-003 | P0 | Pairing token: one-time, 5 min, random, rate-limited, generic failures. |
| SEC-004 | P0 | Input validation both sides: size limits, URL scheme allow-list (`http`, `https`), UTF-8. |
| SEC-005 | P0 | No secrets or content in logs; secrets in OS secure storage; key files 0600. |
| SEC-006 | P0 | No analytics, telemetry, cloud calls. |
| SEC-007 | P0 | Server runs only when a pairing session is open or ≥1 device is paired; stops on Quit/Pause. |

## Settings & reliability
| ID | Pri | Requirement |
|---|---|---|
| SET-001 | P0 | Show peer name, reachability, last sync, queue count, server state, IP:port. |
| SET-002 | P0 | Retry now, unpair/revoke, export, clear data (with confirmation). |
| SET-003 | P0 | Diagnostics screen with actionable network help (same Wi-Fi? isolation? firewall? VPN?). |
| SET-004 | P0 | Corrupt API data handled safely; non-sensitive error; app stays alive. |
| SET-005 | P0 | DB migrations tested on prior schema; backup before any destructive recovery. |

## Design (details in `13-design-system.md`)
| ID | Pri | Requirement | Acceptance evidence |
|---|---|---|---|
| DES-001 | P0 | Dark theme is the default; Light and System available; every screen works in both. | Screenshots + golden tests in both themes. |
| DES-002 | P0 | All colors, radii, spacing and fonts come from design tokens; no hard-coded hex or font names in widgets. | CI grep. |
| DES-003 | P0 | IBM Plex Sans/Mono bundled as assets; no runtime font or network fetch. | Offline run + asset check. |
| DES-004 | P0 | No gradients, blur, glow, drop shadows, emoji in UI, or stock illustrations. | CI grep + screenshot review. |
| DES-005 | P0 | One accent color used only where allowed; status never relies on color alone. | Review checklist. |
| DES-006 | P0 | WCAG AA contrast for all text in both themes. | Contrast check recorded. |
| DES-007 | P0 | Logo, app icon and symbolic tray icon (light/dark, offline, unread states) generated from `design/`. | Artifacts present in APK/AppImage. |
| DES-008 | P0 | Motion follows spec (120/180 ms, no springs) and respects reduce-motion. | Manual + widget test. |
| DES-009 | P1 | Optional true-black theme for OLED phones. | Manual. |

## Non-functional
- **Latency:** < 1 s visible delivery on healthy LAN when both online (target, not guarantee).
- **Durability:** local transactional write before network; WAL mode.
- **Performance:** virtualized lists; 10k notes browse smooth; FTS search < 100 ms.
- **Accessibility:** 48 dp targets, semantic labels, AA contrast, font scaling to 200%, keyboard navigation and visible focus rings on desktop, reduce-motion respected.
- **Portability:** test the packaged AppImage, not only `flutter run`; state under XDG dirs, never inside the AppImage mount.
- **Battery:** keep-alive uses one idle socket with 15 s ping; no wakelock when screen off.

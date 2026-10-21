# 02 — UX & Flows

## Design principles
Speed over features (open → type → sent < 2 s). Familiar messenger feel + notepad. **Dark-first** (Light and System also supported) with off-white as the contrast color, hairline borders, one accent, IBM Plex type — full rules in `13-design-system.md`, which overrides any visual detail in this file. Same widgets on phone and desktop; desktop adds sidebar + shortcuts. Plain copy; every error says what to do next.

## Navigation
- **Phone:** bottom nav **Chat · Notepad · Settings**. Unpaired → pairing-first home ("Connect to your desktop"); never show a fake active chat.
- **Desktop main window:** left sidebar **Chat · Notepad · Settings**, status chip, responsive width.
- **Desktop popup (tray):** 380×520, chat view + input; header has status dot and "Open full app".

## Screens
1. **Pairing** — Desktop: QR + manual details + "Waiting for phone…" → approval card (name, platform, **confirmation code**) → "Connected". Phone: scan QR / "Enter manually" → shows same confirmation code → "Waiting for approval on your desktop" → permission steps (notifications, background consent, battery) with Skip.
2. **Chat** — bubbles (mine right, other device left), device label + time, state icons (clock = queued, single check = sent, double check = delivered), link chips, date separators, jump-to-latest, offline banner with Retry/Troubleshoot. Long-press/right-click: Copy · Save to Notepad · Delete · Select.
3. **Notepad** — Phone: category chips + FAB. Desktop: category sidebar (drag reorder, right-click rename/delete, + New). Cards: title, 3-line text, link chip, meta ("from Pixel 8 · 2h ago"), pin. Detail/edit: title, text, category. Search bar. Sort: pinned, then newest. Delete = tombstone + 5 s Undo. "Conflict copy" badge on conflict notes with "Keep this / Merge manually / Delete".
4. **Save-to-Notepad sheet** — categories (last used preselected), + New category, optional title, Save.
5. **Android share panel** — translucent bottom card over the source app (never the full app): check icon + "Saved to Inbox" + **Change category · Also send as chat · Undo**; offline line "Will sync when desktop is online". Auto-dismiss 4 s; returns user to the source app.
6. **Settings** — Device (name, status, IP:port, last seen, queue count, revoke/unpair) · Sharing (default share action, clean Instagram tracking params) · Background (keep-alive toggle + consent text, battery helper) · Notifications · Appearance · Desktop (start at login, hide on blur, quick-send shortcut command + Copy, tray status) · Data (export MD/JSON, quarantine viewer, clear data) · About.
7. **Diagnostics** — own IPs, peer last IP:port, mDNS result, TLS pin state, last handshake error, **Test connection**, tips (same Wi-Fi, guest/AP isolation, firewall port, VPN), manual address entry, firewall hint command (shown, never run).

## Flows
**A. First pairing.** Desktop → Pair a phone → 5-min session with QR → phone scans → phone verifies pin and sends request → both show the same 4-digit code → desktop user taps Approve → phone receives token once, stores it in secure storage, syncs snapshot → both show connected. Session/QR single-use.
Failure states: invalid/expired QR · no route · port blocked · pin mismatch · approval denied/expired · code mismatch (user cancels) · duplicate device · host IP changed. Each offers Retry / Rescan / Re-pair; none bypass TLS.

**B. Desktop → phone.** Tray click → popup → type → Enter → stored locally → sent over socket → phone shows it; sender sees Queued → Sent → Delivered only as acks arrive. Phone asleep with service on: heads-up notification.

**C. Phone → desktop.** Composer → Send → local write first → push; Queued if offline, auto-send on reconnect.

**D. Instagram/Reels link.** Share → TwinDrop → local save to Inbox in ≤1.5 s → panel (Undo/Change category/Also send as chat) → syncs when desktop online. Tapping the saved URL later opens the browser; the app never downloads media.

**E. Save message as note.** Item menu → Save to Notepad → category pick → creates a **new note** (copy) linked to the message; deleting the message doesn't delete the note.

**F. Categories.** Create/rename/reorder anywhere (works offline). Delete → confirm → its notes move to Inbox.

**G. Reconnect.** Network loss → status Searching; outbox keeps everything; backoff 1→30 s with jitter plus immediate retry on Wi-Fi change/foreground/resume; on connect: authenticate, pull both ways, ack, show "Synced".

**H. Desktop quit.** Close window → hides to tray only when tray confirmed; **Quit** stops server and frees port. No tray → close exits normally.

**I. Revoke.** Desktop Settings → Devices → Remove phone → socket closed; phone shows "This phone was removed from the desktop" and offers re-pair; its local data remains until user clears it.

## Keyboard (desktop)
`Enter` send · `Shift+Enter` newline · `Esc` hide popup · `Ctrl+S` save to Notepad · `Ctrl+Shift+V` send clipboard · `Ctrl+N` open Notepad · `Ctrl+F` search · `Ctrl+,` settings. Custom OS shortcut → `TwinDrop.AppImage --quick-send`.

## Exact error copy (use these; keep tone)
| Situation | Message | Actions |
|---|---|---|
| Desktop not found | "Can't reach your desktop. Is it on the same Wi-Fi and running TwinDrop?" | Retry · Troubleshoot |
| Wi-Fi isolation suspected | "Your Wi-Fi may be blocking device-to-device traffic (guest network or client isolation)." | Troubleshoot |
| Pin mismatch | "This desktop's security identity changed. Pair again only if you made that change." | Pair again · Cancel |
| QR expired | "That code expired. Create a new one on your desktop." | Rescan |
| Approval denied | "Your desktop declined this phone." | Try again |
| Code mismatch | "The codes don't match. Cancel and start over." | Cancel |
| Removed | "This phone was removed from the desktop." | Pair again |
| Update needed | "Your other device uses a newer version. Update TwinDrop on both." | — |
| Unsupported share | "TwinDrop saves text and links only." | OK |
| Storage error | "Couldn't save. Free some space and try again — nothing was sent." | Retry |
| Tray unavailable | "Your desktop isn't showing tray icons. TwinDrop will stay in a normal window." | How to enable |
| Port in use | "Port 47321 is busy. Using <new port> instead." | — |
| Notifications denied | "Notifications are off, so you won't see messages while the app is closed." | Open settings |
| Queue near limit | "Lots of items are waiting to sync. Connect to your desktop soon." | Troubleshoot |

## Accessibility & assets
48 dp tap targets, semantic labels on icon buttons, AA contrast, honors font scale, focus order on desktop. App icon, tray icon and states come from `design/logo-mark.svg` and `design/tray-symbolic.svg` (see `13-design-system.md` §5); generate the Android adaptive icon and Linux 16–512 px PNGs from them.

# 00 — Product Brief

## Problem
The owner constantly moves small things (text, links, snippets, Instagram videos to watch later) between **their own Android phone and Linux desktop**. Today: copy → open WhatsApp/Telegram "saved messages" → paste → switch device → copy again. Too many steps, and it clutters personal chats.

## Promise
**Share once. Find it on either device.** It feels like messaging yourself: the sender is you on one device, the recipient is you on the other. Beside the chat there is a shared **Notepad** with your own **categories** (Inbox, Watch Later, Research…).

## Primary user
One person, one Android phone, one (or more) Linux desktops, usually on the same private Wi-Fi. Desktop environment is not assumed: **GNOME (Wayland/X11), KDE, Xfce, Cinnamon** are all supported targets; GNOME's tray caveat is handled explicitly (`docs/07`).

## Jobs to be done
1. Click the top-bar icon on desktop → type → Enter → it's on the phone.
2. Send text from phone to desktop without a third-party messenger.
3. In Instagram/any app: Share → TwinDrop → saved. One tap, no form.
4. Open either app later: same chat history, notes, categories.
5. Capture now, organize later, search anytime.
6. Work with no cloud, no account, no subscription.

## Principles
- **One-tap capture.** A shared URL never opens an editor.
- **Don't lose anything.** Persist locally before any network call; conflicts keep both versions.
- **Private by default.** LAN only; nothing leaves your network; no telemetry.
- **Truthful status.** Distinguish Queued / Sent / Delivered; never claim Delivered without an acknowledgement.
- **Boring and reliable.** Idempotent operations, explicit conflict rules, bounded retries.
- **Native entry points.** Android share sheet; desktop tray + keyboard-first popup + optional custom shortcut.
- **Not a messenger.** These are app-internal records, not SMS/WhatsApp/Telegram messages.

## MVP scope (in)
Android APK + Linux AppImage; pairing (QR, approval, confirmation code); chat history both ways; notepad with categories, search, pin, move, edit, delete+undo; Android share target with confirmation panel; offline create/edit on both devices with deterministic merge; background keep-alive service (consented); tray icon + popup + clipboard send; autostart; export; diagnostics screen.

## Non-goals (do NOT build in v1)
Cloud/relay/off-LAN sync, accounts, iOS/macOS/Windows, file/image/video transfer (text and links only; protocol stays extensible), automatic clipboard monitoring, rich text/markdown rendering, link scraping/preview fetching, downloading Instagram/YouTube media, multi-user sharing/collaboration, public links.

## Success criteria
1. Instagram → Share → TwinDrop: saved in 1 tap, ≤ 1.5 s from cold start to "Saved".
2. Desktop tray click → type → Enter → visible on phone < 1 s on healthy Wi-Fi.
3. Nothing lost when either device is offline; no duplicates after retry.
4. Setup < 1 minute: install both, scan QR, approve, done.
5. No traffic to any cloud endpoint, verified.

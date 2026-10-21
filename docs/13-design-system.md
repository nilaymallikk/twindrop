# 13 — Design System

**Direction: dark-first, with white as the contrast color.** Quiet, dense, tool-like — closer to a terminal-meets-notebook than to a "friendly AI app". The product is two surfaces talking to each other, so the interface is flat, hairline-ruled and typographic. One accent color, used rarely.

Source of truth for values: `design/tokens.json`. Logo: `design/logo-mark.svg`. Tray icon: `design/tray-symbolic.svg`.

## 1. Themes
- **Dark (default)** — near-black warm neutral with off-white "paper" as the strong contrast color.
- **Light** — warm paper background, white surfaces, near-black ink.
- **System** — follows OS. Settings → Appearance: Dark · Light · System. First run = Dark.
- P1: **Black** (true-black OLED variant for the phone).

### Palette
| Token | Dark | Light | Use |
|---|---|---|---|
| `bg` | `#0E0F11` | `#F4F3EE` | App background |
| `surface` | `#16181B` | `#FFFFFF` | Panels, input, sheets |
| `raised` | `#1D2024` | `#EDECE6` | Hover, received bubble, popovers |
| `hairline` | `#2A2E33` | `#D8D6CE` | All borders and dividers (1 px) |
| `text` | `#ECEBE6` | `#131417` | Primary text |
| `textSecondary` | `#B4B6BB` | `#3C4047` | Body copy in cards |
| `muted` | `#8E9198` | `#5C6068` | Meta, hints, timestamps |
| `paper` / `onPaper` | `#ECEBE6` / `#0E0F11` | `#131417` / `#F4F3EE` | **Inverted** elements: my bubbles, secondary buttons, selected tab |
| `accent` / `onAccent` | `#FF6B3D` / `#0E0F11` | `#B33F12` / `#FFFFFF` | Send button, focus ring, unread dot, selection |
| `ok` / `warn` / `error` | `#5FBF8F` / `#E3A93B` / `#F2705F` | `#1E7A4F` / `#8A5A00` / `#B3261E` | Status only, always with a text label |

Contrast (checked): dark text on bg 16.1:1, muted on bg 6.1:1, accent on bg 6.8:1; light text on bg 16.6:1, muted on bg 5.7:1, accent on bg 5.2:1. All text meets WCAG AA. Re-check if any value changes.

### Accent rules
One accent only. Allowed: primary send/confirm button fill, focus ring, unread dot, text selection, link hover. **Not allowed:** gradients, large fills, decorative borders, icons in colored circles, colored left-edge "stripe" on cards.

## 2. Typography
- **UI:** IBM Plex Sans (400/500/600). **Meta, URLs, device names, timestamps, counts:** IBM Plex Mono (400).
- Both are OFL-licensed; **bundle them as assets** with license files. Never fetch fonts at runtime (no `google_fonts` network fetching — TwinDrop makes no external requests).
- Scale (px/line): meta 12/16 mono · secondary 13/18 · body 14/20 desktop, 15/22 phone · title 17/24 semibold · screen title 22/28 semibold. Titles tracking −0.01 em. Sentence case everywhere; no all-caps labels except tiny mono tags.

## 3. Shape, spacing, depth
- Radii: 4 / 6 / 10 / 14 (`xs/sm/md/lg`). Inputs and cards 10, buttons 8, chips 6, bottom sheet top corners 14. **Not pill-shaped everything.**
- Spacing on a 4 pt grid: 4, 8, 12, 16, 20, 24, 32, 48. Phone side padding 16. Desktop chat column max 720 px.
- Density: desktop compact (list rows 36–44 px), phone comfortable (48 dp targets).
- **Depth = 1 px hairline borders and a step in surface color. No shadows, no blur, no glass, no glow.** Dialogs/popovers: `raised` surface + hairline + 60% black scrim (no backdrop blur).

## 4. Iconography
Outline icons, consistent 1.5 px stroke (20 px desktop, 24 px phone nav), Lucide-style. Verify a maintained Flutter package (e.g. `lucide_icons_flutter`) or bundle the needed SVGs. **No emoji anywhere in the UI**, no mixed icon sets, no sparkle/"magic" icons.

## 5. Logo & app icon
Mark: two overlapping rounded squares — back one outlined, front one solid — with a small accent square ("the drop") in the front square's lower-right corner. Android adaptive icon: mark on `#0E0F11` background layer. Linux icon: same on `#0E0F11` rounded tile, sizes 16–512. **Tray icon:** symbolic, single-color (black on light panels, white on dark; supply both). States: connected (as drawn) · offline (outline square dashed) · unread (adds a 5 px dot, top-right). Status must not rely on color alone.

## 6. Components
**Chat**
- My messages: `paper` bubble with `onPaper` text, radius 10 (3 px on the corner nearest the sender). Other device: `raised` bubble + 1 px hairline, `text` color. Max width 78%.
- Under each bubble: device name and time in mono 12 `muted` (e.g. `Desktop · 14:02`). Delivery icons 14 px: clock (queued), single check (sent), double check (delivered, `text` color).
- Links inside bubbles: mono domain chip with 1 px border, no favicon (no network). Date separators: mono, centered, hairline either side.
- Input: `surface`, 1 px hairline, radius 10; focus = 1 px `accent` border (no glow). Send button: `accent` fill, `onAccent` icon, radius 8, disabled until text exists. Hint line (desktop popup): mono 12 muted `Enter to send · Shift+Enter for new line`.

**Notepad**
- Category: phone = horizontal text tabs with a 2 px `paper` underline for the selected one; desktop = sidebar list with a mono count at the right and a `raised` background for the selected row. No chips-with-icons.
- Note card: `surface`, 1 px hairline, radius 10, no shadow; hover `raised`. Title 15/600; body 14 `textSecondary`, 3 lines; meta row mono 12 `muted` (`Phone · 2h ago`); link shown as mono domain. Pinned = small pin icon at top right (not a stripe, not a color fill). Conflict copy = small mono tag `conflict copy` with 1 px border.

**Status** — an 8 px dot plus a text label (`Connected`, `Searching`, `Offline`, `Syncing`). `ok`/`warn` color for the dot only; offline = hollow ring in `muted`. No pulsing or looping animation.

**Share panel (Android)** — bottom sheet, `raised`, top radius 14, 1 px top hairline, no drag handle. Line icon (check) + **Saved to Inbox** (16/600). Below: three plain text buttons `Change category`, `Also send as chat`, `Undo`. A 2 px `accent` countdown hairline runs along the bottom edge for the 4 s dismiss. Offline variant: "Saved. Will sync when your desktop is online."

**Buttons** — Primary: `accent` fill (send/confirm only). Secondary: **inverted paper** (`paper` fill, `onPaper` text). Tertiary: text only. All radius 8, 36 px desktop / 48 dp phone height. Destructive actions use `error` text, confirm in a dialog.

**Popup (tray)** — 380×520, `bg`, 1 px hairline border, radius 12 (where the compositor supports it). 40 px header (status dot + label, "Open" icon button), message list, input. Keyboard-first: visible focus rings, no hover-only controls.

**QR** — always dark-on-light tile (`#F4F3EE` with 16 px quiet zone) even in dark theme, so it scans reliably. Approval code shown in large mono digits (32 px, tracking +0.12 em).

**Onboarding** — three numbered plain steps in mono (`01 02 03`); no carousel, no illustration. **Empty states** — one left-aligned sentence, one action, the 24 px logo mark in `muted`. No cartoon illustrations.

## 7. Motion
120 ms ease-out for state changes, 180 ms for sheets/popups. New message: 140 ms fade + 4 px rise. No springs, bounce, parallax, shimmer skeletons (use a plain placeholder line), confetti, or typing indicators. Honor the OS reduce-motion setting (disable rise/fade, keep instant state changes).

## 8. Copy voice
Plain, short, sentence case, no exclamation marks, no emoji, no "Oops", no "seamless/magic/effortless". Say what happened and what to do. Examples: "Saved to Inbox." · "Can't reach your desktop." · "Sent." Use "This phone" and "Desktop" (or the user's device names).

## 9. Anti-slop rules (hard "do not")
Do not use: purple/indigo/blue-violet gradients, any gradients, glassmorphism/blur, neon glow, drop shadows for depth, emoji or emoji-style icons, stock/3D/cartoon illustrations, sparkle or wand icons, centered hero blocks inside app screens, card-inside-card nesting, colored left-border cards, icon-in-tinted-circle list rows, pill-shaped everything, oversized 24 px+ corner radii, default Material blue/purple seed colors, placeholder lorem or "John Doe" data, marketing-style headings ("Supercharge your workflow").

## 10. Flutter implementation notes
- Build `ThemeData` from tokens (`useMaterial3: true`, then override): `surfaceTint` transparent, elevations 0, `splashFactory: NoSplash.splashFactory` (or a subtle ink at ≤ 8% opacity), `dividerTheme` 1 px hairline, `cardTheme`/`inputDecorationTheme`/`dialogTheme` with hairline shapes, fade-only `pageTransitionsTheme`.
- Expose custom tokens as a `ThemeExtension<TdTokens>`. **No hard-coded hex values or font names in widgets** (CI grep: hex literals allowed only in the tokens file).
- Don't ship the default Flutter counter/demo styles or a `ColorScheme.fromSeed` look; if `fromSeed` is used, every role must be overridden from tokens.
- Respect font scaling up to 200% without clipping; test at narrow phone width (320 dp) and wide desktop.

## 11. Design acceptance checklist (Phase 6 gate)
- [ ] Dark is the default; Light and System work; every screen verified in both
- [ ] Only tokens used (grep shows no stray hex/font literals)
- [ ] IBM Plex Sans/Mono bundled with licenses; no runtime font fetch
- [ ] Zero emoji in UI strings, notifications, and error copy (grep)
- [ ] No gradients, blur, glow, or shadows in code (grep for `BoxShadow`, `LinearGradient`, `BackdropFilter`, `elevation > 0`)
- [ ] Accent appears only where section 1 allows
- [ ] Contrast AA verified for all text/background pairs in both themes
- [ ] Screenshots saved in `docs/screens/` — desktop 1280×800 and phone 393×852, both themes: popup, chat, notepad, share panel, pairing + approval, settings, diagnostics
- [ ] Golden tests for chat bubble (sent/received/queued), note card (normal/pinned/conflict), status indicator, share panel in both themes
- [ ] Agent has reviewed screenshots against section 9 and fixed violations

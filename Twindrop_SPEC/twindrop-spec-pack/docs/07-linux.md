# 07 — Linux Desktop (AppImage)

## Targets
Test matrix: **Fedora GNOME (Wayland)**, **Ubuntu GNOME**, **KDE Plasma**. Keep standard Flutter Linux support; don't assume identical tray behavior.

## Behavior
- Start → DB → (host starts only if pairing session or paired peer) → mDNS → tray. `--hidden` = tray only, no window.
- **Single instance** via a unix socket `$XDG_RUNTIME_DIR/twindrop.sock`. Second launch sends its command to the first and exits. Commands: `--open`, `--quick-send`, `--quit`.
- Close window = hide **only if tray confirmed**; otherwise exit (no invisible server). **Quit** (tray/menu) stops the host and frees the port.
- Standard `.desktop` launcher + icon so the app is reachable even without a tray.

## Tray
`tray_manager`. Left-click toggles popup; right-click menu: **Open TwinDrop · Send clipboard to phone · Status (disabled label) · Pause/Resume connection · Quit**. Tooltip "TwinDrop — connected to Pixel 8". Icons from `design/tray-symbolic.svg`: connected / offline (dashed outline) / unread dot; supply black and white symbolic variants so it reads on light and dark panels.

**GNOME:** tray icons need an AppIndicator/StatusNotifier host. Ubuntu ships it; Fedora/vanilla GNOME require the "AppIndicator and KStatusNotifierItem Support" extension. On startup detect failure (no StatusNotifierWatcher on D-Bus or tray init error) → show a one-time card: explanation + how to enable; app continues in a normal window. **Never** bundle, install, or modify GNOME extensions from the AppImage.
**KDE/Xfce/Cinnamon/MATE/Budgie:** native tray.
**Wayland:** can't position near the tray reliably → anchor popup to top-right of the primary monitor with 12 px margin under the panel (≈36 px); on X11 use click coordinates if available.

## Popup
380×520, always-on-top while visible, hide on blur (setting, default on) and `Esc`. Autofocus input. Enter sends; Shift+Enter newline; `Ctrl+S` Save to Notepad; `Ctrl+Shift+V` send clipboard; `Ctrl+N` open Notepad. Click a message → copy (toast); link → open in browser.
Clear the input only after the message is committed to the local DB.

## Keyboard shortcut that actually works on Wayland (LNX-007)
Wayland blocks apps from grabbing global hotkeys. So the app exposes **`--quick-send`**: the user binds any key in their desktop settings to
`/path/to/TwinDrop-x86_64.AppImage --quick-send`. Settings → Desktop shows the exact command (using `$APPIMAGE`) with a **Copy** button and one-paragraph instructions for GNOME (Settings → Keyboard → Custom Shortcuts) and KDE (System Settings → Shortcuts → Custom). On X11 a native global shortcut is P1.

## Main window
900×640. Chat + Notepad tabs (Notepad with category sidebar), Settings dialog (device, pairing, autostart, notifications, theme, hide-on-blur, shortcut command, diagnostics, data).

## Notifications
Incoming item while popup hidden → desktop notification "Pixel 8: <first 80 chars>"; click shows popup. Toggle.

## Autostart (LNX-009)
After first successful pairing ask "Start TwinDrop when you log in?" (default Yes). Writes `~/.config/autostart/twindrop.desktop`:
```
[Desktop Entry]
Type=Application
Name=TwinDrop
Exec=<value of $APPIMAGE, else current executable> --hidden
Icon=twindrop
X-GNOME-Autostart-enabled=true
```
On every start, if enabled and `$APPIMAGE` differs from the stored path → rewrite; if the target is missing, show a "stale path" notice instead of looping. No root. Toggle removes the file.

## Host details
- Bind only when a pairing session is open or a peer is paired and not Paused. Accept only private-range sources (10/8, 172.16/12, 192.168/16, 169.254/16, loopback); the token/pin handshake is the real security.
- List all non-loopback IPv4s in QR `hosts`; show them in Settings → Diagnostics (never the public IP).
- Rebind/re-announce on interface changes and after suspend/resume (detect by timer drift > 30 s).
- Port busy → next free port; QR/mDNS carry the real port.
- Firewall: if blocked, show the hint `sudo ufw allow from 192.168.0.0/16 to any port 47321 proto tcp` (ufw) or the firewalld equivalent; **never** run privileged commands.
- Cert + key + DB under XDG dirs, user-only permissions; never inside the AppImage.

## AppImage packaging
`flutter build linux --release` is **not** an AppImage. `packaging/appimage/build.sh` must:
1. Verify the Flutter bundle exists.
2. Create `AppDir/` (executable, `lib/`, `data/`, `twindrop.desktop`, icons 16–512 under `usr/share/icons/hicolor`, `AppRun` that sets `LD_LIBRARY_PATH` then execs).
3. Bundle needed libs not guaranteed on user systems (`libayatana-appindicator3` + deps, `libdbusmenu-glib`, `libsecret`, `libnotify` as needed) following the AppImage excludelist (don't bundle glibc/GL/core GTK).
4. Inspect `ldd` of the binary and plugins; record missing/extra libs.
5. Build with `appimagetool` → `dist/TwinDrop-x86_64.AppImage`; `chmod +x`; write `.sha256`.
6. Build on an older base (Ubuntu 22.04) for glibc compatibility.
7. Smoke test: run the real AppImage (not `flutter run`), and with `--appimage-extract-and-run` to cover systems without FUSE; record distro/version for each.
8. Verify SQLite FTS5 works inside the packaged app.
Name architecture truthfully. Never include user data, certs, tokens, or databases in the image.

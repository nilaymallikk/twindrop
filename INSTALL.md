# Installing TwinDrop

TwinDrop has two parts. The **desktop** is the host: it runs the server and
shows the tray icon. The **phone** is the client: it sends and receives, and it
is also the Android share-sheet target.

Nothing is sent to a cloud service. The two devices talk to each other directly
over your own Wi-Fi, with a pinned TLS certificate.

---

## Linux desktop (AppImage)

Download `dist/TwinDrop-x86_64.AppImage` and make it executable:

```bash
chmod +x TwinDrop-x86_64.AppImage
./TwinDrop-x86_64.AppImage
```

The image is self-contained: it bundles GTK3, libsecret, libnotify and the
AppIndicator stack, so it runs on a clean machine without installing
dependencies.

**No FUSE?** Extract it and run it from the folder:

```bash
./TwinDrop-x86_64.AppImage --appimage-extract
cd squashfs-root
./AppRun
```

### Launch options

| Flag | Effect |
|---|---|
| *(none)* | Opens the main window. |
| `--hidden` | Starts in the tray only — no window. |
| `--open` | Brings the running instance to the front. |
| `--quick-send` | Opens the small popup in the running instance, ready to type. |
| `--quit` | Quits the running instance and frees the port. |

A second launch never starts a second server: it forwards its flag to the
instance that already runs (through `$XDG_RUNTIME_DIR/twindrop.sock`) and exits.
That is what makes `--quick-send` usable as a desktop shortcut on Wayland.

### Autostart

Settings → Desktop → *Start at login* writes a per-user `.desktop` file. No
root is needed and nothing is installed system-wide.

### Where the data lives

| What | Where |
|---|---|
| Database, TLS identity, settings | `~/.local/share/app.twindrop/` |
| Exports (Markdown/JSON) | `~/Documents/TwinDrop/` |

Nothing is ever written inside the AppImage mount. The private key is stored
with `0600` permissions in the app data directory.

### Requirements

- A 64-bit x86-64 Linux desktop with a running graphical session.
- A StatusNotifier/AppIndicator host for the tray icon (GNOME with the
  *AppIndicator* extension, KDE Plasma, or anything else that implements the
  StatusNotifierItem spec). Without a tray, TwinDrop still works — the window
  is the way back in — but it says so instead of hiding itself.

---

## Android phone (APK)

`dist/twindrop.apk` is built with the **debug key**, because no release
keystore was provided. Android will install it for testing:

```bash
adb install -r dist/twindrop.apk
```

To ship it you need your own keystore. Drop a `app/android/key.properties`
next to the Gradle files:

```properties
storePassword=<password>
keyPassword=<password>
keyAlias=twindrop
storeFile=/absolute/path/to/twindrop.jks
```

and rebuild — the build then signs with that key automatically.

### Permissions the app asks for, and why

| Permission | Why |
|---|---|
| `INTERNET`, `ACCESS_NETWORK_STATE`, `ACCESS_WIFI_STATE`, `CHANGE_WIFI_MULTICAST_STATE` | Talk to the desktop on your Wi-Fi and find it with mDNS. |
| `CAMERA` | Only when you scan the pairing QR code. |
| `POST_NOTIFICATIONS` | Only if you allow incoming-message notifications. |
| `FOREGROUND_SERVICE` (+ `specialUse`) | Keeps one idle connection open so a message reaches you while the app is closed. |
| `REQUEST_IGNORE_BATTERY_OPTIMIZATIONS` | Optional helper so Android does not kill that connection. |

There is **no** storage, location, contacts or microphone permission.

### After installing

1. Open TwinDrop on the phone and on the desktop.
2. On the desktop, choose *Pair a phone* and scan the code with the phone.
3. Check that the 4-digit code matches on both screens, then approve.
4. Done — messages and links now sync both ways.

---

## Building from source

```bash
git clone https://github.com/nilaymallikk/twindrop.git
cd twindrop
tool/doctor.sh          # reports what is missing
tool/build_all.sh       # builds the AppImage and the APK into dist/
```

`tool/build_all.sh` needs Flutter stable, a Dart SDK, a JDK 17 and an Android
SDK. On a host without `sudo`, `tool/env.sh` points the build at a userland
toolchain — see `docs/DECISIONS.md` (D-002, D-005, D-006).

Individual steps:

```bash
tool/build_linux.sh              # Flutter Linux release bundle
tool/build_android.sh            # release APK
packaging/appimage/build.sh      # AppDir + AppImage
tool/screenshots.sh              # refresh docs/screens/ from the goldens
```

## Running the tests

```bash
cd packages/core && dart test     # 392 tests: HLC, sync, TLS pins, pairing, merge
cd app && flutter test            # 43 tests: widgets, goldens, popup shortcuts
cd packages/core && dart run tool/smoke_two_peer.dart
# -> SMOKE_OK: two peers over real pinned TLS, message both ways, exactly once
```

## Troubleshooting

- **The phone cannot find the desktop.** Both devices must be on the same Wi-Fi
  and the network must not isolate clients from each other. Desktop → Settings
  → Diagnostics shows the addresses it serves and a firewall command to run.
- **Pairing says the codes differ.** Start a new pairing session on the desktop
  and scan the new code.
- **The certificate warning.** TwinDrop pins the desktop's certificate. If the
  desktop was reinstalled, the pin no longer matches: remove the device in
  Settings and pair again.

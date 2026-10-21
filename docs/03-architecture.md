# 03 — Architecture

## Topology
```
         private Wi-Fi / LAN  (HTTPS + WSS, pinned self-signed cert)

 Android APK (client)  <─────────────────────────────►  Linux AppImage (host)
  • Flutter UI                                            • Flutter UI + tray + popup
  • full SQLite replica                                    • full SQLite replica
  • change log + peer cursors                              • change log + peer cursors
  • share receiver (native)                                • TLS server (pinned identity)
  • foreground keep-alive service                          • mDNS announcer
  • never listens                                          • pairing/approval manager
```
The data layer is **symmetric** (both sides run the same sync engine on their own replica). Only the transport role differs: desktop listens, phone dials. Keep transport behind an interface so a future relay or second host fits without data-layer changes.

## Stack (verify current versions; pin in lockfiles; log substitutions)
| Concern | Choice |
|---|---|
| UI/logic | Flutter 3.x stable, Dart 3, `riverpod` |
| DB | `drift` + `sqlite3_flutter_libs`, WAL mode, FTS5 (test it inside the AppImage) |
| Server | `shelf` + `shelf_web_socket` (or `dart:io` `HttpServer.bindSecure` directly), pinned TLS |
| Client | `dart:io` `HttpClient`/`WebSocket.connect` with custom `SecurityContext` (no public roots) and **pin check** |
| TLS cert generation | pure-Dart X.509 self-signed ECDSA P-256 (e.g. `basic_utils`/`pointycastle`); no dependency on an `openssl` binary at runtime |
| Discovery | `multicast_dns` (desktop announce), Android `nsd`/NsdManager + `MulticastLock` |
| Secure storage | `flutter_secure_storage` (Keystore on Android, libsecret on Linux; 0600 file fallback with warning) |
| QR | `qr_flutter` show, `mobile_scanner` scan |
| Tray/window | `tray_manager`, `window_manager` (needs `libayatana-appindicator3`) |
| Share intent | custom Kotlin `ShareReceiverActivity` (preferred) or `share_handler`; verify cold+warm |
| Background | custom Kotlin foreground service hosting a Dart isolate/headless engine (or `flutter_foreground_task`) |
| Notifications | `flutter_local_notifications` |
| IDs | UUIDv7 (`uuid`) |
| Hash/HMAC | `crypto` / `cryptography` |

## Repo layout
```
twindrop/
├─ docs/                      # this pack (+ PROGRESS/DECISIONS)
├─ BUILD_STATUS.md  AGENTS.md  README.md
├─ packages/core/             # PURE DART (no Flutter imports)
│  ├─ lib/{db,models,protocol,tls,sync,net,services,validators}/
│  └─ test/
├─ app/
│  ├─ lib/{main.dart,app.dart,ui/,state/,platform/{android,linux}/,features/{pairing,chat,notepad,settings,diagnostics}}
│  ├─ android/  (Kotlin: ShareReceiverActivity, KeepAliveService, BootReceiver)
│  ├─ linux/
│  └─ integration_test/
├─ packaging/{appimage,icons}/
├─ tool/{doctor.sh,build_android.sh,build_linux.sh,build_all.sh,fake_peer.dart,smoke_test_appimage.sh}
├─ dist/                      # generated, gitignored
└─ .github/workflows/         # optional CI
```

## Core services (`packages/core`)
`PairingService` · `ConnectionManager` (state machine, backoff, reconnect) · `SyncEngine` (change log, pull/notify/ack, merge) · `ChatService` · `NotepadService` · `ShareIngest` · `Validators` · `TlsIdentity` (generate/load cert, fingerprint, pin verifier) · `PeerRegistry` · `ExportService`.

## Lifecycle
- Startup detects platform and wires only relevant adapters. **Server is never instantiated on Android.**
- Linux host runs only when a pairing session is open or ≥1 peer is paired and not Paused (SEC-007). Quit: stop mDNS → close sockets with `server_shutdown` → stop server → flush DB → close DB → exit.
- Close-to-tray only if tray creation succeeded and a host is confirmed; otherwise close = quit.
- Android: foreground service (if consented) owns the connection; UI attaches to it. Without the service, connect on app open and disconnect shortly after backgrounding.
- Sync triggers: connect, notify, app resume, network change, manual retry.

## Error boundary
Convert network, TLS, protocol, serialization, permission, storage errors into typed failures; UI shows short actionable copy from `02`. Logs: timestamps, change seq numbers, error categories, host:port only. Never content, tokens, URLs with queries, QR payloads, keys.

## Threading
DB and network work off the UI isolate where heavy; never block the UI with sync. Batch applying remote changes in transactions.

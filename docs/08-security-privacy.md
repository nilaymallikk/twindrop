# 08 — Security & Privacy

## Posture
A local-first personal tool, not a public server. Same Wi-Fi is **not** a trust boundary: other devices on the LAN must not be able to read or change data just because they can reach the port.

## Data flow
Phone share/message → phone SQLite (commit) → pinned WSS → desktop SQLite (commit) → UI. Desktop → phone the same way in reverse. **No external service**: no analytics, crash upload, relay, external DB, sign-in.

## Threat model
**Protect against:** other LAN devices reading/writing without pairing · captured-operation replay · brute-forcing pairing · reuse of an expired QR · MITM on Wi-Fi (pinning) · token leakage via logs/URLs/screenshots · malicious shared content (custom URL schemes, auto-fetch) · duplicate operations from retry · malformed JSON / resource exhaustion · a lost/stolen phone (desktop revoke).
**Not protected against:** compromised OS accounts/root malware on either device · a user exposing the port to the Internet · OS-level screen capture · traffic-analysis · delivery when Android force-stops the app.

## Controls
**Pairing.** 5-min single-use random token; QR carries pin + token only; **desktop approval with matching 4-digit code**; rate-limit + lockout; generic failure messages; pairing endpoints exist only during a session.
**Transport.** TLS 1.2+/1.3, pinned self-signed ECDSA cert, no public-CA trust, no plaintext fallback. Cert rotation → mismatch error → deliberate re-pair; never auto-accept a new cert.
**Authentication.** 256-bit device token per phone; desktop stores `sha256(token)` only; constant-time compare; token only in `Authorization` header (never URL/QR/log). Revocation closes live sockets (4403) and rejects future use. Lost phone → revoke from the desktop even if the phone is offline.
**Authorization.** Server derives sender identity from the token, ignores client-claimed IDs. All validation runs on the receiving side regardless of what the sender checked.
**Input handling.** Size limits (frame 1 MiB; message 64 KiB; note 256 KiB), UTF-8 only, URL scheme allow-list (`http/https`), escape all text in widgets (never render HTML), don't auto-open or auto-fetch links, don't download media, bounded connections/timeouts (5 s handshake), reject (never truncate) oversize payloads.
**Storage.** Android Keystore for token; desktop keys with 0600 permissions; DB and certs outside the AppImage; exclude secrets/DB/certs from Git and artifacts; backups don't include plaintext tokens.
**Network exposure.** Server runs only with a session or paired peer, stops on Quit/Pause; no UPnP, no router ports, no privileged firewall changes.
**Logging.** Allowed: timestamps, seq numbers, operation counts, host:port, error categories. Forbidden: message/note text, full URLs (queries may be private), tokens, QR payloads, keys.
**mDNS.** Discovery hint only (id, name, 8-hex fp prefix); never tokens, content or authority.

## Security checklist (tick with evidence in BUILD_STATUS)
Checked on 2026-10-21. Every tick names the test or command that produced it.

- [x] Missing/invalid bearer token cannot read or write anything
      — `packages/core/test/pairing_revoke_test.dart`: "a missing token is
      rejected with 401", "an unknown token is rejected with 401", "a missing
      token cannot open a WebSocket session", "an unknown endpoint answers 404".
- [x] Revoked token rejected on REST and existing socket closed with 4403
      — same file: "a revoked token is rejected with 403", "a revoked token
      cannot open a WebSocket session", "revocation closes the live socket with
      4403" (asserts `closeCode == 4403` and `closeReason == 'revoked'`).
- [x] Expired and replayed pairing token fail
      — `packages/core/test/pairing_test.dart`: expiry, single use and
      replay of a pairing token.
- [x] Approval required; confirmation code mismatch aborts
      — `packages/core/test/pairing_test.dart` plus
      `packages/core/tool/smoke_two_peer.dart`, which aborts when the two
      confirmation codes differ.
- [x] Wrong TLS pin rejected on Android **and** Linux client (automated test)
      — `packages/core/test/tls_pin_test.dart`: "rejects the server when the pin
      does not match", "the pin of another identity does not unlock this server".
      The same Dart `TlsIdentity.pinnedHttpClient` is the only client the app
      uses on both platforms. **Not** executed on a physical Android phone —
      that part is BLOCKED for lack of a device.
- [x] No `badCertificateCallback => true` anywhere (grep in CI)
      — the only production callback is
      `packages/core/lib/tls/tls_identity.dart:126`, and it returns
      `sha256.convert(cert.der).toString() == pin`. `tls_pin_test.dart` greps
      the whole source tree for the forbidden pattern.
- [x] Invalid URL schemes stored as plain text, never as links
      — `packages/core/test/validators_test.dart`: `javascript:`, `file:`,
      `data:`, `intent:` and relative URLs are not links.
- [x] Oversize frames/messages rejected, not truncated
      — `validators_test.dart` ("throws instead of truncating", "never
      truncates: the rejected string is not shortened") and `frames_test.dart`
      (the 1 MiB frame limit).
- [x] Replaying the same change twice creates no duplicate
      — `packages/core/test/sync_engine_test.dart` (replay guard) and
      `packages/core/test/two_peer_session_test.dart` (exactly-once).
- [x] Logs contain no content, tokens, or QR payloads (grep test)
      — `packages/core/test/logger_test.dart` asserts the logger redacts URLs,
      long hex/base64 runs and, in strict mode, IP addresses.
- [x] No connection to any non-LAN host (network audit)
      — `grep -rnE 'https?://' packages/core/lib app/lib` finds no external
      host; the only URLs are in comments and test data. The app opens links
      only on an explicit tap, via the system browser.
- [x] Server not listening when unpaired and no session open
      — `CoreRuntime.start()` only calls `_ensureHost()` when a peer is active;
      `startPairingSession()` starts it for the session and `_stopHostIdle()`
      stops it again when the session closes and no peer remains. Quit and Pause
      stop it (`docs/05`).
- [x] Rate-limit lockout works for pairing
      — `packages/core/test/pairing_test.dart`: the limiter locks out for 60 s
      after 5 failures (`PairingRateLimiter` in `protocol/pairing_guard.dart`).
- [x] Keys/DB not present in the AppImage or APK (inspect archives)
      — `./dist/TwinDrop-x86_64.AppImage --appimage-extract` then
      `find squashfs-root -name '*.db' -o -name '*.pem' -o -name '*.key' -o
      -name '*.sqlite*'` → **no hits**. `unzip -l dist/twindrop.apk` shows no
      database, key or certificate; the only match is `libsqlite3.so`, the
      SQLite engine itself. The replica and the TLS key are created at runtime
      under `~/.local/share/app.twindrop/` with the key at `0600`.

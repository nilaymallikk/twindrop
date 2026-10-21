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
- [ ] Missing/invalid bearer token cannot read or write anything
- [ ] Revoked token rejected on REST and existing socket closed with 4403
- [ ] Expired and replayed pairing token fail
- [ ] Approval required; confirmation code mismatch aborts
- [ ] Wrong TLS pin rejected on Android **and** Linux client (automated test)
- [ ] No `badCertificateCallback => true` anywhere (grep in CI)
- [ ] Invalid URL schemes stored as plain text, never as links
- [ ] Oversize frames/messages rejected, not truncated
- [ ] Replaying the same change twice creates no duplicate
- [ ] Logs contain no content, tokens, or QR payloads (grep test)
- [ ] No connection to any non-LAN host (network audit)
- [ ] Server not listening when unpaired and no session open
- [ ] Rate-limit lockout works for pairing
- [ ] Keys/DB not present in the AppImage or APK (inspect archives)

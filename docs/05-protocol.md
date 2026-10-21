# 05 — Network Protocol

## Transport
- **HTTPS** (pairing endpoints) and **WSS** (session) on the desktop host. Default port **47321**; if busy, try the next 20; the real port goes into the QR and mDNS.
- **TLS only. No plaintext fallback** — ever. Self-signed ECDSA P-256 certificate generated on first host run; private key stored in the app data dir with 0600 permissions, outside the AppImage; validity 10 years; SAN lists current LAN IPs (informational only — trust comes from the pin).
- **Pinning:** `fp = SHA-256(DER certificate)`, lowercase hex. The client builds a `SecurityContext(withTrustedRoots: false)` and a `badCertificateCallback` that returns `true` **only** if the presented cert's SHA-256 equals the stored pin. An unconditional `=> true` is forbidden.
- **Spike required (Phase 2):** prove on Android + Linux that (a) correct pin connects, (b) wrong pin is rejected, (c) WebSocket upgrade works with the same client. If it cannot be made to work, **do not weaken TLS**: switch to the documented fallback in Appendix A, log the decision, and tell the user.

## Discovery
Desktop advertises mDNS `_twindrop._tcp`: TXT `v=1`, `id=<deviceId>`, `name=<deviceName>`, `fp8=<first 8 hex of pin>` (a hint only; **never authority**). Phone order: (1) last known `host:port` (1.5 s timeout), (2) mDNS browse (hold `MulticastLock`), (3) manual address. Backoff 1,2,4,8,15,30 s (±20% jitter); immediate retry on network change/foreground. Always verify the full pin regardless of how the address was found.

## Pairing
**Offer (desktop).** Generate `pairingToken` (32 random bytes, base64url), 5-minute expiry, single use. QR (JSON → base64url):
```json
{"app":"twindrop","v":1,"hosts":["192.168.1.23"],"port":47321,"fp":"<sha256 hex>","pt":"<token>","exp":"2026-10-21T10:05:00Z","name":"Ubuntu Desktop","id":"<hostDeviceId>"}
```
No long-lived secret, private key or content in the QR.

**Request (phone).** Parse QR strictly (types, `app`, `v`, expiry, host/port ranges, hex length). Connect to `hosts[*]:port` pinned to `fp`.
`POST /v1/pair/request` `{pairingToken, clientInstanceId, displayName, platform, protocolVersion}` → `202 {requestId, pollSecret, pollAfterMs}`. Same `clientInstanceId` repeated in the window is idempotent.

**Confirmation code.** Both sides compute `code = (HMAC-SHA256(pairingToken, requestId || fp) first 4 bytes as uint32) mod 10000`, zero-padded to 4 digits. Desktop approval card and phone waiting screen display it; the user confirms they match.

**Approve (desktop).** Shows device name/platform + code; **Approve / Reject**. On approve: create `deviceId`, `deviceToken` (32 random bytes), store `sha256(token)` + metadata, invalidate the pairing token.

**Collect (phone).** `GET /v1/pair/status?requestId=…` with header `X-Poll-Secret: <pollSecret>` → states `pending_approval | approved | rejected | expired`. On `approved` the response includes `{deviceId, deviceToken, hostDeviceId, hostName, protocolVersion}` **exactly once**; later polls return `already_collected`. Phone stores the token in secure storage, the pin and host in `peers`.

**Manual pairing** (no camera): user types `IP:port` + pairing code (8 groups of 4 base32 chars). Phone connects, sees the cert, shows its **6-character short fingerprint**; user compares with the one shown on the desktop; only on confirmation is the pin stored. Then proceed as above (approval + code still required).

**Abuse controls.** 5 failed token attempts in 60 s → pairing locked 60 s; responses are generic (`pairing_failed`); pairing endpoints exist only while a session is open.

## Session (WSS `/v1/ws`)
Auth: `Authorization: Bearer <deviceToken>` on the upgrade (never in the URL). If a platform can't set headers, use a single-use 30 s ticket from `POST /v1/ws-ticket`. Unknown/invalid → HTTP 401; revoked → 403.
Handshake must finish within 5 s. All frames are JSON text, ≤ 1 MiB, ≤ 30 frames/s per connection.

```
C→S  {"t":"hello","v":1,"id":"<deviceId>","name":"Pixel 8","kind":"phone","app":"0.1.0"}
S→C  {"t":"ready","v":1,"id":"<hostDeviceId>","name":"Ubuntu Desktop","seq":812,"serverTime":"…"}
both {"t":"pull","after":<peerSeqAppliedSoFar>,"limit":200}
both {"t":"changes","items":[…],"categories":[…],"next":<seq>,"more":false}
both {"t":"notify","seq":<mySeq>}            // after each local commit (optional inline "changes" ≤ 20 rows)
both {"t":"ack","seq":<peerSeqApplied>}      // after the page committed
both {"t":"ping","ts":…} / {"t":"pong","ts":…}   // every 15 s, dead if no pong in 10 s
both {"t":"error","code":"…","message":"…"}
```
Flow after `ready`: each side `pull`s from the other, applies pages (`04` rules), sends `ack`; then live mode: local commit → `notify` → peer `pull`s → `ack`. `ack` marks `peer_delivery=delivered` for messages ≤ acked seq. Unknown message types: ignore + log (forward compatible). Unknown *entity/schema version*: stop with `unsupported_version`.

## Close codes
`4401` unauthorized · `4403` revoked/forbidden · `4409` duplicate session (older closed) · `4426` upgrade required (version) · `4429` rate limited · `4500` internal · `4000` server shutdown (reason in frame `server_shutdown`).

## Other endpoints
`GET /v1/health` → `{"app":"twindrop","protocolVersion":1}` (nothing else, unauthenticated). `POST /v1/devices/self/revoke` (authenticated) — phone-initiated unpair. Desktop-side revoke is a local UI/domain action: mark `revoked_at`, close sockets (4403), reject future tokens.

## Error format (HTTP)
```json
{"error":{"code":"validation_error","message":"…","requestId":"uuid","retryable":false}}
```
Codes: `validation_error, unauthorized, forbidden, not_found, rate_limited, payload_too_large, pairing_failed, pairing_expired, server_busy, unsupported_version, certificate_mismatch, internal_error`. Never include stack traces or secrets.

## Delivery vocabulary
**Queued** = saved locally, not yet written to the socket. **Sent** = written to socket. **Delivered** = peer applied it and sent `ack`. **Read** = not implemented; don't show.

## Appendix A — Fallback if TLS pinning proves impossible (agent: use only after the Phase-2 spike fails, log it)
Keep plain `ws://` but wrap every frame in AES-256-GCM: pairing secret from QR → HKDF → session keys per connection (`k_c2s`, `k_s2c`) from client/server nonces; MAC-based mutual challenge; 8-byte strictly increasing counters as nonce (replay protection); AAD = version‖counter; constant-time MAC compare. This is weaker to implement correctly than TLS and must carry the same tests (tamper, replay, wrong secret).

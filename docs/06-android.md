# 06 — Android (APK)

`minSdk 26`, `targetSdk` = latest stable at build time. App id `app.twindrop`. Verify current Android behavior for the target SDK (foreground-service rules, local-network permission changes) at implementation time instead of copying old manifests.

## 1. Share target
Dedicated lightweight activity so sharing is fast and doesn't open the whole app:
```xml
<activity android:name=".ShareReceiverActivity" android:exported="true"
    android:theme="@style/Theme.SharePanel"       <!-- translucent, bottom-sheet style -->
    android:excludeFromRecents="true" android:taskAffinity="" android:launchMode="singleTop">
  <intent-filter>
    <action android:name="android.intent.action.SEND"/>
    <category android:name="android.intent.category.DEFAULT"/>
    <data android:mimeType="text/plain"/>
  </intent-filter>
</activity>
```
**Flow**
1. Read `EXTRA_TEXT` (+ `EXTRA_SUBJECT`/`EXTRA_TITLE` as title). Reject non-text payloads with the "text and links only" panel (SHARE-008).
2. Extract the first valid `http/https` URL; keep surrounding text as body. Optional Instagram param cleaning (`igsh`, `igshid`) if setting on; original preserved.
3. **Persist locally first** (transactional write in `core`). If it fails, tell the user it was **not** saved.
4. Per `share_default` setting: `notepad` (default) → save to Inbox; `chat` → send as message; `ask` → panel with two buttons.
5. Show the panel (spec in `13-design-system.md` §6): check icon + "Saved to Inbox" · **Change category** · **Also send as chat** · **Undo**; auto-dismiss ~4 s; finishing returns the user to the source app. If offline: "Saved. Will sync when your desktop is online."
6. If paired and reachable, sync immediately.

**Speed (SHARE-009, ≤ 1.5 s cold start to "Saved").** Prefer reusing a Flutter engine cached by the keep-alive service. If the engine start misses the budget, write the share to a small native queue (SQLite in Kotlin), show the panel instantly, and let Dart import the queue on next engine start (import must be idempotent). Record the measured time in `BUILD_STATUS.md`; log the choice in `DECISIONS.md`.

**Single processing per intent.** Consume the intent exactly once (clear extras / mark handled for `onCreate` + `onNewIntent`). Additionally dedupe identical URL text within 10 s (user may intentionally re-save later). Test cold and warm start.

**Instagram.** Shares a URL such as `https://www.instagram.com/reel/XXXX/?igsh=…`. Save the URL; never fetch it or download media. Show domain chip "instagram.com".

## 2. Keep-alive foreground service (core use case)
Purpose: keep the pinned WSS connection alive so desktop→phone messages arrive when the app is closed, and shares sync instantly.
- `foregroundServiceType="specialUse"` + property `android.app.PROPERTY_SPECIAL_USE_FGS_SUBTYPE` = "Maintains a private local-network connection to the user's own paired desktop". (APK sideloaded; revisit if ever on Play Store.)
- **Consent:** during onboarding after pairing, a clear screen explains the persistent notification and battery use; **toggle defaults ON**, user can decline or later disable in Settings. Never start silently without having shown this screen.
- Notification (channel `keepalive`, min importance, no sound): "TwinDrop · connected to <desktop>" with **Pause** action; tapping opens the app.
- Start when paired + enabled; restart on `BOOT_COMPLETED` and `MY_PACKAGE_REPLACED`; stop on unpair/revoke.
- Runs the same Dart `ConnectionManager` (headless engine/isolate) — one protocol implementation only.
- React to Wi-Fi changes via `ConnectivityManager.NetworkCallback` (immediate reconnect); `MulticastLock` only while discovering; no wakelock when screen off; one idle socket + 15 s ping.
- Incoming message while app closed → heads-up notification (channel `messages`): "Desktop: <first 80 chars>"; tap opens Chat. Toggle in Settings.
- Battery helper: button → `ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS`; info card about OEM killers (Xiaomi, Oppo, Vivo, Samsung, OnePlus) as static text.
- Be honest in Settings: delivery isn't guaranteed if the app is force-stopped, Wi-Fi is off, or the OS kills the service.

## 3. Permissions
`INTERNET, ACCESS_NETWORK_STATE, ACCESS_WIFI_STATE, CHANGE_WIFI_MULTICAST_STATE, FOREGROUND_SERVICE, FOREGROUND_SERVICE_SPECIAL_USE, POST_NOTIFICATIONS (runtime, after pairing), RECEIVE_BOOT_COMPLETED, REQUEST_IGNORE_BATTERY_OPTIMIZATIONS, CAMERA (runtime, only at QR scan)`. If the target SDK requires a local-network/nearby-devices permission for LAN sockets or mDNS, add and request it at the moment it's first needed. **No** storage, location, or contacts permissions.

## 4. Network security config
Traffic is TLS to the pinned host. Disallow cleartext (`cleartextTrafficPermitted="false"`) except where Appendix A fallback is explicitly in use (then document why). The pin check lives in Dart; do not add user-installed CA trust.

## 5. Secure storage & pairing
Device token in Android Keystore-backed storage (never SharedPreferences/SQLite plaintext). Pin + host id kept with peer metadata. Unpair: call desktop revoke if reachable, then delete token; if unreachable, state clearly that the desktop can still revoke later. Pin mismatch = blocking error with "Pair again"; no "ignore" button.

## 6. App UI summary
Bottom nav Chat · Notepad · Settings; onboarding: Welcome → scan QR → confirm code → waiting for approval → permissions (notifications, background consent, battery). Clipboard "Paste" chip in the composer when the clipboard has text.

## 7. Build & signing
`flutter build apk --release` with `android/key.properties` (gitignored). If no key: use debug signing and say so loudly; never fake a signed release. R8/ProGuard: keep Flutter/plugin classes; **verify the release APK** (share + service) before ticking done. Output `dist/twindrop.apk` + `.sha256`.

## 8. adb test recipes
```
adb install -r dist/twindrop.apk
adb shell am start -a android.intent.action.SEND -t text/plain \
  --es android.intent.extra.TEXT "https://www.instagram.com/reel/TEST123/?igsh=abc" \
  app.twindrop/.ShareReceiverActivity
adb shell dumpsys activity services app.twindrop
adb shell am kill app.twindrop          # process death; service should restart
adb shell cmd connectivity airplane-mode enable   # offline share test (or toggle manually)
```
Redact payloads from `logcat`. Record emulator vs real-device for each test.

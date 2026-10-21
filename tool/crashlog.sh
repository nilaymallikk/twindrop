#!/usr/bin/env bash
# tool/crashlog.sh — capture why TwinDrop dies on an Android device.
#
#   tool/crashlog.sh            install, launch, capture 12 s of logcat
#
# Needs the phone connected with USB debugging on. The output is filtered to
# the things that matter: the Dart error, the Android crash, and the Flutter
# engine messages.
set -euo pipefail
cd "$(dirname "$0")/.."
# shellcheck source=env.sh
. tool/env.sh

PKG="app.twindrop"
APK="dist/twindrop.apk"
DURATION="${1:-12}"

[ -f "$APK" ] || { echo "ERROR: $APK is missing — run tool/build_all.sh" >&2; exit 1; }

echo "==> devices"
adb devices -l

# Wait for the phone if it is not there yet, so the user only has to plug it
# in. On Xiaomi/MIUI the phone only exposes the ADB interface when the USB
# mode is "File transfer", not "Charging only" - that is the usual reason a
# plugged-in phone stays invisible here.
waited=0
while [ -z "$(adb devices | sed '1d' | grep -w device)" ]; do
  if [ "$waited" -ge 120 ]; then
    echo "ERROR: no device in 'device' state after ${waited}s." >&2
    echo "       - Enable USB debugging: Settings > About phone > tap Build" >&2
    echo "         number 7 times, then Settings > System > Developer options." >&2
    echo "       - On the USB notification, choose 'File transfer (MTP)'." >&2
    echo "         'Charging only' does NOT expose the ADB interface." >&2
    echo "       - Accept the 'Allow USB debugging?' prompt on the phone." >&2
    echo "       - Use a data-capable cable, not a charge-only one." >&2
    exit 1
  fi
  if [ "$waited" -eq 0 ]; then
    echo "==> waiting for the phone (plug it in, USB mode = File transfer)..."
  fi
  sleep 3
  waited=$((waited + 3))
done
echo "==> device found after ${waited}s"

echo "==> installing $APK"
adb install -r "$APK"

echo "==> clearing logcat"
adb logcat -c || true

echo "==> launching"
adb shell am force-stop "$PKG" || true
adb shell am start -n "$PKG/.MainActivity" || true

echo "==> capturing ${DURATION}s"
sleep "$DURATION"

echo
echo "======================================================================"
echo " Crash report"
echo "======================================================================"
adb logcat -d -v time 2>/dev/null | grep -iE \
  "AndroidRuntime|FATAL|libc |DEBUG   |flutter|TwinDrop|twindrop|app\.twindrop|Dart|Exception|Error|SIGABRT|SIGSEGV|ANR in|Force finishing|died" \
  | tail -250 || true

echo
echo "======================================================================"
echo " Process state"
echo "======================================================================"
adb shell pidof "$PKG" || echo "(the process is not running — it died)"
echo
adb shell dumpsys activity exit-info "$PKG" 2>/dev/null | head -60 || true

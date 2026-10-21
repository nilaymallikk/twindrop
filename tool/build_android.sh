#!/usr/bin/env bash
# tool/build_android.sh — build the release APK.
#
# Output: app/build/app/outputs/flutter-apk/app-release.apk
#
# The release build is unsigned unless a keystore is configured (see
# app/android/key.properties). An unsigned APK is still produced so the
# artefact can be inspected; BUILD_STATUS.md records which one it is.
set -euo pipefail
cd "$(dirname "$0")/.."
# shellcheck source=env.sh
. tool/env.sh

echo "==> flutter build apk --release"
(cd app && flutter build apk --release)

APK="app/build/app/outputs/flutter-apk/app-release.apk"
if [ ! -f "$APK" ]; then
  echo "ERROR: $APK was not produced" >&2
  exit 1
fi
echo "==> apk ready: $APK"
ls -la "$APK"

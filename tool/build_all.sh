#!/usr/bin/env bash
# tool/build_all.sh — produce every release artefact and its checksum.
#
#   tool/build_all.sh [--skip-android] [--skip-appimage]
#
# Produces:
#   dist/TwinDrop-x86_64.AppImage (+ .sha256)
#   dist/twindrop.apk            (+ .sha256)
#
# Nothing is reported as built unless the file exists on disk afterwards.
set -euo pipefail
cd "$(dirname "$0")/.."
# shellcheck source=env.sh
. tool/env.sh

SKIP_ANDROID=0
SKIP_APPIMAGE=0
for arg in "$@"; do
  case "$arg" in
    --skip-android) SKIP_ANDROID=1 ;;
    --skip-appimage) SKIP_APPIMAGE=1 ;;
    *) echo "unknown option: $arg" >&2; exit 2 ;;
  esac
done

DIST="$REPO/dist"
mkdir -p "$DIST"

echo "=============================================================="
echo " TwinDrop release build — $(date -u +%Y-%m-%dT%H:%M:%SZ)"
echo "=============================================================="

if [ "$SKIP_ANDROID" -eq 0 ]; then
  echo
  echo "--- Android -------------------------------------------------"
  tool/build_android.sh
  cp -f app/build/app/outputs/flutter-apk/app-release.apk "$DIST/twindrop.apk"
else
  echo
  echo "--- Android skipped -----------------------------------------"
fi

if [ "$SKIP_APPIMAGE" -eq 0 ]; then
  echo
  echo "--- Linux desktop -------------------------------------------"
  tool/build_linux.sh
  packaging/appimage/build.sh "$DIST/TwinDrop-x86_64.AppImage"
else
  echo
  echo "--- Linux desktop skipped -----------------------------------"
fi

echo
echo "--- Checksums ------------------------------------------------"
( cd "$DIST" && sha256sum *.AppImage *.apk > /dev/null 2>&1 || true )
for artefact in "$DIST/TwinDrop-x86_64.AppImage" "$DIST/twindrop.apk"; do
  [ -f "$artefact" ] || continue
  ( cd "$DIST" && sha256sum "$(basename "$artefact")" > "$(basename "$artefact").sha256" )
  printf '%s\n' "$(basename "$artefact")"
  ls -la "$artefact"
  cat "$artefact.sha256"
done

echo
echo "--- Artefacts ------------------------------------------------"
ls -la "$DIST"

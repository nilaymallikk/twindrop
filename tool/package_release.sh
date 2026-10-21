#!/usr/bin/env bash
# tool/package_release.sh — bundle the release artefacts for distribution.
#
#   tool/package_release.sh [version]
#
# Produces, in dist/:
#   TwinDrop-v<version>-linux-x86_64.tar.gz   the AppImage + INSTALL.md + README.md
#   TwinDrop-v<version>-android.apk           the APK (a copy of twindrop.apk)
#   SHA256SUMS                                checksums for every file above
#
# Nothing is listed in SHA256SUMS unless the file exists on disk.
set -euo pipefail
cd "$(dirname "$0")/.."
REPO="$(pwd)"

DIST="$REPO/dist"
APPIMAGE="$DIST/TwinDrop-x86_64.AppImage"
APK="$DIST/twindrop.apk"

VERSION="${1:-}"
if [ -z "$VERSION" ]; then
  VERSION="$(grep -m1 '^version:' app/pubspec.yaml | sed 's/^version: *//' | cut -d+ -f1)"
fi

die() { echo "ERROR: $*" >&2; exit 1; }

[ -f "$APPIMAGE" ] || die "$APPIMAGE is missing — run tool/build_all.sh first"
[ -f "$APK" ] || die "$APK is missing — run tool/build_all.sh first"

STAGE="$DIST/.stage"
rm -rf "$STAGE"
mkdir -p "$STAGE/TwinDrop-$VERSION"

echo "==> staging the release"
cp -f "$APPIMAGE" "$STAGE/TwinDrop-$VERSION/"
cp -f "$APK" "$STAGE/TwinDrop-$VERSION/twindrop.apk"
cp -f INSTALL.md "$STAGE/TwinDrop-$VERSION/"
cp -f README.md "$STAGE/TwinDrop-$VERSION/"
cat > "$STAGE/TwinDrop-$VERSION/VERSION" <<EOF
TwinDrop $VERSION
EOF

TARBALL="$DIST/TwinDrop-v$VERSION-linux-x86_64.tar.gz"
echo "==> building $TARBALL"
# Byte-reproducible: fixed mtime/owner and a gzip header without a timestamp,
# so the same inputs always give the same checksum.
tar --sort=name \
    --mtime='UTC 2020-01-01' \
    --owner=0 --group=0 --numeric-owner \
    -cf - -C "$STAGE" "TwinDrop-$VERSION" \
  | gzip -n -9 > "$TARBALL"
rm -rf "$STAGE"

APK_OUT="$DIST/TwinDrop-v$VERSION-android.apk"
cp -f "$APK" "$APK_OUT"

echo "==> checksums"
# SHA256SUMS covers exactly the files that are published in the release.
# The build outputs keep their own per-file .sha256 next to them in dist/.
( cd "$DIST" && rm -f SHA256SUMS && sha256sum \
    "TwinDrop-x86_64.AppImage" \
    "TwinDrop-v$VERSION-linux-x86_64.tar.gz" \
    "TwinDrop-v$VERSION-android.apk" > SHA256SUMS )

echo
echo "==> release contents"
ls -la "$DIST"
echo
cat "$DIST/SHA256SUMS"
echo
( cd "$DIST" && sha256sum -c SHA256SUMS )

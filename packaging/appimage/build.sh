#!/usr/bin/env bash
# packaging/appimage/build.sh — assemble the AppDir and build the AppImage.
#
#   packaging/appimage/build.sh [output]
#
# Produces a self-contained AppImage: the Flutter bundle plus every shared
# library it needs that a clean machine may not have (GTK3, libsecret,
# libnotify, appindicator, dbusmenu).
#
# The AppImage is not signed and the artefact is reported honestly: BUILD_STATUS
# .md records the exact bytes and SHA-256 of whatever this script produced.
set -euo pipefail

REPO="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$REPO"
# shellcheck source=../../tool/env.sh
. tool/env.sh

OUT="${1:-$REPO/dist/TwinDrop-x86_64.AppImage}"
APPDIR="$REPO/packaging/appimage/AppDir"
BUNDLE="$REPO/app/build/linux/x64/release/bundle"
ICONS="$REPO/packaging/icons"

die() { echo "ERROR: $*" >&2; exit 1; }

[ -x "$BUNDLE/twindrop" ] || die "the Linux release bundle is missing; run tool/build_linux.sh first"

echo "==> preparing AppDir"
rm -rf "$APPDIR"
mkdir -p "$APPDIR/usr/bin" "$APPDIR/usr/lib" "$APPDIR/usr/share/icons/hicolor"

# 1. The Flutter bundle, kept in its own layout so the relative $ORIGIN/lib
#    rpath that Flutter writes keeps working untouched.
mkdir -p "$APPDIR/usr/lib/twindrop"
cp -a "$BUNDLE/." "$APPDIR/usr/lib/twindrop/"

# 2. Icons.
for size in 16 24 32 48 64 128 256 512; do
  mkdir -p "$APPDIR/usr/share/icons/hicolor/${size}x${size}/apps"
  cp -f "$ICONS/hicolor/${size}x${size}/apps/twindrop.png" \
    "$APPDIR/usr/share/icons/hicolor/${size}x${size}/apps/twindrop.png"
done
cp -f "$ICONS/hicolor/512x512/apps/twindrop.png" "$APPDIR/.DirIcon"
# appimagetool wants the icon next to the desktop file as well.
cp -f "$ICONS/hicolor/256x256/apps/twindrop.png" "$APPDIR/twindrop.png"

# 3. Desktop entry.
cat > "$APPDIR/twindrop.desktop" <<'DESKTOP'
[Desktop Entry]
Type=Application
Name=TwinDrop
Comment=Private sharing between your phone and your desktop
Exec=twindrop
Icon=twindrop
Terminal=false
Categories=Network;FileTransfer;
Keywords=transfer;share;clipboard;notepad;
StartupWMClass=twindrop
DESKTOP

# 4. AppRun: sets the library path and hands over to the Flutter binary.
cat > "$APPDIR/AppRun" <<'APPRUN'
#!/bin/sh
# TwinDrop AppImage entry point.
HERE="$(dirname "$(readlink -f "$0")")"
export LD_LIBRARY_PATH="$HERE/usr/lib:$HERE/usr/lib/twindrop/lib${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
export GDK_BACKEND="${GDK_BACKEND:-x11}"
export QT_QPA_PLATFORM="${QT_QPA_PLATFORM:-xcb}"
export NO_AT_BRIDGE=1
exec "$HERE/usr/lib/twindrop/twindrop" "$@"
APPRUN
chmod +x "$APPDIR/AppRun"

# 5. Bundle the shared libraries a clean machine may not have.
#    glibc itself is never bundled: the AppImage must run on the host's libc.
echo "==> resolving shared libraries"
BUNDLED_LIBS="$APPDIR/usr/lib"
EXCLUDE_RE='^(libc|libm|libdl|libpthread|librt|libresolv|libutil|libnsl|libanl|ld-linux.*|libgcc_s)\.so'

bundle_libs() {
  local binary="$1"
  ldd "$binary" 2>/dev/null | awk '{print $3}' | grep '^/' | sort -u | while read -r lib; do
    local base
    base="$(basename "$lib")"
    case "$base" in
      $EXCLUDE_RE) continue ;;
    esac
    [ -e "$BUNDLED_LIBS/$base" ] && continue
    # Skip libraries the host provides system-wide in a stable location.
    case "$lib" in
      /lib/*|/usr/lib/*)
        case "$lib" in
          /lib64/*|/usr/lib64/*)
            # Host lib64: still bundle the desktop stack, but never the
            # kernel-facing ones listed above.
            ;;
        esac
        ;;
    esac
    cp -L "$lib" "$BUNDLED_LIBS/$base" 2>/dev/null || true
  done
}

QUEUE=("$BUNDLE/twindrop")
while [ ${#QUEUE[@]} -gt 0 ]; do
  current="${QUEUE[0]}"
  QUEUE=("${QUEUE[@]:1}")
  [ -f "$current" ] || continue
  for lib in $(ldd "$current" 2>/dev/null | awk '{print $3}' | grep '^/' | sort -u); do
    base="$(basename "$lib")"
    case "$base" in
      $EXCLUDE_RE) continue ;;
    esac
    if [ ! -e "$BUNDLED_LIBS/$base" ]; then
      cp -L "$lib" "$BUNDLED_LIBS/$base" 2>/dev/null || true
    fi
    case "$lib" in
      "$BUNDLE"/*) QUEUE+=("$lib") ;;
    esac
  done
done

# The plugin libraries inside the Flutter bundle link against the desktop stack.
for so in "$BUNDLE"/lib/*.so; do
  [ -f "$so" ] || continue
  for lib in $(ldd "$so" 2>/dev/null | awk '{print $3}' | grep '^/' | sort -u); do
    base="$(basename "$lib")"
    case "$base" in
      $EXCLUDE_RE) continue ;;
    esac
    [ -e "$BUNDLED_LIBS/$base" ] || cp -L "$lib" "$BUNDLED_LIBS/$base" 2>/dev/null || true
  done
done

echo "    bundled $(ls -1 "$BUNDLED_LIBS" | wc -l) libraries"

# 6. Build the image.
APPIMAGETOOL=""
if [ -x "${TWINDROP_TOOLCHAIN:-/data/toolchain}/appimagetool/squashfs-root/usr/bin/appimagetool" ]; then
  APPIMAGETOOL="${TWINDROP_TOOLCHAIN:-/data/toolchain}/appimagetool/squashfs-root/usr/bin/appimagetool"
  export LD_LIBRARY_PATH="${TWINDROP_TOOLCHAIN:-/data/toolchain}/appimagetool/squashfs-root/usr/lib${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
elif command -v appimagetool >/dev/null 2>&1; then
  APPIMAGETOOL="$(command -v appimagetool)"
else
  die "appimagetool not found (expected under ${TWINDROP_TOOLCHAIN:-/data/toolchain}/appimagetool)"
fi

mkdir -p "$(dirname "$OUT")"
echo "==> running appimagetool"
ARCH=x86_64 "$APPIMAGETOOL" --no-appstream "$APPDIR" "$OUT"

echo "==> built $OUT"
ls -la "$OUT"

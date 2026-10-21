#!/usr/bin/env bash
# tool/fetch_tooling.sh — fetch appimagetool into the project toolchain.
#
# The AppImage is extracted (not run) because the host may have no FUSE. The
# extracted tree is what packaging/appimage/build.sh invokes.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=/dev/null
source "$ROOT/tool/env.sh"

TOOLCHAIN="${TWINDROP_TOOLCHAIN:-/data/toolchain}"
DEST="$TOOLCHAIN/appimagetool"
URL="${APPIMAGETOOL_URL:-https://github.com/AppImage/AppImageKit/releases/download/continuous/appimagetool-x86_64.AppImage}"

log() { printf '[tooling] %s\n' "$*"; }
die() { printf '[tooling] ERROR: %s\n' "$*" >&2; exit 1; }

command -v curl >/dev/null || die "curl is required to fetch appimagetool"
mkdir -p "$DEST"
tmp="$(mktemp "$DEST/.appimagetool.XXXXXX")"
trap 'rm -f "$tmp"' EXIT

log "downloading $URL"
curl -fL --retry 3 --connect-timeout 20 -o "$tmp" "$URL"

bytes="$(stat -c%s "$tmp")"
[ "$bytes" -ge 1000000 ] || die "downloaded appimagetool is only $bytes bytes"
magic="$(od -An -tx1 -N4 "$tmp" | tr -d ' \n')"
[ "$magic" = '7f454c46' ] || die "downloaded file is not an ELF binary (magic $magic)"

actual="$(sha256sum "$tmp" | cut -d' ' -f1)"
if [ -n "${APPIMAGETOOL_SHA256:-}" ]; then
  printf '%s  %s\n' "$APPIMAGETOOL_SHA256" "$tmp" | sha256sum -c -
  log "verified pinned sha256 $APPIMAGETOOL_SHA256"
else
  log "WARN: APPIMAGETOOL_SHA256 not set; computed sha256 $actual"
  log "      set APPIMAGETOOL_SHA256 for reproducible builds"
fi

chmod 755 "$tmp"

# Extract: the host may have no FUSE, so the image is unpacked, not mounted.
log "extracting"
rm -rf "$DEST/squashfs-root"
( cd "$DEST" && "$tmp" --appimage-extract >/dev/null )
[ -x "$DEST/squashfs-root/usr/bin/appimagetool" ] ||
  die "extraction did not produce usr/bin/appimagetool"

mv -f "$tmp" "$DEST/appimagetool-x86_64.AppImage"
trap - EXIT
log "installed $DEST/squashfs-root/usr/bin/appimagetool ($bytes bytes, sha256 $actual)"

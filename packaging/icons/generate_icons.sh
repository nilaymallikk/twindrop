#!/usr/bin/env bash
# Generate every TwinDrop icon from design/logo-mark.svg and design/tray-symbolic.svg.
#
#   ./packaging/icons/generate_icons.sh
#
# Requires ImageMagick built with RSVG (the host `magick`/`convert` here is;
# verify with: convert -list format | grep -i svg).
#
# Outputs:
#   packaging/icons/twindrop.svg, twindrop-tile.svg, hicolor/<size>/apps/twindrop.png
#   packaging/icons/tray/{connected,offline,unread}-{black,white}-{24,48}.png
#   app/assets/tray/{connected,offline,unread}-{black,white}.png   (Flutter assets, 24 px + 48 px)
#   app/android/app/src/main/res/mipmap-*/ic_launcher{,_round}.png, ic_launcher_foreground.png
#   app/android/app/src/main/res/mipmap-anydpi-v26/ic_launcher{,_round}.xml
#   app/android/app/src/main/res/values/colors.xml
#   app/android/app/src/main/res/drawable-*/ic_stat_twindrop.png
#
# Icons are deterministic: no timestamps, no external fetches.
set -euo pipefail
cd "$(dirname "$0")/../.."
ROOT="$PWD"
OUT="$ROOT/packaging/icons"
APP="$ROOT/app"
RES="$APP/android/app/src/main/res"
DESIGN="$ROOT/design"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

magick_cmd() { command -v magick >/dev/null 2>&1 && magick "$@" || convert "$@"; }

# --- vector sources ---------------------------------------------------------
LOGO_CONTENT="$(sed -e '1d' -e '$d' "$DESIGN/logo-mark.svg")"

cat > "$TMP/logo-tile.svg" <<EOF
<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 64 64" width="64" height="64" role="img" aria-label="TwinDrop">
  <rect x="0" y="0" width="64" height="64" rx="14" fill="#0E0F11"/>
  <g transform="translate(6.4 6.4) scale(0.8)">
$LOGO_CONTENT
  </g>
</svg>
EOF
cp "$TMP/logo-tile.svg" "$OUT/twindrop-tile.svg"
cp "$DESIGN/logo-mark.svg" "$OUT/twindrop-mark.svg"
cp "$TMP/logo-tile.svg" "$OUT/twindrop.svg"

cat > "$TMP/logo-round.svg" <<EOF
<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 64 64" width="64" height="64" role="img" aria-label="TwinDrop">
  <circle cx="32" cy="32" r="32" fill="#0E0F11"/>
  <g transform="translate(8.96 8.96) scale(0.72)">
$LOGO_CONTENT
  </g>
</svg>
EOF

cat > "$TMP/logo-fg.svg" <<EOF
<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 64 64" width="64" height="64">
  <g transform="translate(12.16 12.16) scale(0.62)">
$LOGO_CONTENT
  </g>
</svg>
EOF

render() { # render <svg> <px> <out>
  magick_cmd -background none -density 1536 "$1" -resize "${2}x${2}" -strip "$3"
}

# --- Linux hicolor icons ----------------------------------------------------
for size in 16 24 32 48 64 128 256 512; do
  dir="$OUT/hicolor/${size}x${size}/apps"
  mkdir -p "$dir"
  render "$TMP/logo-tile.svg" "$size" "$dir/twindrop.png"
done
mkdir -p "$OUT/hicolor/scalable/apps"
cp "$TMP/logo-tile.svg" "$OUT/hicolor/scalable/apps/twindrop.svg"

# --- Linux tray icons (both panel polarities, three states) -----------------
tray_rect_connected='<rect x="3" y="3" width="13" height="13" rx="2.5" fill="none" stroke="COLOR" stroke-width="2"/><rect x="8" y="8" width="13" height="13" rx="2.5" fill="COLOR"/>'
tray_rect_offline='<rect x="3" y="3" width="13" height="13" rx="2.5" fill="none" stroke="COLOR" stroke-width="2" stroke-dasharray="2.6 1.8"/><rect x="8" y="8" width="13" height="13" rx="2.5" fill="none" stroke="COLOR" stroke-width="2" stroke-dasharray="2.6 1.8"/>'
tray_dot='<circle cx="21" cy="3" r="2.6" fill="COLOR"/>'

for variant in black white; do
  if [ "$variant" = black ]; then color='#000000'; else color='#FFFFFF'; fi
  for state in connected offline unread; do
    body="$tray_rect_connected"
    [ "$state" = offline ] && body="$tray_rect_offline"
    [ "$state" = unread ] && body="$tray_rect_connected$tray_dot"
    svg="$TMP/tray-$state-$variant.svg"
    cat > "$svg" <<EOF
<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" width="24" height="24">
  ${body//COLOR/$color}
</svg>
EOF
    mkdir -p "$OUT/tray" "$APP/assets/tray"
    for px in 24 48; do
      render "$svg" "$px" "$OUT/tray/${state}-${variant}-${px}.png"
    done
    render "$svg" 24 "$APP/assets/tray/${state}-${variant}.png"
  done
done

# --- Android launcher icons ------------------------------------------------
declare -A sizes=( [mdpi]=48 [hdpi]=72 [xhdpi]=96 [xxhdpi]=144 [xxxhdpi]=192 )
declare -A fg_sizes=( [mdpi]=108 [hdpi]=162 [xhdpi]=216 [xxhdpi]=324 [xxxhdpi]=432 )
for bucket in mdpi hdpi xhdpi xxhdpi xxxhdpi; do
  mkdir -p "$RES/mipmap-$bucket"
  render "$TMP/logo-tile.svg" "${sizes[$bucket]}" "$RES/mipmap-$bucket/ic_launcher.png"
  render "$TMP/logo-round.svg" "${sizes[$bucket]}" "$RES/mipmap-$bucket/ic_launcher_round.png"
  render "$TMP/logo-fg.svg" "${fg_sizes[$bucket]}" "$RES/mipmap-$bucket/ic_launcher_foreground.png"
done

mkdir -p "$RES/mipmap-anydpi-v26"
cat > "$RES/mipmap-anydpi-v26/ic_launcher.xml" <<'EOF'
<?xml version="1.0" encoding="utf-8"?>
<adaptive-icon xmlns:android="http://schemas.android.com/apk/res/android">
    <background android:drawable="@color/ic_launcher_background" />
    <foreground android:drawable="@mipmap/ic_launcher_foreground" />
    <monochrome android:drawable="@mipmap/ic_launcher_foreground" />
</adaptive-icon>
EOF
cat > "$RES/mipmap-anydpi-v26/ic_launcher_round.xml" <<'EOF'
<?xml version="1.0" encoding="utf-8"?>
<adaptive-icon xmlns:android="http://schemas.android.com/apk/res/android">
    <background android:drawable="@color/ic_launcher_background" />
    <foreground android:drawable="@mipmap/ic_launcher_foreground" />
    <monochrome android:drawable="@mipmap/ic_launcher_foreground" />
</adaptive-icon>
EOF
mkdir -p "$RES/values"
cat > "$RES/values/colors.xml" <<'EOF'
<?xml version="1.0" encoding="utf-8"?>
<resources>
    <!-- design/tokens.json: bg dark -->
    <color name="ic_launcher_background">#0E0F11</color>
</resources>
EOF

# --- Android notification small icon (single-colour silhouette) ------------
for bucket in mdpi hdpi xhdpi xxhdpi xxxhdpi; do
  case "$bucket" in
    mdpi) px=24 ;; hdpi) px=36 ;; xhdpi) px=48 ;; xxhdpi) px=72 ;; xxxhdpi) px=96 ;;
  esac
  mkdir -p "$RES/drawable-$bucket"
  render "$TMP/tray-connected-white.svg" "$px" "$RES/drawable-$bucket/ic_stat_twindrop.png"
done

echo "icons generated:"
find "$OUT" "$APP/assets/tray" "$RES" -name '*.png' -newer "$OUT/twindrop.svg" -o -name 'ic_launcher.xml' -newer "$OUT/twindrop.svg" | sed "s|$ROOT/||" | sort | head -60

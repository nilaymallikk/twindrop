#!/usr/bin/env bash
# tool/screenshots.sh — publish the golden renders into docs/screens/.
#
# The goldens are the source of truth: they are produced by
#   flutter test --update-goldens test/golden_test.dart
# and reviewed by eye against docs/13 §9. This script only copies them to the
# place the Phase 6 gate expects them (docs/13 §11).
set -euo pipefail
cd "$(dirname "$0")/.."

SRC="app/test/goldens"
DEST="docs/screens"

[ -d "$SRC" ] || { echo "ERROR: $SRC does not exist" >&2; exit 1; }
mkdir -p "$DEST"
rm -f "$DEST"/*.png

count=0
for png in "$SRC"/*.png; do
  [ -e "$png" ] || continue
  cp -f "$png" "$DEST/$(basename "$png")"
  count=$((count + 1))
done

echo "published $count screenshots to $DEST"
ls -la "$DEST"

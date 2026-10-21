#!/usr/bin/env bash
# tool/goldens.sh — run the golden tests with a pinned timezone.
#
#   tool/goldens.sh            check the goldens
#   tool/goldens.sh --update   regenerate them
#
# The chat bubble shows a wall-clock label, so the rendered picture depends on
# the machine's timezone. The goldens are pinned to UTC; the test refuses to
# run anywhere else.
set -euo pipefail
cd "$(dirname "$0")/.."
# shellcheck source=env.sh
. tool/env.sh

UPDATE=""
if [ "${1:-}" = "--update" ]; then
  UPDATE="--update-goldens"
fi

echo "==> golden tests (TZ=UTC)"
( cd app && TZ=UTC flutter test $UPDATE test/golden_test.dart )

if [ -z "$UPDATE" ]; then
  echo
  echo "==> publishing the screenshots to docs/screens/"
  tool/screenshots.sh > /dev/null
  echo "    docs/screens/ is up to date"
fi

#!/usr/bin/env bash
# tool/build_linux.sh — build the Linux desktop release bundle.
#
# Output: app/build/linux/x64/release/bundle/
#
# The host has no sudo and no clang; `tool/env.sh` points Flutter at the
# userland Fedora sysroot and at the gcc wrappers in packaging/toolchain/bin.
set -euo pipefail
cd "$(dirname "$0")/.."
# shellcheck source=env.sh
. tool/env.sh

echo "==> flutter build linux --release"
(cd app && flutter build linux --release)

BUNDLE="app/build/linux/x64/release/bundle"
if [ ! -x "$BUNDLE/twindrop" ]; then
  echo "ERROR: $BUNDLE/twindrop was not produced" >&2
  exit 1
fi
echo "==> bundle ready: $BUNDLE"
ls -la "$BUNDLE" | head -20

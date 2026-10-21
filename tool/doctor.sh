#!/usr/bin/env bash
# tool/doctor.sh — inspect and print the toolchain required to build TwinDrop.
# Never installs anything. Exits non-zero if a required tool is missing.
set -u
cd "$(dirname "$0")/.."
# shellcheck source=env.sh
. tool/env.sh 2>/dev/null || true

fail=0
ok() { printf '  [ok]   %s\n' "$*"; }
miss() { printf '  [MISS] %s\n' "$*"; fail=1; }
note() { printf '         %s\n' "$*"; }

echo "TwinDrop doctor — $(date -u +%Y-%m-%dT%H:%M:%SZ)"
echo
echo "Host"
ok "$(uname -srm)"
if [ -f /etc/os-release ]; then . /etc/os-release; ok "$PRETTY_NAME"; fi
note "DISPLAY=${DISPLAY:-<unset>} WAYLAND_DISPLAY=${WAYLAND_DISPLAY:-<unset>} SESSION=${XDG_SESSION_TYPE:-<unset>}"
note "toolchain root: ${TWINDROP_TOOLCHAIN:-<unset>}"

echo
echo "Dart / Flutter"
if command -v flutter >/dev/null 2>&1; then
  ver="$(flutter --version 2>/dev/null | head -1)"
  [ -n "$ver" ] && ok "$ver" || miss "flutter present but not runnable"
else miss "flutter (source tool/env.sh)"; fi
if command -v dart >/dev/null 2>&1; then
  ok "$(dart --version 2>&1)"
else miss "dart"; fi

echo
echo "Android"
if [ -n "${ANDROID_HOME:-}" ] && [ -d "${ANDROID_HOME:-/nonexistent}" ]; then
  ok "ANDROID_HOME=$ANDROID_HOME"
else miss "ANDROID_HOME"; fi
if command -v adb >/dev/null 2>&1; then ok "$(adb version 2>/dev/null | head -1)"; else miss "adb"; fi
if command -v javac >/dev/null 2>&1; then ok "$(javac -version 2>&1)"; else miss "javac (JDK)"; fi
if [ -n "${JAVA_HOME:-}" ] && [ -x "${JAVA_HOME:-/nonexistent}/bin/java" ]; then
  ok "JAVA_HOME=$JAVA_HOME"
else miss "JAVA_HOME"; fi
if [ -d "${ANDROID_HOME:-/nonexistent}/platforms" ]; then
  ok "platforms: $(ls "${ANDROID_HOME}/platforms" 2>/dev/null | tr '\n' ' ')"
else note "no Android platforms installed yet (sdkmanager)"; fi
if [ -d "${ANDROID_HOME:-/nonexistent}/build-tools" ]; then
  ok "build-tools: $(ls "${ANDROID_HOME}/build-tools" 2>/dev/null | tr '\n' ' ')"
else note "no Android build-tools installed yet"; fi
adb devices 2>/dev/null | tail -n +2 | sed 's/^/         device: /' || true

echo
echo "Linux desktop build dependencies (pkg-config via sysroot)"
if [ -n "${PKG_CONFIG_PATH:-}" ]; then ok "PKG_CONFIG_PATH set"; else note "PKG_CONFIG_PATH not set"; fi
for mod in gtk+-3.0 libsecret-1 libnotify ayatana-appindicator3-0.1; do
  if pkg-config --exists "$mod" 2>/dev/null; then
    ok "$mod $(pkg-config --modversion "$mod" 2>/dev/null)"
  else
    miss "$mod (pkg-config)"
  fi
done
for tool in clang gcc cmake ninja pkg-config; do
  if command -v "$tool" >/dev/null 2>&1; then ok "$tool $(command -v "$tool")"; else note "$tool not found"; fi
done

echo
echo "AppImage tooling"
for tool in appimagetool linuxdeploy; do
  if command -v "$tool" >/dev/null 2>&1; then ok "$tool $(command -v "$tool")"
  elif [ -x "tool/bin/$tool" ]; then ok "tool/bin/$tool"
  else note "$tool not found (packaging/appimage/build.sh can fetch it)"; fi
done

echo
echo "SQLite (drift, FTS5)"
if command -v sqlite3 >/dev/null 2>&1; then
  ok "sqlite3 $(sqlite3 --version | cut -d' ' -f1)"
  if sqlite3 :memory: "CREATE VIRTUAL TABLE t USING fts5(x);" 2>/dev/null; then ok "FTS5 available"; else miss "FTS5 unavailable"; fi
else
  note "sqlite3 CLI missing; dart sqlite3 package uses system libsqlite3"
  ldconfig -p 2>/dev/null | grep -q libsqlite3 && ok "libsqlite3 present" || miss "libsqlite3"
fi

echo
if [ "$fail" -ne 0 ]; then echo "RESULT: MISSING REQUIRED TOOLS (see [MISS] above)"; else echo "RESULT: OK"; fi
exit "$fail"

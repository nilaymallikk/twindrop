#!/usr/bin/env bash
# Source this file before running Flutter/Dart/Android commands in this repo.
# It points all toolchains and the userland Fedora sysroot at /data/toolchain.
#
#   source tool/env.sh
#
# Override TWINDROP_TOOLCHAIN if the toolchain lives elsewhere.

export TWINDROP_TOOLCHAIN="${TWINDROP_TOOLCHAIN:-/data/toolchain}"

export PATH="$TWINDROP_TOOLCHAIN/flutter/bin:$TWINDROP_TOOLCHAIN/dart/dart-sdk/bin:$TWINDROP_TOOLCHAIN/jdk17/bin:$TWINDROP_TOOLCHAIN/android-sdk/cmdline-tools/latest/bin:$TWINDROP_TOOLCHAIN/android-sdk/platform-tools:$PATH"

export JAVA_HOME="$TWINDROP_TOOLCHAIN/jdk17"
export ANDROID_HOME="$TWINDROP_TOOLCHAIN/android-sdk"
export ANDROID_SDK_ROOT="$ANDROID_HOME"
export FLUTTER_ROOT="$TWINDROP_TOOLCHAIN/flutter"
export PUB_CACHE="${PUB_CACHE:-$HOME/.pub-cache}"

# Linux desktop build: GTK/secret/notify/appindicator headers live in a userland
# Fedora sysroot (no sudo on the host). Point pkg-config at it.
TWINDROP_SYSROOT="$TWINDROP_TOOLCHAIN/sysroot"
if [ -d "$TWINDROP_SYSROOT/usr" ]; then
  export TWINDROP_SYSROOT
  export PKG_CONFIG_PATH="$TWINDROP_SYSROOT/usr/lib64/pkgconfig:$TWINDROP_SYSROOT/usr/share/pkgconfig:$TWINDROP_SYSROOT/usr/lib/pkgconfig"
  export PKG_CONFIG_SYSROOT_DIR="$TWINDROP_SYSROOT"
  # Some generated headers are looked up via the compiler include path.
  export CFLAGS="${CFLAGS:-} -I$TWINDROP_SYSROOT/usr/include"
  export CXXFLAGS="${CXXFLAGS:-} -I$TWINDROP_SYSROOT/usr/include"
  export LDFLAGS="${LDFLAGS:-} -L$TWINDROP_SYSROOT/usr/lib64"
  # Runtime: host has GTK3; appindicator/libdbusmenu only in the sysroot.
  export LD_LIBRARY_PATH="$TWINDROP_SYSROOT/usr/lib64${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
fi

# Keep Flutter from phoning home for analytics.
export FLUTTER_SUPPRESS_ANALYTICS=true
export CI="${CI:-true}"

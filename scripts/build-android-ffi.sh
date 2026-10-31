#!/usr/bin/env bash
# Build the Android arm64 embedded core and stage it in jniLibs.
# Requires: git, cmake, ninja, JDK 17, Android NDK 27+, and network for vcpkg
# dependencies on the first run.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
NDK="${ANDROID_NDK_HOME:-${ANDROID_HOME:-$HOME/Android/Sdk}/ndk/27.2.12479018}"
VCPKG="${VCPKG_ROOT:-$ROOT/.vcpkg}"
TRIPLET=arm64-android

if [[ ! -x "$VCPKG/vcpkg" ]]; then
  git clone --depth 1 https://github.com/microsoft/vcpkg.git "$VCPKG"
  "$VCPKG/bootstrap-vcpkg.sh" -disableMetrics
fi

export VCPKG_ROOT="$VCPKG"
export ANDROID_NDK_HOME="$NDK"
export ANDROID_NDK_ROOT="$NDK"

if [[ ! -f "$ROOT/.vcpkg_installed/$TRIPLET/lib/libcurl.a" ]]; then
  (cd "$VCPKG" && ./vcpkg install --classic --triplet "$TRIPLET" \
    --x-install-root="$ROOT/.vcpkg_installed" "curl[openssl]" sqlite3)
fi

cmake --preset android-arm64
cmake --build build/android-arm64 --target chatvv_ffi -j"$(nproc)"

DEST="$ROOT/app/android/app/src/main/jniLibs/arm64-v8a"
mkdir -p "$DEST"
cp "$ROOT/build/android-arm64/libchatvv_ffi.so" "$DEST/libchatvv_ffi.so"
"$NDK/toolchains/llvm/prebuilt/linux-x86_64/bin/llvm-strip" \
  --strip-unneeded "$DEST/libchatvv_ffi.so"
cp "$NDK/toolchains/llvm/prebuilt/linux-x86_64/sysroot/usr/lib/aarch64-linux-android/libc++_shared.so" \
  "$DEST/libc++_shared.so"

echo "staged: $DEST/libchatvv_ffi.so"

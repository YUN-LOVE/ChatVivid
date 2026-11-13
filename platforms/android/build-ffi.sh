#!/usr/bin/env bash
# Build the Android arm64 embedded core (C++ FFI + read-aloud Rust cdylib) and
# stage the shared libraries in app/android/app/src/main/jniLibs/arm64-v8a/.
#
# Canonical location. scripts/build-android-ffi.sh is a thin compatibility shim.
#
# Usage:
#   platforms/android/build-ffi.sh [extra cmake configure args...]
#
# Environment:
#   ANDROID_NDK_HOME / ANDROID_HOME / ANDROID_SDK_ROOT   NDK 27+ discovery
#   ANDROID_NDK_HOST_TAG     NDK prebuilt host tag (default: linux-x86_64 /
#                            darwin-x86_64 from the host OS)
#   VCPKG_ROOT               vcpkg checkout (default: <repo>/.vcpkg)
#   CHATVV_VULKAN            AUTO (default), ON (CI), OFF
#   CHATVV_READ_ALOUD_LINKAGE  shared (default: required for jniLibs)
#   ANDROID_VULKAN_INCLUDE_DIR Vulkan headers dir (default /usr/include: the host
#                              libvulkan-dev has vulkan.hpp, the NDK does not)
#   ANDROID_VULKAN_CMAKE_ARGS  extra configure args; use if Android cross
#                              configure picks up host x86_64 Vulkan libs, e.g.
#                              -DVulkan_LIBRARY=<ndk-sysroot>/libvulkan.so
#                              -DVulkan_INCLUDE_DIR=<ndk-sysroot>/usr/include
#   CHATVV_SKIP_READ_ALOUD=1   skip read-aloud staging (local experiments only)
#
# Rust: read-aloud builds through CMake (see cmake/readaloud.cmake). This script
# exports the NDK linker/CC/AR env vars cargo needs, and the 16 KB page-size
# linker flags for the Rust cdylib (verify-apk.sh checks every bundled ELF).
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
# shellcheck source=../common/build-lib.sh
source "$ROOT/platforms/common/build-lib.sh"

NDK="${ANDROID_NDK_HOME:-${ANDROID_HOME:-${ANDROID_SDK_ROOT:-$HOME/Android/Sdk}}/ndk/27.2.12479018}"
if [[ -z "$NDK" || ! -d "$NDK" ]]; then
  {
    echo "Android NDK not found: '$NDK'"
    echo "Install NDK 27.2.12479018 or export ANDROID_NDK_HOME."
  } >&2
  exit 1
fi

case "$(uname -s)" in
  Linux) DEFAULT_HOST_TAG="linux-x86_64" ;;
  Darwin) DEFAULT_HOST_TAG="darwin-x86_64" ;;
  *)
    echo "Unsupported host: $(uname -s) (expected Linux or macOS)." >&2
    exit 1
    ;;
esac
NDK_HOST_TAG="${ANDROID_NDK_HOST_TAG:-$DEFAULT_HOST_TAG}"
TOOLCHAIN="$NDK/toolchains/llvm/prebuilt/$NDK_HOST_TAG"
if [[ ! -d "$TOOLCHAIN" ]]; then
  echo "NDK LLVM toolchain not found: $TOOLCHAIN" >&2
  exit 1
fi

export ANDROID_NDK_HOME="$NDK"
export ANDROID_NDK_ROOT="$NDK"
export PATH="$TOOLCHAIN/bin:$PATH"

# --- Rust cross-compilation environment (read-aloud) -------------------------
# The C ABI library is a Rust cdylib; CMake only needs cargo in PATH plus the
# usual cc-rs / cargo target variables. cargo-ndk also works (it reads
# ANDROID_NDK_HOME); these exports make a plain `cargo build --target
# aarch64-linux-android` work too.
API_LEVEL="${ANDROID_API_LEVEL:-24}"
ANDROID_API_LEVEL="$API_LEVEL"
export ANDROID_API_LEVEL
ANDROID_CLANG="$TOOLCHAIN/bin/aarch64-linux-android${API_LEVEL}-clang"
export CC_aarch64_linux_android="$ANDROID_CLANG"
export CXX_aarch64_linux_android="${ANDROID_CLANG}++"
export AR_aarch64_linux_android="$TOOLCHAIN/bin/llvm-ar"
export CARGO_TARGET_AARCH64_LINUX_ANDROID_LINKER="$ANDROID_CLANG"
export CC_armv7_linux_androideabi="$TOOLCHAIN/bin/armv7a-linux-androideabi${API_LEVEL}-clang"
export AR_armv7_linux_androideabi="$TOOLCHAIN/bin/llvm-ar"
export CARGO_TARGET_ARMV7_LINUX_ANDROIDEABI_LINKER="$TOOLCHAIN/bin/armv7a-linux-androideabi${API_LEVEL}-clang"

# Android 15+/17 requires 16 KB-compatible ELF load segments. CMake sets this
# for the C++ library (CMakeLists.txt); the Rust cdylib needs it separately or
# verify-apk.sh will reject the APK.
READ_ALOUD_16K_RUSTFLAGS="-C link-arg=-Wl,-z,max-page-size=16384 -C link-arg=-Wl,-z,common-page-size=16384"
export CARGO_TARGET_AARCH64_LINUX_ANDROID_RUSTFLAGS="$READ_ALOUD_16K_RUSTFLAGS"
export CARGO_TARGET_ARMV7_LINUX_ANDROIDEABI_RUSTFLAGS="$READ_ALOUD_16K_RUSTFLAGS"

VULKAN_MODE="$(chatvv_vulkan_mode AUTO)"
if [[ "$VULKAN_MODE" == "ON" ]]; then
  command -v glslc >/dev/null || {
    echo "CHATVV_VULKAN=ON but glslc is not in PATH." >&2
    echo "Android CI installs it on the Linux runner (apt: glslc libvulkan-dev spirv-headers)." >&2
    exit 1
  }
fi

VCPKG="${VCPKG_ROOT:-$ROOT/.vcpkg}"
TRIPLET=arm64-android

if [[ ! -x "$VCPKG/vcpkg" ]]; then
  git clone --depth 1 https://github.com/microsoft/vcpkg.git "$VCPKG"
  "$VCPKG/bootstrap-vcpkg.sh" -disableMetrics
fi

export VCPKG_ROOT="$VCPKG"

if [[ ! -f "$ROOT/.vcpkg_installed/$TRIPLET/lib/libcurl.a" ]]; then
  (cd "$VCPKG" && ./vcpkg install --classic --triplet "$TRIPLET" \
    --x-install-root="$ROOT/.vcpkg_installed" "curl[openssl,websockets]" sqlite3)
fi

CMAKE_EXTRA_ARGS=()
if [[ -n "${ANDROID_VULKAN_CMAKE_ARGS:-}" ]]; then
  read -r -a CMAKE_EXTRA_ARGS <<< "$ANDROID_VULKAN_CMAKE_ARGS"
fi

# Vulkan cross-compile needs both sides of the SDK:
#   * the NDK sysroot provides target vulkan.h + libvulkan.so for arm64;
#   * but ggml's Vulkan backend also uses C++ bindings (vulkan/vulkan.hpp),
#     which the NDK does not ship. Use the host SDK headers (API-compatible)
#     and link the target NDK libvulkan.so explicitly.
if [[ "$VULKAN_MODE" != "OFF" ]]; then
  VULKAN_TARGET_LIB="$NDK/toolchains/llvm/prebuilt/$NDK_HOST_TAG/sysroot/usr/lib/aarch64-linux-android/${API_LEVEL}/libvulkan.so"
  if [[ -f "$VULKAN_TARGET_LIB" ]]; then
    has_vulkan_lib_arg=0
    for arg in ${CMAKE_EXTRA_ARGS[@]+"${CMAKE_EXTRA_ARGS[@]}"}; do
      case "$arg" in -DVulkan_LIBRARY=*) has_vulkan_lib_arg=1 ;; esac
    done
    if [[ "$has_vulkan_lib_arg" == "0" ]]; then
      # Do NOT pass /usr/include directly: CMake drops it as an "implicit" dir,
      # and with --sysroot it is not searched, so vulkan.hpp would be missing.
      # Use a tiny staging dir that only contains the vulkan/ headers.
      VULKAN_HOST_INCLUDE="${ANDROID_VULKAN_INCLUDE_DIR:-}"
      if [[ -z "$VULKAN_HOST_INCLUDE" ]]; then
        VULKAN_HOST_INCLUDE="$ROOT/build/android-vulkan-headers"
        mkdir -p "$VULKAN_HOST_INCLUDE"
        ln -sfn /usr/include/vulkan "$VULKAN_HOST_INCLUDE/vulkan"
        # vulkan_core.h includes vk_video/vulkan_video_codec_*.h
        if [[ -d /usr/include/vk_video ]]; then
          ln -sfn /usr/include/vk_video "$VULKAN_HOST_INCLUDE/vk_video"
        fi
        # ggml-vulkan-types.h includes spirv/unified1/spirv.hpp
        if [[ -d /usr/include/spirv ]]; then
          ln -sfn /usr/include/spirv "$VULKAN_HOST_INCLUDE/spirv"
        fi
      fi
      CMAKE_EXTRA_ARGS+=("-DVulkan_INCLUDE_DIR=$VULKAN_HOST_INCLUDE")
      CMAKE_EXTRA_ARGS+=("-DVulkan_LIBRARY=$VULKAN_TARGET_LIB")
    fi
  else
    echo "warning: target libvulkan.so not found at $VULKAN_TARGET_LIB; relying on ggml FindVulkan defaults." >&2
  fi
fi

cmake --preset android-arm64 \
  "-DCHATVV_VULKAN=$VULKAN_MODE" \
  "-DCHATVV_READ_ALOUD_LINKAGE=${CHATVV_READ_ALOUD_LINKAGE:-shared}" \
  ${CMAKE_EXTRA_ARGS[@]+"${CMAKE_EXTRA_ARGS[@]}"} \
  "$@"
cmake --build build/android-arm64 --target chatvv_ffi -j"$(nproc)"

BUILD_DIR="$ROOT/build/android-arm64"
DEST="$ROOT/app/android/app/src/main/jniLibs/arm64-v8a"
STRIP="$TOOLCHAIN/bin/llvm-strip"
READELF="$TOOLCHAIN/bin/llvm-readelf"
mkdir -p "$DEST"

cp "$BUILD_DIR/libchatvv_ffi.so" "$DEST/libchatvv_ffi.so"
"$STRIP" --strip-unneeded "$DEST/libchatvv_ffi.so"
cp "$TOOLCHAIN/sysroot/usr/lib/aarch64-linux-android/libc++_shared.so" \
  "$DEST/libc++_shared.so"

# read-aloud: cmake/readaloud.cmake stages it in <build>/read_aloud/lib/; it must be
# distributed next to the FFI library on Android (explicit CHATVV_READ_ALOUD_LINKAGE=shared).
if [[ "${CHATVV_SKIP_READ_ALOUD:-0}" != "1" ]]; then
  if READ_ALOUD_LIB="$(chatvv_find_read_aloud "$BUILD_DIR" "$ROOT" libread_aloud.so)"; then
    cp "$READ_ALOUD_LIB" "$DEST/libread_aloud.so"
    "$STRIP" --strip-unneeded "$DEST/libread_aloud.so"
    chatvv_require_16k_align "$DEST/libread_aloud.so" "$READELF" "libread_aloud.so"
  else
    exit 1
  fi
else
  echo "CHATVV_SKIP_READ_ALOUD=1: skipping libread_aloud.so staging" >&2
fi

chatvv_require_16k_align "$DEST/libchatvv_ffi.so" "$READELF" "libchatvv_ffi.so"
echo "staged: $DEST/libchatvv_ffi.so"

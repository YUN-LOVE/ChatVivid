#!/usr/bin/env bash
# Build and package the Linux desktop app (Flutter bundle + libchatvv_ffi.so).
#
# Canonical location. scripts/package-desktop-linux.sh is a compatibility shim.
#
# Environment:
#   CHATVV_VULKAN   AUTO (default), ON (CI), OFF
#
# Requirements: clang, cmake, ninja, pkg-config, GTK3 dev headers, Flutter,
# Rust (read-aloud is linked into libchatvv_ffi), and a Vulkan SDK when
# CHATVV_VULKAN=ON (CI uses libvulkan-dev + glslc + spirv-headers).
# The packaged bundle depends on the *runtime* Vulkan loader (libvulkan.so.1)
# from the target machine's GPU driver; it is not bundled.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
# shellcheck source=../common/build-lib.sh
source "$ROOT/platforms/common/build-lib.sh"

cd "$ROOT"
VULKAN_ARG="$(chatvv_vulkan_configure_arg AUTO)"
cmake --preset release "$VULKAN_ARG"
cmake --build build/release --target chatvv_ffi -j"$(nproc)"

chatvv_versions "$ROOT"
cd "$ROOT/app"
flutter pub get
dart run rive_native:setup --verbose -p linux
flutter build linux --release \
  --build-name="$CHATVV_VERSION" --build-number="$CHATVV_BUILD_NUMBER" \
  --dart-define=APP_VERSION="$CHATVV_VERSION" \
  --dart-define=BUILD_NUMBER="$CHATVV_BUILD_NUMBER" \
  --dart-define=BUILD_COMMIT="$CHATVV_COMMIT_SHA"

BUNDLE="$ROOT/app/build/linux/x64/release/bundle"
mkdir -p "$BUNDLE/lib" "$ROOT/artifacts"
cp "$ROOT/build/release/libchatvv_ffi.so" "$BUNDLE/lib/libchatvv_ffi.so"
# read-aloud is linked statically into libchatvv_ffi on desktop, so there is no
# extra cdylib to distribute here.
tar -C "$(dirname "$BUNDLE")" -czf "$ROOT/artifacts/chatvv-linux-x64.tar.gz" "$(basename "$BUNDLE")"
echo "packaged $ROOT/artifacts/chatvv-linux-x64.tar.gz"

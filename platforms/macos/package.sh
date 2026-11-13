#!/usr/bin/env bash
# Build and package the macOS desktop app (Flutter bundle + libchatvv_ffi.dylib).
#
# Canonical location. scripts/package-desktop-macos.sh is a compatibility shim.
#
# Apple targets keep the CPU/Metal backend: CHATVV_VULKAN defaults to OFF and
# the CMake module rejects ON on Apple (MoltenVK is not wired up yet).
#
# Environment:
#   CHATVV_VULKAN   OFF (default on Apple; ON is rejected by the CMake module)
#
# Requirements: Xcode command line tools, cmake, ninja, Homebrew curl, Flutter,
# Rust (read-aloud is linked statically into libchatvv_ffi).
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
# shellcheck source=../common/build-lib.sh
source "$ROOT/platforms/common/build-lib.sh"

cd "$ROOT"
CURL_ROOT="$(brew --prefix curl)"
VULKAN_ARG="$(chatvv_vulkan_configure_arg OFF)"
cmake --preset macos-arm64 -DCURL_ROOT="$CURL_ROOT" "$VULKAN_ARG"
cmake --build build/macos-arm64 --target chatvv_ffi -j"$(sysctl -n hw.ncpu)"

chatvv_versions "$ROOT"
cd "$ROOT/app"
flutter pub get
dart run rive_native:setup --verbose -p macos
flutter build macos --release \
  --build-name="$CHATVV_VERSION" --build-number="$CHATVV_BUILD_NUMBER" \
  --dart-define=APP_VERSION="$CHATVV_VERSION" \
  --dart-define=BUILD_NUMBER="$CHATVV_BUILD_NUMBER" \
  --dart-define=BUILD_COMMIT="$CHATVV_COMMIT_SHA"

APP="$ROOT/app/build/macos/Build/Products/Release/chatvv.app"
mkdir -p "$APP/Contents/Frameworks" "$ROOT/artifacts"
cp "$ROOT/build/macos-arm64/libchatvv_ffi.dylib" "$APP/Contents/Frameworks/"
codesign --force --deep --sign - "$APP"
ditto -c -k --sequesterRsrc --keepParent "$APP" "$ROOT/artifacts/chatvv-macos-arm64.zip"
echo "packaged $ROOT/artifacts/chatvv-macos-arm64.zip"

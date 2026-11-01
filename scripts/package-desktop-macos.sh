#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"
CURL_ROOT="$(brew --prefix curl)"
cmake --preset macos-arm64 -DCURL_ROOT="$CURL_ROOT"
cmake --build build/macos-arm64 --target chatvv_ffi -j"$(sysctl -n hw.ncpu)"
cd app
flutter pub get
COMMIT_COUNT=$(git -C "$ROOT" rev-list --count HEAD)
COMMIT_SHA=$(git -C "$ROOT" rev-parse --short HEAD)
VERSION="0.1.${COMMIT_COUNT}"
flutter build macos --release \
  --build-name="$VERSION" --build-number="$COMMIT_COUNT" \
  --dart-define=APP_VERSION="$VERSION" \
  --dart-define=BUILD_NUMBER="$COMMIT_COUNT" \
  --dart-define=BUILD_COMMIT="$COMMIT_SHA"
APP="$ROOT/app/build/macos/Build/Products/Release/chatvv.app"
mkdir -p "$APP/Contents/Frameworks" "$ROOT/artifacts"
cp "$ROOT/build/macos-arm64/libchatvv_ffi.dylib" "$APP/Contents/Frameworks/"
codesign --force --deep --sign - "$APP"
ditto -c -k --sequesterRsrc --keepParent "$APP" "$ROOT/artifacts/chatvv-macos-arm64.zip"
echo "packaged $ROOT/artifacts/chatvv-macos-arm64.zip"

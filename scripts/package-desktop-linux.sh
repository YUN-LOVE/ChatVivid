#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"
cmake --preset release
cmake --build build/release --target chatvv_ffi -j"$(nproc)"
cd app
flutter pub get
dart run rive_native:setup --verbose -p linux
COMMIT_COUNT=$(git -C "$ROOT" rev-list --count HEAD)
COMMIT_SHA=$(git -C "$ROOT" rev-parse --short HEAD)
VERSION="0.1.${COMMIT_COUNT}"
flutter build linux --release \
  --build-name="$VERSION" --build-number="$COMMIT_COUNT" \
  --dart-define=APP_VERSION="$VERSION" \
  --dart-define=BUILD_NUMBER="$COMMIT_COUNT" \
  --dart-define=BUILD_COMMIT="$COMMIT_SHA"
BUNDLE="$ROOT/app/build/linux/x64/release/bundle"
mkdir -p "$BUNDLE/lib" "$ROOT/artifacts"
cp "$ROOT/build/release/libchatvv_ffi.so" "$BUNDLE/lib/libchatvv_ffi.so"
tar -C "$(dirname "$BUNDLE")" -czf "$ROOT/artifacts/chatvv-linux-x64.tar.gz" "$(basename "$BUNDLE")"
echo "packaged $ROOT/artifacts/chatvv-linux-x64.tar.gz"

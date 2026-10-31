#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"
cmake --preset release
cmake --build build/release --target chatvv_ffi -j"$(nproc)"
cd app
flutter pub get
flutter build linux --release
BUNDLE="$ROOT/app/build/linux/x64/release/bundle"
mkdir -p "$BUNDLE/lib" "$ROOT/artifacts"
cp "$ROOT/build/release/libchatvv_ffi.so" "$BUNDLE/lib/libchatvv_ffi.so"
tar -C "$(dirname "$BUNDLE")" -czf "$ROOT/artifacts/chatvv-linux-x64.tar.gz" "$(basename "$BUNDLE")"
echo "packaged $ROOT/artifacts/chatvv-linux-x64.tar.gz"

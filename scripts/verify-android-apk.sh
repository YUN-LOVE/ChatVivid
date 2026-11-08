#!/usr/bin/env bash
# Verify an APK is 16 KB page aligned and signed.
set -euo pipefail
APK="${1:?usage: verify-android-apk.sh <apk>}"
SDK="${ANDROID_HOME:-${ANDROID_SDK_ROOT:-$HOME/Android/Sdk}}"
BUILD_TOOLS="${ANDROID_BUILD_TOOLS:-$SDK/build-tools/36.0.0}"
ZIPALIGN="$BUILD_TOOLS/zipalign"
APKSIGNER="$BUILD_TOOLS/apksigner"
[[ -x "$ZIPALIGN" ]] || { echo "missing $ZIPALIGN" >&2; exit 2; }
[[ -x "$APKSIGNER" ]] || { echo "missing $APKSIGNER" >&2; exit 2; }

echo "== 16 KB zip alignment =="
"$ZIPALIGN" -c -P 16 -v 4 "$APK" >/dev/null

echo "== APK signature =="
"$APKSIGNER" verify --verbose --print-certs "$APK"

echo "== native ELF LOAD alignment =="
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
unzip -q "$APK" 'lib/arm64-v8a/*.so' -d "$TMP"
READELF="$SDK/ndk/27.2.12479018/toolchains/llvm/prebuilt/linux-x86_64/bin/llvm-readelf"
for so in "$TMP"/lib/arm64-v8a/*.so; do
  align="$("$READELF" -l "$so" | awk '/LOAD/{print $NF; exit}')"
  printf '%-32s LOAD align %s\n' "$(basename "$so")" "$align"
  case "$align" in
    0x4000|0x10000) ;;
    *) echo "ERROR: $(basename "$so") is not 16 KB compatible" >&2; exit 1 ;;
  esac
done

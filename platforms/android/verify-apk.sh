#!/usr/bin/env bash
# Verify an Android APK is 16 KB page-size compatible and signed.
#
# Canonical location. scripts/verify-android-apk.sh is a compatibility shim.
#
# Usage: platforms/android/verify-apk.sh <apk>
#
# Environment:
#   ANDROID_CERT_SHA256               optional expected signer cert SHA-256
#                                     (hex, colons optional); fails on mismatch
#   ANDROID_HOME / ANDROID_SDK_ROOT   SDK discovery
#   ANDROID_NDK_HOME                  NDK discovery for llvm-readelf
#   ANDROID_BUILD_TOOLS               build-tools directory (default 36.0.0)
set -euo pipefail

APK="${1:?usage: platforms/android/verify-apk.sh <apk>}"
SDK="${ANDROID_HOME:-${ANDROID_SDK_ROOT:-$HOME/Android/Sdk}}"
BUILD_TOOLS="${ANDROID_BUILD_TOOLS:-$SDK/build-tools/36.0.0}"
NDK="${ANDROID_NDK_HOME:-$SDK/ndk/27.2.12479018}"
ZIPALIGN="$BUILD_TOOLS/zipalign"
APKSIGNER="$BUILD_TOOLS/apksigner"
READELF="$NDK/toolchains/llvm/prebuilt/${ANDROID_NDK_HOST_TAG:-linux-x86_64}/bin/llvm-readelf"
[[ -x "$ZIPALIGN" ]] || { echo "missing $ZIPALIGN" >&2; exit 2; }
[[ -x "$APKSIGNER" ]] || { echo "missing $APKSIGNER" >&2; exit 2; }
[[ -x "$READELF" ]] || { echo "missing $READELF" >&2; exit 2; }

echo "== 16 KB zip alignment =="
"$ZIPALIGN" -c -P 16 -v 4 "$APK" >/dev/null

echo "== APK signature =="
SIGNER_INFO="$("$APKSIGNER" verify --verbose --print-certs "$APK")"
echo "$SIGNER_INFO"
if [[ -n "${ANDROID_CERT_SHA256:-}" ]]; then
  ACTUAL="$(
    printf '%s\n' "$SIGNER_INFO" \
      | sed -n 's/.*SHA-256 digest: *//p' \
      | head -1 \
      | tr -d ':' | tr '[:upper:]' '[:lower:]'
  )"
  EXPECTED="$(printf '%s' "$ANDROID_CERT_SHA256" | tr -d ':' | tr '[:upper:]' '[:lower:]')"
  if [[ -z "$ACTUAL" ]]; then
    echo "ERROR: could not read the signer certificate SHA-256" >&2
    exit 1
  fi
  if [[ "$ACTUAL" != "$EXPECTED" ]]; then
    echo "ERROR: APK is not signed with the unified chatvv key" >&2
    echo "  expected: $EXPECTED" >&2
    echo "  actual  : $ACTUAL" >&2
    exit 1
  fi
  echo "signer matches ANDROID_CERT_SHA256 ($EXPECTED)"
fi

echo "== native ELF LOAD alignment =="
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
unzip -q "$APK" 'lib/arm64-v8a/*.so' -d "$TMP"
for so in "$TMP"/lib/arm64-v8a/*.so; do
  # No early awk exit: with `set -o pipefail` readelf would die with SIGPIPE.
  align="$("$READELF" -l "$so" \
    | awk '/LOAD/ && !align {align=$NF} END {if (align == "") exit 1; print align}')"
  printf '%-32s LOAD align %s\n' "$(basename "$so")" "$align"
  case "$align" in
    0x4000|0x10000) ;;
    *) echo "ERROR: $(basename "$so") is not 16 KB compatible" >&2; exit 1 ;;
  esac
done

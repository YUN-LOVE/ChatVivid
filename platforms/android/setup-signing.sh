#!/usr/bin/env bash
# Materialize the unified Android signing material for a build.
#
# Signed chatvv Android builds require one keystore for every artifact (debug and
# release, local and CI). This script prefers an existing local key.properties and
# otherwise decodes the CI secret:
#
#   ANDROID_KEYSTORE_BASE64     base64 of the keystore (.jks), required in CI
#   ANDROID_KEYSTORE_PASSWORD   keystore password
#   ANDROID_KEY_ALIAS           key alias (default: chatvv)
#   ANDROID_KEY_PASSWORD        key password (PKCS12: usually same as store password)
#
# Usage:
#   platforms/android/setup-signing.sh              # best effort (missing key -> warning)
#   platforms/android/setup-signing.sh --required   # CI: fail if signing is not configured
#
# The keystore is written to app/android/chatvv-release.jks and key.properties to
# app/android/key.properties; both are gitignored. Generate the keystore once with
# platforms/android/make-keystore.sh (see docs/android-signing.md).
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
APP_ANDROID="$ROOT/app/android"
KEYSTORE="$APP_ANDROID/chatvv-release.jks"
PROPS="$APP_ANDROID/key.properties"

REQUIRED=0
for arg in "$@"; do
  case "$arg" in
    --required) REQUIRED=1 ;;
    -h|--help) sed -n '2,22p' "${BASH_SOURCE[0]}"; exit 0 ;;
    *) echo "unknown argument: $arg" >&2; exit 2 ;;
  esac
done

fail() {
  cat >&2 <<EOF
error: $1

Android builds must be signed with the unified chatvv key.
Configure it once, then re-run:
  platforms/android/make-keystore.sh          # prints base64 + gh secret commands
See docs/android-signing.md for the full setup.
EOF
  exit 1
}

print_fingerprint() {
  local keystore="$1" password="$2" alias="$3"
  if command -v keytool >/dev/null 2>&1; then
    keytool -list -v -keystore "$keystore" -storepass "$password" -alias "$alias" 2>/dev/null \
      | awk -F': ' '/SHA256:/{print $2; exit}' | tr -d ':' | tr '[:upper:]' '[:lower:]'
  fi
}

if [[ -n "${ANDROID_KEYSTORE_BASE64:-}" ]]; then
  : "${ANDROID_KEYSTORE_PASSWORD:?ANDROID_KEYSTORE_PASSWORD is required when ANDROID_KEYSTORE_BASE64 is set}"
  : "${ANDROID_KEY_PASSWORD:?ANDROID_KEY_PASSWORD is required when ANDROID_KEYSTORE_BASE64 is set}"
  ALIAS="${ANDROID_KEY_ALIAS:-chatvv}"
  echo "== materializing Android signing key from CI secret =="
  umask 077
  printf '%s' "$ANDROID_KEYSTORE_BASE64" | base64 -d >"$KEYSTORE" || fail "ANDROID_KEYSTORE_BASE64 is not valid base64"
  command -v keytool >/dev/null 2>&1 || fail "keytool not found (JDK 17 required)"
  keytool -list -keystore "$KEYSTORE" -storepass "$ANDROID_KEYSTORE_PASSWORD" -alias "$ALIAS" >/dev/null 2>&1 \
    || fail "keystore could not be opened with ANDROID_KEYSTORE_PASSWORD / ANDROID_KEY_ALIAS=$ALIAS"
  cat >"$PROPS" <<EOF
storeFile=../chatvv-release.jks
storePassword=$(printf '%s' "$ANDROID_KEYSTORE_PASSWORD" | sed 's/\\/\\\\/g')
keyAlias=$ALIAS
keyPassword=$(printf '%s' "$ANDROID_KEY_PASSWORD" | sed 's/\\/\\\\/g')
EOF
  chmod 600 "$KEYSTORE" "$PROPS"
  FP="$(print_fingerprint "$KEYSTORE" "$ANDROID_KEYSTORE_PASSWORD" "$ALIAS")"
  echo "  keystore   : app/android/chatvv-release.jks"
  echo "  key alias  : $ALIAS"
  echo "  cert SHA-256: ${FP:-<unknown>}"
  if [[ -n "${ANDROID_CERT_SHA256:-}" && -n "$FP" ]]; then
    expected="$(printf '%s' "$ANDROID_CERT_SHA256" | tr -d ':' | tr '[:upper:]' '[:lower:]')"
    if [[ "$expected" != "$FP" ]]; then
      fail "certificate fingerprint mismatch: expected $expected, got $FP"
    fi
    echo "  fingerprint matches ANDROID_CERT_SHA256"
  fi
  exit 0
fi

if [[ -f "$PROPS" ]]; then
  echo "== using existing app/android/key.properties =="
  STORE_FILE="$(sed -n 's/^storeFile=//p' "$PROPS" | head -1)"
  STORE_PASSWORD="$(sed -n 's/^storePassword=//p' "$PROPS" | head -1)"
  KEY_ALIAS="$(sed -n 's/^keyAlias=//p' "$PROPS" | head -1)"
  # Gradle resolves storeFile relative to app/android/app.
  STORE_ABS="$APP_ANDROID/app/$STORE_FILE"
  [[ -f "$STORE_ABS" ]] || STORE_ABS="$APP_ANDROID/$STORE_FILE"
  if [[ -f "$STORE_ABS" ]]; then
    FP="$(print_fingerprint "$STORE_ABS" "$STORE_PASSWORD" "$KEY_ALIAS")"
    echo "  keystore    : ${STORE_ABS#$ROOT/}"
    echo "  key alias   : $KEY_ALIAS"
    echo "  cert SHA-256: ${FP:-<unknown>}"
    exit 0
  fi
  echo "warning: key.properties exists but its keystore was not found ($STORE_FILE)" >&2
fi

if [[ "$REQUIRED" == "1" ]]; then
  fail "no Android signing key configured (ANDROID_KEYSTORE_BASE64 secret missing)"
fi

cat >&2 <<'EOF'
warning: no Android signing key configured.
         Gradle will sign with the throwaway debug key: the APK installs, but it is
         not the unified chatvv signature and cannot replace builds from other
         machines/CI. Run platforms/android/make-keystore.sh to set one up.
EOF

#!/usr/bin/env bash
# Generate the *unified* chatvv Android signing keystore.
#
# Every chatvv Android artifact (debug and release, CI and local) is signed with
# this one key, so builds can replace each other on a device and keep user data.
# The keystore and key.properties are gitignored — back the keystore up somewhere
# safe: if it is lost you cannot update an already installed app (or Play upload)
# with a different key.
#
# Usage:
#   platforms/android/make-keystore.sh                 # generate ./app/android/chatvv-release.jks
#   platforms/android/make-keystore.sh --force         # rotate (breaks existing installs!)
#
# Environment:
#   CHATVV_KEY_ALIAS            key alias                (default: chatvv)
#   CHATVV_KEYSTORE_PATH        output keystore path     (default: app/android/chatvv-release.jks)
#   CHATVV_KEYSTORE_PASSWORD    keystore password        (default: generated, printed once)
#   CHATVV_KEY_DNAME            X.509 distinguished name (default: CN=chatvv, O=chatvv, C=CN)
#   CHATVV_KEY_VALIDITY_DAYS    validity in days         (default: 10000 ≈ 27 years)
#   JAVA_HOME / keytool         JDK 17 is enough
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
FORCE=0
for arg in "$@"; do
  case "$arg" in
    --force) FORCE=1 ;;
    -h|--help) sed -n '2,20p' "${BASH_SOURCE[0]}"; exit 0 ;;
    *) echo "unknown argument: $arg" >&2; exit 2 ;;
  esac
done

ALIAS="${CHATVV_KEY_ALIAS:-chatvv}"
KEYSTORE="${CHATVV_KEYSTORE_PATH:-$ROOT/app/android/chatvv-release.jks}"
DNAME="${CHATVV_KEY_DNAME:-CN=chatvv, O=chatvv, C=CN}"
VALIDITY="${CHATVV_KEY_VALIDITY_DAYS:-10000}"

command -v keytool >/dev/null 2>&1 || {
  echo "keytool not found. Install JDK 17 (Arch: pacman -S jdk17-openjdk) or set JAVA_HOME." >&2
  exit 2
}

if [[ -e "$KEYSTORE" && "$FORCE" != "1" ]]; then
  echo "keystore already exists: $KEYSTORE" >&2
  echo "Refusing to overwrite (rotation invalidates over-the-air updates of installed apps)." >&2
  echo "Pass --force only if you really want a new identity." >&2
  exit 2
fi

PASSWORD="${CHATVV_KEYSTORE_PASSWORD:-}"
GENERATED=0
if [[ -z "$PASSWORD" ]]; then
  PASSWORD="$(head -c 32 /dev/urandom | base64 | tr -d '/+=\n' | cut -c1-32)"
  GENERATED=1
fi
if [[ ${#PASSWORD} -lt 8 ]]; then
  echo "CHATVV_KEYSTORE_PASSWORD must be at least 8 characters." >&2
  exit 2
fi

mkdir -p "$(dirname "$KEYSTORE")"
umask 077
set +o history 2>/dev/null || true

echo "== generating keystore =="
echo "  path : $KEYSTORE"
echo "  alias: $ALIAS"
keytool -genkeypair -v \
  -keystore "$KEYSTORE" \
  -storetype PKCS12 \
  -storepass "$PASSWORD" \
  -keypass "$PASSWORD" \
  -alias "$ALIAS" \
  -keyalg RSA \
  -keysize 4096 \
  -validity "$VALIDITY" \
  -dname "$DNAME" >/dev/null

FINGERPRINT="$(
  keytool -list -v -keystore "$KEYSTORE" -storepass "$PASSWORD" -alias "$ALIAS" 2>/dev/null \
    | awk -F': ' '/SHA256:/{print $2; exit}' \
    | tr -d ':' | tr '[:upper:]' '[:lower:]'
)"
BASE64="$(base64 -w0 "$KEYSTORE" 2>/dev/null || base64 "$KEYSTORE" | tr -d '\n')"
B64_FILE="${KEYSTORE%.jks}.jks.b64"
printf '%s' "$BASE64" >"$B64_FILE"
chmod 600 "$KEYSTORE" "$B64_FILE"

cat <<EOF

== done ==
keystore          : $KEYSTORE
password          : $PASSWORD
alias             : $ALIAS
cert SHA-256      : $FINGERPRINT
base64 file       : $B64_FILE
EOF
if [[ "$GENERATED" == "1" ]]; then
  echo "NOTE: the password above was generated once. Store it with the keystore."
fi
cat <<EOF

Next steps (GitHub Actions secrets for the chatvv repository):
  gh secret set ANDROID_KEYSTORE_BASE64 < "$B64_FILE"
  gh secret set ANDROID_KEYSTORE_PASSWORD --body "$PASSWORD"
  gh secret set ANDROID_KEY_ALIAS          --body "$ALIAS"
  gh secret set ANDROID_KEY_PASSWORD       --body "$PASSWORD"
  gh secret set ANDROID_CERT_SHA256        --body "$FINGERPRINT"

Or paste the values in Settings -> Secrets and variables -> Actions.

Local builds: create app/android/key.properties (or run
  platforms/android/setup-signing.sh
after exporting the same ANDROID_KEYSTORE_BASE64/password variables).

Keep $KEYSTORE and $B64_FILE out of git (both gitignored) and keep a backup:
losing this key means installed apps can no longer be updated.
EOF

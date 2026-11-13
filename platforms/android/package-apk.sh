#!/usr/bin/env bash
# Build the Flutter Android artifact(s), verify 16 KB page-size compatibility
# and stage everything under artifacts/.
#
# Canonical location; invoked by .github/workflows/{ci,release}.yml.
#
# Usage:
#   CHATVV_APK_MODE=debug   platforms/android/package-apk.sh   # CI debug APK
#   CHATVV_APK_MODE=release platforms/android/package-apk.sh   # release APK + AAB
#
# Signing: debug and release are both signed with the unified chatvv key. CI
# provides ANDROID_KEYSTORE_BASE64 / ANDROID_KEYSTORE_PASSWORD / ANDROID_KEY_ALIAS /
# ANDROID_KEY_PASSWORD (and optionally ANDROID_CERT_SHA256) and signing is
# mandatory; locally run platforms/android/make-keystore.sh once. See
# docs/android-signing.md.
#
# Prerequisites: jniLibs already staged by platforms/android/build-ffi.sh
# (Android SDK/NDK + JDK 17 available).
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
# shellcheck source=../common/build-lib.sh
source "$ROOT/platforms/common/build-lib.sh"

# Unified signing (debug and release use the same key). In CI the keystore comes
# from the ANDROID_KEYSTORE_BASE64 secret and is mandatory; locally it uses
# app/android/key.properties when present, otherwise Gradle's debug key.
if [[ -n "${ANDROID_KEYSTORE_BASE64:-}" || -n "${GITHUB_ACTIONS:-}" ]]; then
  "$ROOT/platforms/android/setup-signing.sh" --required
else
  "$ROOT/platforms/android/setup-signing.sh"
fi

MODE="${CHATVV_APK_MODE:-debug}"
case "$MODE" in
  debug | release) ;;
  *)
    echo "CHATVV_APK_MODE must be 'debug' or 'release' (got '$MODE')." >&2
    exit 2
    ;;
esac

chatvv_versions "$ROOT"
DART_DEFINES=(
  "--build-name=$CHATVV_VERSION"
  "--build-number=$CHATVV_BUILD_NUMBER"
  "--dart-define=APP_VERSION=$CHATVV_VERSION"
  "--dart-define=BUILD_NUMBER=$CHATVV_BUILD_NUMBER"
  "--dart-define=BUILD_COMMIT=$CHATVV_COMMIT_SHA"
)

cd "$ROOT/app"
flutter pub get
dart run rive_native:setup --verbose -p android

# rive_native's Android debug artifacts ship the Khronos Vulkan validation layer
# (~15 MB). The app never requests it, but the loader registers it as a global
# layer and it bloats the APK. Drop it from the build tree before Gradle runs.
while IFS= read -r layer; do
  echo "removing bundled Vulkan validation layer: $layer"
  rm -f "$layer"
done < <(find "$ROOT/app/build" "$HOME/.pub-cache/hosted" \
  -name 'libVkLayer_khronos_validation.so' 2>/dev/null || true)

APK_DIR="build/app/outputs/flutter-apk"
ARTIFACTS="$ROOT/artifacts"
mkdir -p "$ARTIFACTS"

if [[ "$MODE" == "debug" ]]; then
  flutter build apk --debug --target-platform android-arm64 "${DART_DEFINES[@]}"
  APK="$APK_DIR/app-debug.apk"
  "$ROOT/platforms/android/verify-apk.sh" "$APK"
  cp "$APK" "$ARTIFACTS/chatvv-app-android-debug.apk"
  (cd "$ARTIFACTS" && sha256sum chatvv-app-android-debug.apk >chatvv-app-android-debug.sha256)
else
  flutter build apk --release --target-platform android-arm64 "${DART_DEFINES[@]}"
  flutter build appbundle --release --target-platform android-arm64 "${DART_DEFINES[@]}"
  APK="$APK_DIR/app-release.apk"
  AAB="build/app/outputs/bundle/release/app-release.aab"
  "$ROOT/platforms/android/verify-apk.sh" "$APK"
  cp "$APK" "$ARTIFACTS/chatvv-app-android.apk"
  cp "$AAB" "$ARTIFACTS/chatvv-app-android.aab"
  (cd "$ARTIFACTS" && sha256sum chatvv-app-android.apk chatvv-app-android.aab >chatvv-app-android.sha256)
fi

echo "packaged $MODE android artifacts in $ARTIFACTS"

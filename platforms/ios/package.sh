#!/usr/bin/env bash
# Build the unsigned iOS app bundle (.ipa) for CI artifact upload.
#
# Canonical location; invoked by .github/workflows/release.yml only when the
# tag selects "ios". iOS is disabled by default because app/ios does not exist
# yet: the CI detect/parse-tag scripts only select ios once app/ios is
# scaffolded, and this script fails loudly instead of publishing junk.
#
# Enable later with:
#   cd app && flutter create --platforms=ios .
#   # then configure signing certs/profiles (not wired into CI yet)
#
# Requirements: macOS runner, Xcode, Flutter, CocoaPods, Rust aarch64-apple-ios.
# Output is unsigned (--no-codesign); internal QA only.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
# shellcheck source=../common/build-lib.sh
source "$ROOT/platforms/common/build-lib.sh"

if [[ ! -d "$ROOT/app/ios" ]]; then
  {
    echo "platforms/ios/package.sh: app/ios 不存在，iOS 打包未启用。"
    echo "启用步骤: cd app && flutter create --platforms=ios ."
    echo "然后配置 Apple 签名证书/描述文件（CI secrets 尚未接入）。"
  } >&2
  exit 2
fi

chatvv_versions "$ROOT"
cd "$ROOT/app"
flutter pub get
dart run rive_native:setup --verbose -p ios
flutter build ios --release --no-codesign \
  --build-name="$CHATVV_VERSION" --build-number="$CHATVV_BUILD_NUMBER" \
  --dart-define=APP_VERSION="$CHATVV_VERSION" \
  --dart-define=BUILD_NUMBER="$CHATVV_BUILD_NUMBER" \
  --dart-define=BUILD_COMMIT="$CHATVV_COMMIT_SHA"

APP="$ROOT/app/build/ios/iphoneos/Runner.app"
STAGE="$ROOT/artifacts"
mkdir -p "$STAGE/Payload"
rm -rf "$STAGE/Payload/Runner.app"
cp -R "$APP" "$STAGE/Payload/Runner.app"
(cd "$STAGE" && zip -qry "chatvv-app-ios-unsigned.ipa" Payload && rm -rf Payload)
echo "packaged $STAGE/chatvv-app-ios-unsigned.ipa (unsigned)"

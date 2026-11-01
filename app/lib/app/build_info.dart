/// Build metadata injected by scripts/CI:
///   `--dart-define=APP_VERSION=0.1.<commit-count>`
///   `--dart-define=BUILD_NUMBER=<commit-count>`
///   `--dart-define=BUILD_COMMIT=<short-sha>`
const String appVersion = String.fromEnvironment(
  'APP_VERSION',
  defaultValue: '0.1.0-dev',
);
const String buildNumber = String.fromEnvironment(
  'BUILD_NUMBER',
  defaultValue: '0',
);
const String buildCommit = String.fromEnvironment(
  'BUILD_COMMIT',
  defaultValue: 'local',
);

String get buildLabel =>
    buildNumber == '0' ? appVersion : '$appVersion+$buildNumber';
String get commitLabel => buildCommit.isEmpty ? 'local' : buildCommit;

# Local patches vs pub.dev `live2d_flutter` 1.0.3

Upstream: <https://pub.dev/packages/live2d_flutter> 1.0.3 (published 2026-09-04),
repository <https://github.com/hunmer/flutter_live2d>.
Base archive: `https://pub.dev/api/archives/live2d_flutter-1.0.3.tar.gz`
(sha256 `b16d5d861661427609a692e311f469941526d33a32912616191b8ca5efc84332`).

This directory is the vendored copy used by `app/pubspec.yaml` (path dependency).
It is not published. Dart and native sources are byte-identical to the pub 1.0.3
archive; only the differences below exist.

## 1. Added: `android/src/main/assets/FrameworkShaders/` (36 files)

The Android renderer loads its GLSL sources through `AAssetManager`
(`Live2DPal::LoadFileAsBytes`), looking up `FrameworkShaders/VertShaderSrc*.vert`
and `FrameworkShaders/FragShaderSrc*.frag` inside the APK assets.
The pub 1.0.3 archive contains those shaders only as C++ sources under
`android/src/main/cpp/CubismFramework/Rendering/OpenGL/Shaders/StandardES/`
and does not package them as Android assets, so shader loading fails at runtime
and the model never renders. The added files are byte-identical copies of the
StandardES sources.

## 2. Changed: `pubspec.yaml` — removed the `flutter: assets:` block

1.0.3 declares

```yaml
flutter:
  assets:
    - assets/web/flutter_live2d_web.js
    - assets/web/shaders/
```

but neither path exists in the published archive. Any `flutter build` against
the pub package fails with:

```text
Error: unable to find directory entry in pubspec.yaml: .../assets/web/shaders/
Error detected in pubspec.yaml:
No file or variants found for asset: packages/live2d_flutter/assets/web/flutter_live2d_web.js.
```

Dropping the block makes the package buildable again. Consequence: the web
runtime JS is not bundled here, so the chatvv app does not build Live2D for web.

This is fine for chatvv: **web is not a target** (the old Web GalGame frontend is
archived under `archive/web-gal-game/`, and the app's `dart:ffi` Full-mode code
would need conditional imports anyway). The plugin still supports
Android/iOS/macOS/Windows, which is everything chatvv ships.

## 3. Dropped upstream content

`example/`, `test/`, `web_runtime/`, `artifacts/` and `build/` from the pub
archive are not vendored; they are not needed to build the plugin and `build/`
alone is ~106 MB of committed build output.

## Updating

Report the two packaging bugs upstream. Once a fixed version is published:
delete this directory, point `app/pubspec.yaml` back at
`live2d_flutter: ^x.y.z`, run `flutter pub get`, and verify
`flutter analyze` plus an Android device build (shader/model render).

## 3. Changed: Android native parameter overrides (`Live2DModel.{hpp,cpp}`)

`nativeSetParameter` used to write the Cubism parameter immediately, but
`nativeOnDrawFrame` then calls `LAppModel::Update()`, which runs the motion
manager, drag look-at, eye blink, expressions and physics — overwriting every
app-side value before the draw. On Android (and only here, because it is where
the render thread is implemented in this fork) this made `setParameter` a no-op:
gaze (`ParamEyeBallX/Y`, `ParamAngleX/Y/Z`), the mouth (`ParamMouthOpenY`) and
the tail/idle `Param*` overrides never showed.

Fix: `Live2DModel::SetParameterValue()` now records the value in
`_parameterOverrides`; `Live2DModel::Update()` applies those overrides after
motion/drag/eye-blink/expression/physics/pose and immediately before
`CubismModel::Update()`, so app-driven parameters win for that frame while the
idle motion still drives everything the app does not override.

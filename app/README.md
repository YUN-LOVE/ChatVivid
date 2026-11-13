# chatvv app (Flutter)

> 状态：**Full / Only client 双模式已接入**，Android 真机已验证 FFI（无后端、无 adb reverse）。
> 已实现：启动门、4 步引导、Full/Client 设置、顶部静态舞台、聊天、SSE/FFI。
> Live2D 插件实验在 `feature/live2d-stage` 分支，主分支仍使用静态舞台。
> 未实现：Live2D runtime、TTS、Windows 完整包、真实 DeepSeek 回归、平台安全存储。
> 当前环境 Flutter 3.44.2 / Dart 3.12.2；Android SDK 36。

## 运行

### Full（Android / Linux）

Android 先生成并打包内嵌 core：

```bash
./platforms/android/build-ffi.sh
cd app
flutter build apk --debug --target-platform android-arm64
```

App 首次启动进入引导，默认 Android 选 Full。Full **不需要** `chatvvd`，
也不需要 `adb reverse`。Linux 可 `LD_LIBRARY_PATH=../build/dev flutter run -d linux`。

### Only client

```bash
cd ..
./build/dev/chatvvd --config config/config.toml
```

后在引导/设置里选 Only client，填服务器地址。

### Linux 桌面

```bash
cd app
flutter pub get
flutter run -d linux --dart-define=CHATVV_API=http://127.0.0.1:8080
```

### Android 真机

```bash
adb reverse tcp:8080 tcp:8080
cd app
flutter run -d <device-id> --dart-define=CHATVV_API=http://127.0.0.1:8080
```

或构建安装：

```bash
flutter build apk --debug --target-platform android-arm64
adb install -r build/app/outputs/flutter-apk/app-debug.apk
```

> Android 9+ 已允许本地明文 HTTP（`usesCleartextTraffic=true`）；生产应改 HTTPS。
> 设备必须在 ADB 模式，不是 MIDI/仅充电。

## 当前结构

```
lib/
├── main.dart
├── app.dart
├── theme/
│   ├── app_theme.dart      # Deep Sea 色板、Material 3
│   └── glass.dart          # BackdropFilter 玻璃面板
├── data/
│   └── remote_chat_api.dart # /v1/messages + /v1/turns SSE
└── features/
    ├── character/
    │   └── character_stage.dart # 顶部静态舞台（Live2D 占位）
    └── chat/
        ├── chat_screen.dart
        ├── chat_controller.dart
        └── chat_models.dart
assets/
├── mascot/                 # 大肥鱼头像/全身（CC BY-NC-SA）
└── live2d/whale-girl/      # Live2D 模型（已放入，adapter 下一步）
```

## 依赖

- `dio`：HTTP/SSE。
- `live2d_flutter`（vendored）：Android/iOS/macOS/Windows/Web 原生 GL；Linux 回退静态立绘。
- 暂无 Riverpod/Drift/secure storage；先用 `ChangeNotifier` + 内存历史。

## 验证

```bash
flutter analyze
flutter test
flutter build linux --debug
flutter build apk --debug
```

## 设计

- [整体架构与 IA](../docs/flutter-app-design.md)
- [C++ 编译成库 / FFI](../docs/native-core-embedding.md)
- [视觉 DESIGN](design/DESIGN.md)
- [角色舞台接口 / 外部模型](design/CHARACTER_STAGE.md)
- [Live2D 接入笔记](../reference/avatar-tech/LIVE2D.md)

## 资产许可

- 大肥鱼：**CC BY-NC-SA 4.0，非商业**；署名见 [ATTRIBUTION.md](../reference/deepseek-mascot/ATTRIBUTION.md)。
- Live2D 模型：**CC BY-NC-SA 4.0**，署名 **上善无形 / ZipZipPipe / 氵六青**；见 [LIVE2D.md](../reference/avatar-tech/LIVE2D.md)。
- 商业分发前必须替换素材或取得授权。

# chatvv app (Flutter)

> 状态：**首版 Client 模式 UI 已 scaffold**（Flutter 3.44.2）。
> 已实现：顶部静态大肥鱼舞台、渐变过渡、聊天列表、SSE 发送/停止、连接设置 sheet。
> 未实现：Live2D runtime、Full/FFI、记忆库、助手管理、TTS。
> 当前环境 Flutter 3.44.2 / Dart 3.12.2；Android SDK 36。

## 运行

### 后端

```bash
cd ..
./build/dev/chatvvd --config config/config.toml
```

默认 mock provider，监听 `127.0.0.1:8080`。

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
flutter build apk --debug
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
- `flutter_live2d`：**尚未加入**；下一步接入 Android/iOS 舞台。
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

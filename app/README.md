# chatvv app (Flutter)

> 状态：**目录与设计已建，尚未 scaffold，未写业务代码**。
> 当前环境未安装 Flutter SDK；本轮先完成归档、参考、设计，再开始编码。

## 目标

- Flutter 原生 UI，2D/2.5D、低占用，无 WebView；Live2D 角色层用原生 GL，不做完整 3D。
- 两种模式：
  - `full`：通过 FFI 内嵌 `libchatvv_core`，本地 SQLite，直连 LLM。
  - `client`：只连远端 `chatvv-server`（HTTP/SSE），本地只做缓存。
- 视觉：Material You 3 Expressive + Apple 毛玻璃 + DeepSeek 大肥鱼。
- 一个持续对话，不做会话列表。
- Live2D 角色舞台（Android/iOS，`flutter_live2d`）；静态头像兜底，3D 仅作后续实验。

## 设计文档

- [整体架构与 IA](../docs/flutter-app-design.md)
- [C++ 编译成库 / FFI](../docs/native-core-embedding.md)
- [视觉与交互 DESIGN](design/DESIGN.md)
- [参考素材](../reference/README.md)

## 计划中的目录

```
lib/
├── main.dart
├── app/                 # bootstrap、router、mode
├── core/                # theme、glass、motion、tokens
├── data/
│   ├── backend/         # ChatBackend 接口
│   ├── embedded/        # FFI
│   ├── remote/          # HTTP/SSE
│   └── cache/           # Drift
└── features/
    ├── chat/
    ├── memory/
    ├── assistants/
    ├── settings/
    └── onboarding/
assets/
├── mascot/              # 大肥鱼 WebP（头像/空状态）
├── live2d/whale-girl/   # Live2D 鲸鱼娘（已放入，4.3 MB）
├── fonts/               # Noto 子集
└── icons/               # Material Symbols 子集
```

## 初始化（Flutter 安装后）

```bash
# app/ 里已有 design/README，先 scaffold 到临时目录，避免覆盖
flutter create --org dev.chatvv --project-name chatvv \
  --platforms=android,ios,linux,macos,windows /tmp/chatvv-scaffold
# 把 /tmp/chatvv-scaffold 的 lib/、pubspec.yaml、android/ios/... 合入 app/
cd app
flutter pub add dynamic_color m3_expressive flutter_secure_storage path_provider
flutter pub add flutter_riverpod dio flutter_markdown flutter_live2d
```

- 先做 `client` 模式：`RemoteChatBackend` + 现有 server。
- 再加 `full`：`ffi` + `ffigen` + `libchatvv_core`。
- Flutter flavors：`client` / `full`；native libs 只进 full。
- Live2D：`flutter_live2d` 只支持 Android/iOS；桌面用静态头像。
- 具体包版本在实现时再锁；不要一次引入过多依赖。

## 资产许可

- 大肥鱼设定图：**CC BY-NC-SA 4.0，非商业**；署名见 [ATTRIBUTION.md](../reference/deepseek-mascot/ATTRIBUTION.md)。
- Live2D 模型：**CC BY-NC-SA 4.0**，署名 **上善无形 / ZipZipPipe / 氵六青**；见 [LIVE2D.md](../reference/avatar-tech/LIVE2D.md)。
- `flutter_live2d`：BSD-3；Cubism Core 为 Live2D Inc. 专有许可，发布前核对。
- 3D VRM `BlueFatFish` 仅随原插件分发授权，未取得 app 分发许可，未提交。
- 商业分发前必须替换素材或取得授权。

## 下一步

1. 安装 Flutter stable，`flutter doctor`。
2. scaffold + 主题/玻璃/大肥鱼，先做静态 Chat 页。
3. `flutter_live2d` 真机 spike（模型加载、idle、透明叠加、口型参数）。
4. 接 `client` 模式 SSE，跑通真机。
5. 再拆 C++ core/FFI。

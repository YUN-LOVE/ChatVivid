# Edge TTS（已迁移到 read-aloud）

> 状态：**旧的自研 C++ Edge TTS 实现已删除**（`src/tts/edge_tts.{h,cpp}`，466 行）。
> 当前实现是 vendored 的 Rust crate `read_aloud` v0.3.3 + C++ 封装
> `chatvv::Synthesize()`。新文档见 [read-aloud.md](read-aloud.md)。

## 迁移说明

| 旧 | 新 |
|---|---|
| 头文件 `src/tts/edge_tts.h` | `src/tts/synthesize.h` |
| 实现 `src/tts/edge_tts.cpp`（手写 curl WebSocket、`EdgeTtsGenerateSecMsGec`、CS64 混淆、SSML 拼装） | `src/tts/synthesize.cpp` + Rust `third_party/read_aloud/` |
| `chatvv::EdgeTtsResult EdgeTtsSynthesize(text, voice, output_path)` | `chatvv::SynthesizeResult Synthesize(text, voice, output_path)` |
| 任意 voice 字符串透传 | 322 个 `VOICE_*` 枚举，字符串→枚举映射 + 未知回退 `zh-CN-XiaoxiaoNeural` |
| C ABI `chatvv_tts_synthesize(text, voice, output_path, error_json)` | **签名不变**，内部改调 `chatvv::Synthesize()` |
| Flutter `app/lib/features/chat/tts_service.dart` | **保持不变**（Dart 侧无感） |

删除原因：

1. libcurl 的 WebSocket 支持（`curl_ws_*`）并非所有发行版都编译进来，旧文档已把它列为
   隐患；手写 C++ 需要自己维护 `TrustedClientToken`、`Sec-MS-GEC`/`Sec-MS-GEC-Version`、
   SSML、二进制帧解析等一整套私有协议细节。
2. Microsoft Edge Read Aloud 是私有协议，服务端随时可能调整；把协议维护收敛到一个
   固定版本的上游 crate（read_aloud）比在本仓库手改 C++ 更容易升级/审计。
3. 新实现复用成熟的 Rust TLS/WebSocket 栈（tungstenite + native-tls），跨平台行为一致，
   本仓库只保留薄薄的 C++ 适配层（voice 映射、参数校验、错误映射、日志）。

## 仍然适用的设计结论

- 输出 MP3（24 kHz / 48 kbit/s / mono），Flutter 侧用 `audioplayers`/原生通道播放；
- 说话状态与 Live2D `ParamMouthOpenY` 口形驱动仍在 UI/音频层，与 TTS 后端解耦；
- 网络/服务不可用时 app 侧回退系统 TTS（`flutter_tts`），这部分逻辑未变；
- TTS 调用放在独立 isolate，避免阻塞 UI 线程（未变）。

## 相关文档

- 新实现、构建依赖、交叉编译、staging 路径、voice 映射、CI 步骤、风险：
  [read-aloud.md](read-aloud.md)
- vendored 源码的来源/版本/补丁/许可：
  `third_party/read_aloud/VENDORED.chatvv.md`
- 客户端播放与口形主题：[flutter-app-design.md](flutter-app-design.md)、
  [live2d.md](live2d.md)

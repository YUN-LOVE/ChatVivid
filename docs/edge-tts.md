# Edge TTS（C++ 重写设计）

目标：在 C++ core 内提供 Edge TTS，输出 MP3，并驱动 Live2D 口形。

## 现状

- Flutter 侧已预留 speaking 状态和 `ParamMouthOpenY` 口形驱动
- 当前没有把 Edge TTS 网络客户端编进 core
- 本机 libcurl 没有 WebSocket 支持（features 无 ws，头文件无 `curl_ws_*`）

## 需要的组件

1. **WebSocket + TLS 客户端**
   - edge-tts 使用 `wss://speech.platform.bing.com/consumer/speech/synthesize/readaloud/edge/v1`
   - 需要 libwebsockets 或 Boost.Beast/OpenSSL（libcurl 当前不够）
   - 需要 `Sec-MS-GEC` / `Sec-MS-GEC-Version`、ConnectionId、TrustedClientToken
2. **协议**
   - 发送 `speech.config`（mp3 24kHz）
   - 发送 SSML，语速/音色可配
   - 接收 binary audio frame，去掉 2 字节头后拼 MP3
   - 处理 turn.end
3. **播放**
   - Android/Windows/Linux 的音频输出需要平台适配
   - Flutter 可用 `audioplayers` 播放 core 返回的 MP3
4. **口形**
   - 根据播放音频的 RMS/包络更新 `ParamMouthOpenY`
   - 或由 TTS 返回音素/时间戳（edge-tts 默认只有音频）

当前实现只做了 UI 侧的“说话/张嘴”占位，不应把 Edge TTS 标为已完成。

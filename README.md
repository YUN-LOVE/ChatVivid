# chatvv

一个跑在自己设备上的**个人 AI 记忆体**：没有会话，只有一条持续的对话。

<p align="center"><img src="reference/deepseek-mascot/crops/avatar.png" width="112" alt="DeepSeek 大肥鱼"></p>


> **方向变更（2026-10-31）**：Web GalGame 前端已归档，改为 **Flutter 原生 app + 可嵌入 C++ 核心**。
> 当前状态：C++ core / server 可运行；**Full 模式（Dart FFI + 内嵌 C++ core）已在 Linux 和 Android arm64 跑通**，Android 真机在无后端、无 adb reverse 时可回复；Flutter 已有启动门、引导和分组设置。
> 2026-11 工具链重构：TTS 换成 Rust `read-aloud`（C ABI）、新增 whisper.cpp 端侧 ASR、llama.cpp/whisper.cpp 共用一份 **Vulkan** ggml 后端、Live2D 统一到 vendored `live2d_flutter`、新增 `platforms/` 平台目录与「按改动目录 / tag 选平台」的 CI。

## 新架构：两种模式，一套核心

```
Flutter app
  ├── client 模式 ── HTTP/SSE ── chatvv-server（独立二进制）
  └── full 模式   ── FFI ─────── libchatvv_core（同一套 C++ 核心）
```

| | `full` | `client` |
|---|---|---|
| 核心 | 内嵌 `libchatvv_core` | 远端 `chatvv-server` |
| 数据 | 本机 SQLite | 服务端 SQLite + 本机缓存 |
| 适合 | 单机/边缘设备 | 手机连家里/服务器 |

- 同一套 C++ 核心，既能编成 server，也能编成 lib。
- Flutter 只写一次 UI；`EmbeddedBackend` / `RemoteBackend` 共用 domain 事件。
- 低占用：无 WebView、无完整 3D、无 Python 依赖；Live2D 角色层用原生 GL；2D Material UI + 系统 TTS 兜底。
- TTS：内嵌 Rust [`read-aloud`](https://github.com/naskopw/read_aloud)（C ABI，Microsoft Edge Read Aloud 协议），不再有自研 WebSocket 客户端；见 [docs/read-aloud.md](docs/read-aloud.md)。
- ASR：内嵌 whisper.cpp（模型不随仓库分发），与 RAG 共用 llama.cpp 的 ggml/Vulkan 后端；见 [docs/asr.md](docs/asr.md)。
- Live2D：鲸鱼娘模型在 `app/assets/live2d/whale-girl/`，Flutter 侧用 vendored `live2d_flutter`（Android/iOS/macOS/Windows/Web，Linux 回退静态立绘）；详见 [Live2D 接入笔记](reference/avatar-tech/LIVE2D.md)。

## 仓库结构

```
app/                    Flutter app（Full/Client + 启动/引导/设置）
  design/DESIGN.md      Material 3 Expressive + 毛玻璃 + 大肥鱼
  assets/               头像 / Live2D / 字体计划
docs/
  flutter-app-design.md 整体架构、两种模式、IA、里程碑
  native-core-embedding.md  C ABI、线程、构建矩阵
  api.md architecture.md injections.md client-sync.md platforms.md ...
reference/              RikkaHub / Material 3 Expressive / 大肥鱼参考
archive/                旧 Web GalGame、Python TTS、3D 资产（不维护）
src/                    C++ 后端（core/server/FFI，含 tts/ 与 asr/）
platforms/              平台适配专属代码与构建/打包脚本（android/ios/linux/macos/web/windows）
config/ tests/ scripts/ third_party/ cmake/
```

- 旧 Web 前端：`archive/web-gal-game/`（源码 + 背景 + 预览；模型在 `archive/galgame-assets/`）。
- 旧 Python TTS：`archive/python-tts/`。
- 3D 资产：`archive/galgame-assets/`（本地保留，gitignore）。

## 已有后端（M0，未改）

```bash
cmake --preset dev
cmake --build --preset dev
cp config/config.example.toml config/config.toml
./build/dev/chatvvd --config config/config.toml
```

默认 mock provider：

```bash
curl -sS http://127.0.0.1:8080/healthz
curl -N -X POST http://127.0.0.1:8080/v1/turns \
  -H 'Content-Type: application/json' \
  -d '{"message":"你好"}'
```

接 DeepSeek：

```bash
export DEEPSEEK_API_KEY=sk-...
# config/config.toml: provider = "deepseek"
```

后端能力：单对话、SQLite 持久化、SSE 回放、取消、7 个注入槽位、历史增量同步、Responses API、本地 RAG（llama.cpp embedding）、Edge Read Aloud TTS、whisper.cpp ASR。
接口见 [docs/api.md](docs/api.md)；Redis/React 时期的历史设计见 [archive/legacy-docs/](archive/legacy-docs/)。

构建依赖现在多了 **Rust/cargo**（read-aloud）和可选 **Vulkan SDK**（ggml Vulkan 后端；
没有 Vulkan 时 `CHATVV_VULKAN=AUTO` 自动回退 CPU，CI 传 `-DCHATVV_VULKAN=ON` 强制启用）。
细节见 [docs/read-aloud.md](docs/read-aloud.md) 与 [docs/asr.md](docs/asr.md)。

## 设计文档

- [Flutter app 设计](docs/flutter-app-design.md)：两种模式、信息架构、低占用预算、里程碑。
- [C++ 编译成库](docs/native-core-embedding.md)：`chatvv_core` / `chatvv_ffi` / `chatvv_server`、C ABI、线程模型、平台构建。
- [read-aloud TTS](docs/read-aloud.md) / [whisper ASR](docs/asr.md)：Rust C ABI 接入、交叉编译、模型与 Vulkan 说明。
- [视觉设计](app/design/DESIGN.md)：Deep Sea Glass、色板、字体、毛玻璃配方、组件。
- [参考目录](reference/README.md)：RikkaHub / Material 3 Expressive / 大肥鱼。
- [Live2D 接入](reference/avatar-tech/LIVE2D.md)：鲸鱼娘模型、`live2d_flutter`、口型/动作/性能。
- [3D VRM 评估](reference/avatar-tech/VRM-3D.md)：BlueFatFish、为什么暂不进 v1。


## 开发 / CI

- **Arch Linux 环境**：见 [docs/install-arch.md](docs/install-arch.md)（clang/CMake/Flutter/Android SDK/NDK/Live2D 依赖）。
- **Android 手机 chroot（Arch ARM aarch64）**：见 [docs/install-arch-aarch64-chroot.md](docs/install-arch-aarch64-chroot.md)（本机可跑后端 + Flutter analyze/test；APK/桌面打包需 x86_64 或 CI）。
- **Android 统一签名**：debug/release、本地/CI 共用一张证书；见 [docs/android-signing.md](docs/android-signing.md)。
- **分支规范**：`main` 稳定、`dev` 集成、feature 从 `dev` 开；见 [CONTRIBUTING.md](CONTRIBUTING.md)。
- **CI/CD**：按改动目录选择平台（`platforms/<platform>/**` 只构建该平台，共享路径触发全部启用平台，纯文档只跑 lint）；tag `vX.Y.Z` 发全平台、`vX.Y.Z-<platform>[...]` 只发指定平台、`vX.Y.Z-rc.N` 为预发布；见 [docs/ci-cd.md](docs/ci-cd.md)。

```bash
# 手动只构建某个平台（GitHub Actions → CI → Run workflow）
gh workflow run ci.yml -f platforms=android,linux
```
- **Arch 包模板**：[packaging/arch/PKGBUILD](packaging/arch/PKGBUILD)。

## 参考与许可

- 大肥鱼/鲸鱼娘设定图：**CC BY-NC-SA 4.0，非商业**；署名链见 [ATTRIBUTION.md](reference/deepseek-mascot/ATTRIBUTION.md)。
- Live2D 模型：**CC BY-NC-SA 4.0**，署名 **上善无形 / ZipZipPipe / 氵六青**；见 [LIVE2D.md](reference/avatar-tech/LIVE2D.md)。
- `live2d_flutter`：BSD-3；内置 Cubism Core 为 Live2D Inc. 专有许可，发布前核对。
- `read-aloud`：**GPL-3.0**（与本仓库 GPL-3.0 兼容）；它反向工程 Microsoft Edge Read Aloud 协议，服务端协议变化可能导致失效。
- `whisper.cpp` / `llama.cpp`：MIT；whisper 模型（ggml-tiny/base 等）不随仓库分发，许可见 [docs/asr.md](docs/asr.md)。
- RikkaHub：**AGPL-3.0**，仅参考交互，不复制代码/资源。
- `m3_expressive`：MIT；`dynamic_color`：Apache-2.0；Noto 字体：OFL；Material Symbols：Apache-2.0。
- 3D 模型：旧 `Vodyanitsa` 由项目所有者提供；`BlueFatFish.vrm` 仅随原插件授权分发，未提交，版权归 **木子恶魔**。

## 下一步

1. 安装 Flutter stable，`flutter doctor`。
2. **Full 模式已打通**：C ABI、Dart FFI、Android arm64、Linux；无本地回环。
3. 启动门 / Onboarding / Full ↔ Client 设置已接入。
4. Windows FFI 与真实 DeepSeek 回归。
5. Live2D adapter（独立分支）。

旧 Web 版仅作历史参考，不再维护。

# chatvv

一个跑在自己设备上的**个人 AI 记忆体**：没有会话，只有一条持续的对话。

<p align="center"><img src="reference/deepseek-mascot/crops/avatar.png" width="112" alt="DeepSeek 大肥鱼"></p>


> **方向变更（2026-10-31）**：Web GalGame 前端已归档，改为 **Flutter 原生 app + 可嵌入 C++ 核心**。
> 当前状态：C++ 后端 M0 可运行；Flutter app 已完成设计与工作区整理，**尚未开始编码**；C++ core/FFI 拆分仍是计划。

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
- 低占用：无 WebView、无完整 3D、无 Python 依赖；Live2D 角色层用原生 GL；2D Material UI + 系统 TTS。
- Live2D：鲸鱼娘模型已放入 `app/assets/live2d/whale-girl/`，Flutter 侧计划用 `flutter_live2d`；详见 [Live2D 接入笔记](reference/avatar-tech/LIVE2D.md)。

## 仓库结构

```
app/                    Flutter app（设计/目录已建，未 scaffold）
  design/DESIGN.md      Material 3 Expressive + 毛玻璃 + 大肥鱼
  assets/               头像 / Live2D / 字体计划
docs/
  flutter-app-design.md 整体架构、两种模式、IA、里程碑
  native-core-embedding.md  C ABI、线程、构建矩阵
  api.md architecture.md injections.md client-sync.md platforms.md ...
reference/              RikkaHub / Material 3 Expressive / 大肥鱼参考
archive/                旧 Web GalGame、Python TTS、3D 资产（不维护）
src/                    C++ 后端（暂不改）
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

后端能力：单对话、SQLite 持久化、SSE 回放、取消、7 个注入槽位、历史增量同步、Responses API。
接口见 [docs/api.md](docs/api.md)；Redis/React 时期的历史设计见 [archive/legacy-docs/](archive/legacy-docs/)。

## 设计文档

- [Flutter app 设计](docs/flutter-app-design.md)：两种模式、信息架构、低占用预算、里程碑。
- [C++ 编译成库](docs/native-core-embedding.md)：`chatvv_core` / `chatvv_ffi` / `chatvv_server`、C ABI、线程模型、平台构建。
- [视觉设计](app/design/DESIGN.md)：Deep Sea Glass、色板、字体、毛玻璃配方、组件。
- [参考目录](reference/README.md)：RikkaHub / Material 3 Expressive / 大肥鱼。
- [Live2D 接入](reference/avatar-tech/LIVE2D.md)：鲸鱼娘模型、`flutter_live2d`、口型/动作/性能。
- [3D VRM 评估](reference/avatar-tech/VRM-3D.md)：BlueFatFish、为什么暂不进 v1。


## 开发 / CI

- **Arch Linux 环境**：见 [docs/install-arch.md](docs/install-arch.md)（clang/CMake/Flutter/Android SDK/NDK/Live2D 依赖）。
- **分支规范**：`main` 稳定、`dev` 集成、feature 从 `dev` 开；见 [CONTRIBUTING.md](CONTRIBUTING.md)。
- **CI/CD**：push/PR 跑四平台后端 + Flutter（app 有 `pubspec.yaml` 后启用）；tag `v*` 自动发 Release；见 [docs/ci-cd.md](docs/ci-cd.md)。
- **Arch 包模板**：[packaging/arch/PKGBUILD](packaging/arch/PKGBUILD)。

## 参考与许可

- 大肥鱼/鲸鱼娘设定图：**CC BY-NC-SA 4.0，非商业**；署名链见 [ATTRIBUTION.md](reference/deepseek-mascot/ATTRIBUTION.md)。
- Live2D 模型：**CC BY-NC-SA 4.0**，署名 **上善无形 / ZipZipPipe / 氵六青**；见 [LIVE2D.md](reference/avatar-tech/LIVE2D.md)。
- `flutter_live2d`：BSD-3；内置 Cubism Core 为 Live2D Inc. 专有许可，发布前核对。
- RikkaHub：**AGPL-3.0**，仅参考交互，不复制代码/资源。
- `m3_expressive`：MIT；`dynamic_color`：Apache-2.0；Noto 字体：OFL；Material Symbols：Apache-2.0。
- 3D 模型：旧 `Vodyanitsa` 由项目所有者提供；`BlueFatFish.vrm` 仅随原插件授权分发，未提交，版权归 **木子恶魔**。

## 下一步

1. 安装 Flutter stable，`flutter doctor`。
2. 先做 **client 模式** UI：Chat + SSE + 设置 + 大肥鱼/玻璃主题。
3. `flutter_live2d` 真机 spike：加载鲸鱼娘、idle、口型、透明叠加。
4. 再加 **full 模式**：拆 `chatvv_core` / C ABI / FFI。
5. Android Full → iOS/桌面 → 打磨。

旧 Web 版仅作历史参考，不再维护。

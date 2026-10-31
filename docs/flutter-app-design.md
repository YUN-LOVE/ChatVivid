# Flutter App 设计（v0.1 构思）

> 状态：**Full（Dart FFI + 内嵌 C++ core）与 Only client 双模式已接入**；Android/Linux FFI 已跑通，启动门/引导/分组设置已落地。Live2D 在独立实验分支，Windows 完整包待补。
> 关联文档：[native-core-embedding.md](native-core-embedding.md) · [app/design/DESIGN.md](../app/design/DESIGN.md) · [reference/README.md](../reference/README.md)

## 1. 为什么从 Web 换成 Flutter

Web 版（Astro + Vue + Three.js + WebGL）能跑，但它与“低占用、可移植、单机优先”的目标冲突：

- 浏览器/WebGL 常驻内存高，3D 场景和无节制的毛玻璃都不是低占用方案。
- Web 前端无法把 C++ 核心作为库直接调用，必须额外跑一个 server 进程。
- 移动端 WebView/浏览器在后台、离线、文件系统、TTS、通知上都受限。
- 3D GalGame 的 3D 资产（PMX + 贴图 17 MB）被归档；Live2D 是 2D 角色层，另算。

新方向：

- **Flutter 原生 UI**，2D/2.5D、轻量、无 WebView；Live2D 用原生 GL，不做完整 3D 世界。
- **C++ 后端编译成库**，Full 模式由 Flutter 通过 C ABI 直接调用；同一套核心再编译一个独立 `chatvv-server` 二进制，供 Client-only 模式使用。
- 设计语言：**Material You 3 Expressive 的颜色/形状/排版 + Apple 毛玻璃的层次**，主视觉是 DeepSeek “大肥鱼/鲸鱼娘”。

## 2. 目标与非目标

### 目标

- 单用户、单条持续对话，不做会话列表和多租户。
- 两种运行模式：`full`（内嵌核心）与 `client`（只连远端 server）。
- Android 优先，后续 iOS / Windows / macOS / Linux。
- 低占用：无 WebView、无完整 3D；Live2D 角色层用原生 GL；release 分包；图片 WebP；字体子集；毛玻璃层数受限。
- Live2D 角色舞台：v1 Android/iOS 用 `flutter_live2d`；桌面按“多套 adapter”后补，桌面先静态头像兜底；说话口型、表情、待机动作。
- 离线可读：Client 模式本地缓存最近消息；Full 模式完全本地 SQLite。
- UI 可维护：Material 3 语义 token + 可替换的“玻璃”层，不把 blur 写死在业务组件里。

### 非目标（至少 v1 不做）

- 多会话、多用户、团队协作。
- 内置模型推理（不在手机上跑 LLM）。
- 完整 MCP/Skills 市场；先把内置 memory/tool 做稳。
- 完整 3D 世界/多角色/WebGL；Live2D 是 v1 角色层，3D 只作为后续实验。
- 商业分发（大肥鱼素材是 CC BY-NC-SA，非商业）。

## 3. 两种模式

| | `full` | `client` |
|---|---|---|
| 核心 | Flutter 通过 FFI 调用 `libchatvv_core` | 无本地核心；HTTP/SSE 连 `chatvv-server` |
| 数据 | 本地 SQLite（核心管理） | 本地 Drift 缓存 + 服务端 SQLite |
| LLM Key | 存本机安全存储，核心直连 API | 存服务端或本机（由部署决定） |
| 安装包 | 较大（含静态库/依赖） | 较小 |
| 离线 | 可读历史；LLM 不可用时排队/报错 | 可读缓存；离线发送不可用 |
| 适用 | 单机自用、边缘设备 | 手机连家里/服务器 |
| 构建 | `--flavor full`，带 native libs | `--flavor client`，不带 native libs |

> **建议先做 `client` 模式**：现有 C++ server 已能跑，Flutter 先通过 HTTP/SSE 把 UI、主题、交互跑通；再拆 `chatvv_core` 和 FFI。这样不用一开始就解决 Android/iOS 的 libcurl/OpenSSL 交叉编译。

## 4. 总体架构

```
┌─────────────────────────────────────────────┐
│ Flutter App                                 │
│                                             │
│  Presentation (Material 3 + Glass)          │
│    Chat / Memory / Assistants / Settings    │
│                 │                           │
│  Application                                │
│    ChatRepository  (single dialog)          │
│    MemoryRepository                         │
│    SettingsRepository                       │
│                 │                           │
│  ┌──────────────┴──────────────┐            │
│  │ EmbeddedBackend (FFI)       │ RemoteBackend (HTTP/SSE) │
│  └──────────────┬──────────────┘            │
└─────────────────┼───────────────────────────┘
                  │
       ┌──────────┴──────────┐
       │ libchatvv_core      │        chatvv-server
       │ SQLite / LLM /      │  ←──  same core + HTTP layer
       │ context / memory    │
       └─────────────────────┘
```

### 共享的 domain 事件

两种 backend 都产出同一种流，UI 不关心底层：

```dart
sealed class ChatEvent {}
class ResponseStarted extends ChatEvent { final String responseId; }
class TextDelta extends ChatEvent { final String delta; }
class ToolCall extends ChatEvent { ... }
class ResponseCompleted extends ChatEvent { ... }
class ResponseFailed extends ChatEvent { final String message; }
```

- `RemoteBackend`：解析 `/v1/turns` 的 SSE（`response.output_text.delta` 等）。
- `EmbeddedBackend`：把 C 回调的 JSON 事件转成同样的 `ChatEvent`。
- 断线重连：Remote 用 `response_id` + `/v1/responses/{id}/events?after=`；Full 由核心内存 hub/SQLite 重放。

## 5. 仓库结构（目标）

```
chatvv/
├── app/                    # Flutter（Full/Client + 启动/引导/设置）
│   ├── lib/
│   │   ├── app/            # 路由、模式、启动
│   │   ├── core/           # theme、motion、glass、result
│   │   ├── data/           # repositories、ffi、remote、cache
│   │   └── features/       # chat / memory / assistants / settings
│   ├── assets/             # 大肥鱼 WebP、字体子集、图标
│   └── design/             # DESIGN.md、tokens、mock
├── src/                    # 现有 C++ 后端（暂不动）
├── include/chatvv/         # 未来 C ABI 头（暂不建）
├── docs/                   # 架构、API、植入、Flutter/FFI 设计
├── reference/              # RikkaHub / Material / 大肥鱼参考
├── archive/                # 旧 Web、Python TTS、3D 资产
├── config/  tests/  scripts/  third_party/
└── README.md
```

`src/` 暂时不拆；等 Flutter Client 模式稳定后，再拆：

- `chatvv_core`：`util/store/app/context/llm/dialog`
- `chatvv_ffi`：C ABI + 事件序列化
- `chatvv_server`：core + `http/server` + `main`

## 6. 信息架构（IA）

保持“**没有会话，只有一个对话框**”的原始设定。RikkaHub 只参考交互，不照搬多会话。

### 首次启动 / Onboarding

1. 品牌页：大肥鱼登场 + “你的记忆体”。
2. 选择模式：
   - **本机运行（Full）**：内嵌核心，数据只在本机。
   - **连接服务器（Client）**：填 `baseUrl` / API Key。
3. 填 LLM Provider（Full）或测试连接（Client）。
4. 选择外观：跟随壁纸 / 深海蓝；毛玻璃开关（低端设备默认关）。
5. 进入唯一的对话。

### 主界面：Chat

```
┌──────────────────────────────┐
│ ☰  水仙女            ⋮  ＋   │  ← glass app bar，title + model 副标题
│    deepseek-chat · 记忆体     │
├──────────────────────────────┤
│                              │
│   [大肥鱼]                   │
│   今天想从哪里开始？          │  ← 助手：无气泡，宽排版
│   ⧉ ↻ ✎ ♪ ⋯                 │
│                              │
│                  ┌─────────┐ │
│                  │ 你好呀   │ │  ← 用户：右对齐小胶囊
│                  └─────────┘ │
│                              │
│   正在回忆……                 │  ← 检索/思考折叠
│                              │
├──────────────────────────────┤
│ ╭──────────────────────────╮ │  ← glass composer
│ │ 说点什么…            📎  │ │
│ ╰──────────────────────────╯ │
│  ✦   ◼   ＋            ➤     │
└──────────────────────────────┘
```

- 助手消息默认**无气泡**（RikkaHub 风格），用排版、头像、动作行区分；用户消息用 `primaryContainer` 小胶囊。
- 动作行：复制、重生成、编辑、朗读、分支/更多、导出；默认半透明，hover/长按显示。
- 流式：光标 + 停止按钮；工具调用/记忆检索用可折叠的 `ExpansionTile`。
- 滚动到底部 pill；新消息到达时若用户上滚，不强制跳底。
- 输入区毛玻璃，固定在底部；键盘弹起时只让 composer 上移，不整页抖动。
- 顶部模型副标题可点，打开模型/助手快速切换。

### Live2D / 3D 角色舞台

- **手机**：顶部 28–34% 是舞台，角色锚定底部；下方消息流；键盘弹起时舞台折叠到 96–120dp 或淡出。
- **平板/横屏**：左侧 60–64% 聊天，右侧 36–40% 全高舞台；角色不遮输入区。
- **中间过渡**：舞台底部 48–72dp 渐变到 `surface`，聊天区顶部 24dp 圆角 + 1px 高光；滚动时舞台轻微视差（-8~-16dp），不硬切。
- **统一接口**：`CharacterRuntime`（load / playMotion / setExpression / setMouthOpen / lookAt / pause / resume / dispose）；Live2D、VRM、静态图、外部导入共用。详见 [CHARACTER_STAGE.md](../app/design/CHARACTER_STAGE.md)。
- **Live2D**：`app/assets/live2d/whale-girl/`，`flutter_live2d`，Android/iOS；口型 `ParamMouthOpenY`。
- **外部模型**：文件选择 → app support → 校验 `model3.json`/VRM/图片 → 记录 license/attribution → 本地 registry；不自动上传、不进安装包。
- **3D**：同一舞台 slot，后续 `VrmCharacterRuntime`；VRM 授权/渲染评估见 [VRM-3D.md](../reference/avatar-tech/VRM-3D.md)。
- **性能**：一个 runtime；不在可见页面时 pause；低端/桌面回退静态头像。

### 抽屉 / 记忆

- 抽屉：当前助手、记忆库、设置、关于/许可。
- 记忆库：按时间/重要度的卡片；搜索；手动 pin/forget；显示“为什么想起这条”（检索分数/时间）。
- 不做会话列表；历史就是这一条对话的时间线。

### 助手 / 预设

RikkaHub 的助手卡片可借鉴：大圆角卡、温度 chip、Prompt 预览、编辑/删除 pill。

- 预设：水仙女（默认）、简洁助手、代码助手、翻译。
- 每个预设：头像、system prompt、模型、温度、工具开关、声音。
- 切换预设不新开会话，只改变当前对话的系统提示。

### 设置

- 外观：动态取色、主题色、深色、毛玻璃强度、字号。
- 连接：Full/Client 切换、baseUrl、API Key、测试连接。
- 模型：provider、baseUrl、model、温度、最大输出。
- 语音：系统 TTS 音色/语速/自动朗读；不做 Python sidecar。
- 数据：导出/导入、清空、数据库路径（Full）。
- 关于：版本、开源许可、大肥鱼署名/CC BY-NC-SA、隐私说明。

## 7. UI 设计方向

详见 [app/design/DESIGN.md](../app/design/DESIGN.md)。一句话：

> **Material 的颜色系统 + Expressive 的大形状/弹簧动效 + Apple 的毛玻璃层次 + 大肥鱼的深海蓝。**

- 色彩：动态取色优先；固定主题用深海蓝 `#3254B5` / `#1C2C78` / 冰蓝 `#92B0DF` / 奶油白 `#FBF7F4` / 珊瑚 `#FF8A7A`。
- 形状：卡片 28–32，按钮/输入 999，FAB 20–28；按压时形状微 Morph。
- 玻璃：只用于顶栏、底部 composer、sheet、浮动 pill；最多 2–3 层；低端设备可关。
- 字体：Noto Sans SC（UI）+ Noto Serif SC（叙述/标题点缀），子集打包。
- 动效：M3 Expressive 的 springy 过渡；列表/发送/停止/展开用 180–320 ms；尊重减少动效设置。
- 大肥鱼：头像/空状态/Onboarding/加载动画；不塞满屏，保持留白。

### 从 RikkaHub 借什么

- 聊天页的极简顶部、模型副标题、助手无气泡排版、动作行、token 信息。
- 助手卡片/温度 chip/编辑 pill。
- 输入区大胶囊 + 工具栏 + 发送圆钮。

### 不借什么

- 多会话、Workspace、媒体生成、Web UI、MCP 市场等大而全功能。
- AGPL 代码/资源；只看交互和视觉，不复制实现。

## 8. 低占用预算

| 项 | 目标 |
|---|---|
| APK（arm64，client） | < 30 MB（含 Live2D 资源，不含用户数据） |
| APK（arm64，full） | < 45 MB（含 core + 依赖 + Live2D） |
| Live2D | 4.3 MB 模型；一个 GL view；不可见暂停 |
| 冷启动 | < 1.5 s（中端机） |
| 常驻内存 | < 180 MB（聊天页） |
| 毛玻璃 | 同屏 ≤ 3 个 BackdropFilter；低端默认关 |
| 图片 | WebP，头像 ≤ 256px，空状态 ≤ 768px |
| 字体 | 只打包用到的字重/子集 |
| 列表 | `ListView.builder` + `RepaintBoundary`；不整页重建 |

测量：`flutter build apk --analyze-size`、DevTools memory、`simpleperf`/Perfetto；每个里程碑记录。

## 9. 资产与许可

- 大肥鱼/鲸鱼娘设定图：`reference/deepseek-mascot/`，**CC BY-NC-SA 4.0**，非商业；署名链见 [ATTRIBUTION.md](../reference/deepseek-mascot/ATTRIBUTION.md)。
- Live2D 模型：`app/assets/live2d/whale-girl/`，**CC BY-NC-SA 4.0**；署名 **上善无形 / ZipZipPipe / 氵六青**；见 [LIVE2D.md](../reference/avatar-tech/LIVE2D.md)。
- `flutter_live2d`：BSD-3-Clause；内置 Live2D Cubism Core 为 Live2D Inc. 专有许可，发布前核对。
- 3D VRM `BlueFatFish`：作者 **木子恶魔**；仅随原插件分发授权，未拿到 app 分发许可，未提交；见 [VRM-3D.md](../reference/avatar-tech/VRM-3D.md)。
- RikkaHub：**AGPL-3.0**，仅参考交互，不复制代码/资源。
- `m3_expressive`：MIT；`dynamic_color`：Apache-2.0；Flutter/three 等按各自许可。
- 图标：Material Symbols（Apache-2.0）子集。
- 字体：Noto Sans SC / Noto Serif SC（OFL），子集打包。
- 如果未来商业分发：必须替换大肥鱼素材，或取得各权利人的商业授权。

## 10. 里程碑

### M1 — Client 模式 UI（推荐先做）

- Flutter scaffold + 主题/玻璃/大肥鱼静态资产。
- Chat 页面 + SSE + 历史拉取 + 停止/重生成。
- `flutter_live2d` 真机 spike：加载模型、idle、透明叠加。
- 设置/连接/关于；Android 真机。
- 不碰 C++。

### M2 — Client 完整

- Live2D 舞台：布局、口型、表情/动作映射、暂停/兜底。
- 本地 Drift 缓存、断线重连、通知、TTS、Markdown/代码高亮。
- 记忆库 UI（先 mock/只读）。
- 分包/体积测量。

### M3 — C++ core 拆分 + 桌面 FFI

- `chatvv_core` / `chatvv_ffi` / `chatvv_server` 三个 target。
- C ABI + `ffigen`；Linux/macOS 先跑通 Full。
- Flutter `EmbeddedBackend` 与 Remote 共用 domain。

### M4 — Android Full

- NDK 交叉编译 SQLite/libcurl/OpenSSL；静态链接/裁剪。
- Full/Client flavor；数据库迁移；Key 安全存储。
- 性能/体积达标。

### M5 — iOS / 打磨

- iOS static lib/framework；后台/音频/通知。
- 无障碍、减少动效、深浅色、平板/桌面自适应。

## 11. 待定问题

1. 首批平台：Android only，还是 Android + Windows 桌面？
2. Full 模式的 libcurl/OpenSSL 是否坚持 C++ 直连，还是移动端用平台 HTTP、核心只管 DB/memory？
3. TTS：系统 TTS 优先，还是保留 edge-tts 作为 Client 模式的可选服务？
4. 大肥鱼用基础白色连体服，还是古风盘髻作为默认？头像用 Q 版，Onboarding 用古风？
5. 动态取色默认开，还是默认固定“深海蓝”以保证品牌一致？
6. 是否保留旧 Web 版作为“legacy demo”，还是彻底不维护？
7. Live2D 默认布局：顶部舞台、右侧分栏，还是全屏沉浸？
8. 3D VRM 是否作为 v2 实验，还是不做？

# chatvv · 视觉与交互设计

> 方向名：**Deep Sea Glass / 深海玻璃**
> Material You 3 Expressive 的颜色与形状 + Apple 的毛玻璃层次 + 大肥鱼（DeepSeek 鲸鱼娘）的深海蓝。
> 状态：概念稿，未实现。参考图见 `reference/deepseek-mascot/crops/`。

![大肥鱼头像](../../reference/deepseek-mascot/crops/avatar.png)

## 1. 设计原则

1. **颜色是 Material 的，层次是 Apple 的**：色 roles/动态取色/状态色遵循 M3；浮层用半透明 + blur + 高光，而不是给所有卡片加玻璃。
2. **大形状、大留白、少装饰**：28–32 圆角、pill 按钮、宽松行高；装饰只留大肥鱼和细小的鳍/波纹。
3. **一个对话，不是会话列表**：主界面就是唯一对话；记忆、助手、设置是抽屉/页面，不制造“聊天列表”的噪音。
4. **玻璃是调味，不是主食**：同屏最多 2–3 个 BackdropFilter；低端设备可一键关闭。
5. **动效服务于状态**：发送、停止、展开、切页；不做无意义的循环动画。
6. **非商业同人资产**：大肥鱼素材 CC BY-NC-SA 4.0；App 内必须署名，商业分发前必须替换/授权。

## 2. 色彩

### 固定主题（不跟随壁纸时）

| Token | Light | Dark | 用途 |
|---|---|---|---|
| primary | `#3254B5` | `#B8C4FF` | 主按钮、选中、发送 |
| onPrimary | `#FFFFFF` | `#00208A` | 主色上的文字 |
| primaryContainer | `#DDE1FF` | `#1B2C7A` | 用户气泡、选中底 |
| secondary | `#4F6F9E` | `#B7C7E8` | 次按钮、链接 |
| tertiary | `#FF8A7A` | `#FFB4A8` | 强调、未读、记忆点 |
| surface | `#FBF7F4` | `#0E1526` | 页面底 |
| surfaceContainer | `#F1ECE7` | `#1A2338` | 卡片 |
| onSurface | `#1B1B1F` | `#E6E8F0` | 文字 |
| outline | `#74777F` | `#8E91A3` | 描边 |
| gold | `#D9A441` | `#F5C26B` | 记忆/时间线点缀 |

- 取色来源：大肥鱼头发 `#3254B5 / #2D459C / #1C2C78`，冰蓝 `#92B0DF`，奶油白 `#FBF7F4`，珊瑚 `#FF8A7A`。
- **动态取色**：Android 12+ 用 `dynamic_color` 生成 `ColorScheme`；把 primary 限制在蓝/青范围，避免壁纸变成粉色后失去品牌。设置里可切“跟随壁纸 / 深海蓝”。
- 深色模式是主场景：夜间、低亮度、毛玻璃更有层次。Light 模式用奶油白，不用纯白。

### 状态色

- 成功：`#4F9D69` / `#8FD6A6`
- 警告：`#D9A441` / `#F5C26B`
- 错误：`#BA1A1A` / `#FFB4AB`
- 思考/检索：`secondary` + 轻微 shimmer，不用紫色。

## 3. 字体

| 角色 | 字体 | 说明 |
|---|---|---|
| Display / 品牌 | **Noto Serif SC** 600 | 只用于“chatvv”“记忆体”等少量标题，制造文学感 |
| Headline / Title | **Noto Sans SC** 600 | 页面标题、助手名 |
| Body | **Noto Sans SC** 400/500 | 正文、对话；行高 1.55 |
| Label | **Noto Sans SC** 500 | 按钮、chip、时间 |
| Code | 系统等宽 / JetBrains Mono 子集 | 代码块 |

- 中文优先用 Noto Sans SC；英文/数字可用 `Cormorant Garamond` 做少量装饰（品牌页），不进入正文。
- 只打包 400/500/600 三个字重 + 常用字子集；Release 关闭字体 fallback 的网络加载。
- M3 Expressive 的 `displayLarge` 57 / `headlineLarge` 32 / `titleLarge` 22 / `bodyLarge` 16 / `labelLarge` 14；中文适度下调字号、加大行高。

## 4. 形状与间距

- 页面卡片：**28**；大卡片/空状态容器：**32**；输入框/按钮：**999**（pill）；FAB：**20**；小 chip：**12**。
- 8pt 网格；页面左右 20；卡片内 20–24；对话行距 12–16。
- 形状动效：按下时 28 → 24 → 28；发送按钮圆 → 方形停止（M3 Expressive 的 shape morph）。
- 不用硬阴影堆叠；用 1px 高光 + 低透明黑阴影 + blur。

## 5. 毛玻璃（Apple 感）

### 配方

```
background: linear-gradient(160deg, #0B1220 0%, #14213D 55%, #2A3F6B 100%)
glass:
  color: surface @ 58–66%
  blur: 18–22
  border: 1px rgba(255,255,255,0.14)
  highlight: top 1px rgba(255,255,255,0.28)
  shadow: 0 12 32 rgba(0,0,0,0.28)
  radius: 28–32
```

- Flutter：`ClipRRect` + `BackdropFilter(ImageFilter.blur(sigmaX: 18, sigmaY: 18))` + `Container(color: surface.withOpacity(.62), border: ...)`。
- 玻璃只用于：
  1. 顶部 app bar（滚动时出现）
  2. 底部 composer
  3. bottom sheet / dialog / 浮动 pill
- 不给每条消息、每个设置项加玻璃；列表用 `surfaceContainer` 实色，保证可读性和滚动性能。
- 低端/省电模式：`glass = false`，surface 提升到 92% 不透明；设置里可手动关。
- 同屏 blur ≤ 3；滚动列表里的玻璃用 `RepaintBoundary` 隔离；避免在动画中改 blur sigma。
- 可读性：玻璃上的文字用 `onSurface` 高对比；必要时加 20% 暗色 scrim。

## 6. 动效

| 场景 | 动效 | 时长/曲线 |
|---|---|---|
| 发送 | 圆钮 → 方形停止，轻微 scale | 180 ms spring |
| 新消息 | fade + 8px 上移 | 220 ms easeOutCubic |
| 流式光标 | 1.1 s 呼吸 | 循环，低对比 |
| 抽屉/页面 | shared axis / fade through | 280 ms |
| 卡片按压 | shape 28→24，scale .98 | 120 ms |
| 记忆展开 | 高度 + fade | 240 ms |
| 加载 | `m3_expressive` 的 morphing indicator | 1.4 s |
| 减少动效 | 全部降为 fade/无位移 | 系统设置 |

- 用 `SpringSimulation`（stiffness 220 / damping 26）做按钮/发送；页面用 Material `PageTransitionsTheme`。
- 不做持续漂浮的大肥鱼（会耗电、抢注意力）；空状态可做极慢的 2–3 px 呼吸。

## 7. 页面草图

### Chat（主界面）

```
┌────────────────────────────────┐
│ ☰   水仙女             ⋮   ＋  │ glass app bar
│     deepseek-chat · 记忆体      │
├────────────────────────────────┤
│                                │
│  [avatar]                      │
│  今天想从哪里开始？              │ assistant, no bubble
│  ⧉  ↻  ✎  ♪  ⋯                │ actions, low emphasis
│                                │
│                   ╭──────────╮ │
│                   │ 你好呀    │ │ user pill
│                   ╰──────────╯ │
│                                │
│  ▸ 正在回忆 3 条…               │ collapsible memory
│                                │
├────────────────────────────────┤
│ ╭────────────────────────────╮ │ glass composer
│ │ 说点什么…              📎  │ │
│ ╰────────────────────────────╯ │
│  ✦    ◼    ＋           ➤      │
└────────────────────────────────┘
```

- 助手消息：头像 32 + 名字 + 正文；动作行 hover/长按出现；流式时右下角显示 token/耗时。
- 用户消息：右对齐、`primaryContainer`、圆角 22（右下 6），最大宽度 78%。
- 顶部模型副标题可点，打开模型/助手 sheet。
- 输入区支持多行、@ 记忆、附件、语音；发送后保留草稿历史（撤销）。

### Live2D 舞台（Chat 的两种布局）

**手机：顶部舞台**

```
┌──────────────────────────────┐
│ ☰  水仙女          ⋮   ＋    │
│    deepseek-chat · 记忆体     │
├──────────────────────────────┤
│   ╭──────────────────────╮   │
│   │    [Live2D 角色]      │   │  28–34% 高，透明 GL
│   │    鲸鱼娘 · 待机     │   │  渐变/玻璃底
│   ╰──────────────────────╯   │
│                              │
│  [头像] 今天想从哪里开始？     │
│  ⧉ ↻ ✎ ♪ ⋯                  │
│                  ╭─────────╮ │
│                  │ 你好呀   │ │
│                  ╰─────────╯ │
│  ▸ 正在回忆 3 条…             │
├──────────────────────────────┤
│ ╭──────────────────────────╮ │
│ │ 说点什么…            📎  │ │
│ ╰──────────────────────────╯ │
│  ✦   ◼   ＋            ➤     │
└──────────────────────────────┘
```

**平板/横屏：右侧分栏**

```
┌────────────────────────┬──────────────┐
│ ☰ 水仙女        ⋮  ＋ │              │
│                        │  [Live2D]    │
│  对话流（60–64%）       │  36–40% 全高 │
│                        │  触控/表情    │
│ ╭────────────────────╮ │              │
│ │ 说点什么…      📎  │ │              │
│ ╰────────────────────╯ │              │
└────────────────────────┴──────────────┘
```

- 手机键盘弹起：舞台折叠到 96–120dp 或隐藏，优先保证输入和消息可见。
- 沉浸模式（可选）：点角色进入全屏舞台，聊天气泡浮在玻璃层上；再点退出。
- 模型：`app/assets/live2d/whale-girl/`（Cubism 4，44 表情 / 8 动作）；Flutter 用 `flutter_live2d`。
- 口型：TTS RMS → `ParamMouthOpenY`；停止朗读归零。
- 动作：空闲 `idle`；思考偏头；完成 `开心兴奋`/`自拍`；出错 `悲伤`/`晕晕`；摸头 `脸红`。
- 触控：插件自带眼睛/头跟随；点击头/身体触发不同表情（HitAreas: Head/Body）。
- 性能：一个 `Live2DView`；不可见/后台 `setRenderingPaused(true)`；低端关闭，显示静态头像。
- 3D：v1 不做；VRM 评估见 `reference/avatar-tech/VRM-3D.md`。

### 记忆库

```
┌────────────────────────────────┐
│ ←  记忆体                 搜索 │
├────────────────────────────────┤
│  今天                         │
│  ╭──────────────────────────╮ │
│  │ 她提到喜欢雨天的金泽      │ │
│  │ 重要度 ●●●○   3 天前     │ │
│  ╰──────────────────────────╯ │
│  更早                         │
│  ...                          │
└────────────────────────────────┘
```

- 卡片显示摘要、重要度、时间、来源对话；点开看“为什么被想起”（检索分数/时间衰减）。
- 支持 pin / forget / 改耐久等级；删除有 undo pill。

### 助手

- 大圆角卡（28），头像 + 名字 + 温度 chip + prompt 两行 + 编辑/删除 pill。
- 默认“水仙女”，其他预设用同一套卡；切换只改 system prompt/模型，不新开会话。

### 设置

- 分组：外观 / 连接 / 模型 / 语音 / 数据 / 关于。
- 每项用 list tile + 28 圆角容器；危险操作红色 + 确认。
- “关于”里放：版本、开源许可、大肥鱼署名与 CC BY-NC-SA、隐私说明。

## 8. 大肥鱼的使用

素材：`reference/deepseek-mascot/`
- 头像：`crops/avatar.png`（256²，透明）。
- 空状态/Onboarding：`crops/base-front.png` 或 `crops/hanfu-bun-front.png`（512²，透明）。
- App icon：头像 + 深海蓝底 + 轻微内发光（后续做 adaptive icon）。
- 加载：头像做 1.5% scale 呼吸；不做复杂 Lottie，省体积。
- 装饰：只在空状态、关于页、记忆空态出现；聊天中不重复大图。
- Live2D：`app/assets/live2d/whale-girl/`（Cubism 4，44 表情/8 动作）。舞台优先用它，静态图作为兜底。
- 不改角色性别/服装设定；不把 DeepSeek 官方 logo 与同人角色混淆；注明非官方。
- 3D VRM 只做参考，不进入 v1；见 [VRM-3D.md](../../reference/avatar-tech/VRM-3D.md)。

### 许可

- **CC BY-NC-SA 4.0**，非商业。
- 设定图署名：上善无形 / ZipZipPipe / YunYueSama / xiaoweigen，见 [ATTRIBUTION.md](../../reference/deepseek-mascot/ATTRIBUTION.md)。
- **Live2D 模型署名：上善无形 / ZipZipPipe / 氵六青**；见 [LIVE2D.md](../../reference/avatar-tech/LIVE2D.md)。
- `flutter_live2d` 插件 BSD-3；内置 Cubism Core 为 Live2D Inc. 专有许可，需在关于页一并列出。
- App 内“关于 → 许可”必须可读地展示署名、来源、许可、修改说明。
- 如果未来商业分发：替换为原创/委托角色，或取得各权利人商业授权。

## 9. 组件清单

- `GlassAppBar` / `GlassComposer` / `GlassSheet`（统一 blur + scrim + 性能开关）
- `MascotAvatar`（尺寸 24/32/40/64，圆/方，状态环）
- `ChatMessage`（assistant/user/system/tool）
- `MessageActions`（copy/regenerate/edit/tts/branch/export）
- `StreamingCursor`
- `ModelChip` / `AssistantChip`
- `MemoryCard` / `MemoryScore`
- `AssistantCard`
- `MorphingSendButton`（send/stop）
- `ThinkingIndicator`（m3_expressive）
- `EmptyState`（大肥鱼 + 一句文案 + 一个行动）
- `Live2DStage`（透明 GL view、布局/折叠/暂停）
- `LipSyncDriver`（TTS RMS → `ParamMouthOpenY`）
- `CharacterExpressionMap`（app 状态 → 表情/动作）
- `UndoPill`

## 10. 无障碍与性能

- 对比度：玻璃上文字 ≥ 4.5:1；不够时加 scrim 或改实色。
- 触控目标 ≥ 48dp；字体缩放 200% 不截断；支持屏幕阅读器 label。
- 减少动效：跟随系统 `MediaQuery.disableAnimations`；关闭呼吸/弹跳。
- 性能：每个消息项 `RepaintBoundary`；图片 `cacheWidth`；长列表 `ListView.builder`；blur 层不滚动。
- 低端设备：默认关闭玻璃、关闭动态取色动画、图片降采样；Live2D 不可见时暂停，低端回退静态头像。
- Live2D：只保留一个 GL view；舞台滚出/键盘弹起/退后台暂停；不把 Live2D 放进滚动列表。

## 11. Do / Don't

**Do**
- 用 M3 的 color roles 和 typography，保证主题切换/动态取色一致。
- 用大圆角、留白、少量高光营造“贵”感。
- 让大肥鱼出现在“需要陪伴”的时刻：空状态、首次启动、记忆为空。

**Don't**
- 不要给每个卡片都加 blur；不要玻璃叠玻璃。
- 不要照搬 RikkaHub 的多会话/Workspace/媒体功能。
- 不要把 DeepSeek 官方 logo、RikkaHub 截图、AGPL 代码直接放进 app。
- 不要用 WebView 跑 Live2D；Live2D 用原生 GL（`flutter_live2d`）。
- 不要 v1 上 3D VRM；18 MB + 3D 引擎不值得，先做好 2D Live2D。

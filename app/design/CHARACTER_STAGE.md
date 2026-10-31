# Character Stage / 角色舞台接口

> 目标：顶部舞台 + 中间渐变过渡 + 下方聊天；Live2D 先实现，VRM/3D、静态图、外部导入走同一套接口。
> 状态：接口设计，未写代码。实现见后续 `features/character/`。

## 1. 布局

### 手机（默认）

```
┌──────────────────────────────┐
│ glass app bar                │
├──────────────────────────────┤
│                              │
│       Live2D / VRM           │  舞台 28–34% 高
│       角色锚定底部            │  背景渐变 + 轻粒子
│                              │
│  ░░░░░ 56dp 渐变过渡 ░░░░░   │  舞台 → 聊天
├──────────────────────────────┤
│ 聊天记录（滚动）              │
│                              │
│ ╭──────────────────────────╮ │
│ │ 输入…                    │ │
│ ╰──────────────────────────╯ │
└──────────────────────────────┘
```

- 舞台高度：手机 28–34%（约 220–300dp），平板/横屏右侧 36–40% 全高。
- **中间过渡**：舞台底部 48–72dp 线性渐变到 `surface`；聊天区顶部 24dp 圆角 + 1px 高光，
  不画硬分割线。滚动时舞台轻微视差（-8~-16dp）和 0.98–1.0 缩放，幅度小。
- 键盘弹起：舞台折叠到 96–120dp 或淡出；聊天/输入优先。
- 滚动到底部时舞台可完全展开；长文阅读时淡到 60% 透明度，避免抢注意力。
- 低端/减少动效：不做视差，舞台固定。

### 舞台背景

- 深海底：`linear-gradient(180deg, #0B1220, #14213D 55%, #2A3F6B)` + 2–3 个极慢的光斑。
- 角色后面加 1 层柔和 radial glow（不遮脸）；不加杂乱粒子。
- 聊天区仍是 `surface`，不要整页玻璃。

## 2. 运行时抽象

```dart
enum CharacterKind { live2d, vrm, staticImage }

class CharacterAsset {
  final String id;
  final CharacterKind kind;
  final String displayName;
  final String entry;        // model3.json / .vrm / image
  final String rootDir;      // app support 下的目录
  final bool bundled;        // 是否随 app 分发
  final String license;      // SPDX 或 "custom"
  final String attribution;  // 关于页展示
  final String? sourceUrl;
}

abstract interface class CharacterRuntime {
  ValueListenable<CharacterRuntimeState> get state;

  Future<void> load(CharacterAsset asset);
  Future<void> playMotion(String group, {int? index, double speed = 1.0});
  Future<void> setExpression(String name);
  Future<void> setMouthOpen(double value);   // 0..1
  Future<void> lookAt(Offset normalized);    // 0..1，可选
  void pause();
  void resume();
  Future<void> dispose();
}
```

- `CharacterStageController` 根据 `kind` 选择 adapter；UI 只依赖 `CharacterRuntime`。
- `Live2DCharacterRuntime`：`flutter_live2d`，`model3.json`；`setParameter('ParamMouthOpenY')`；`startMotion`/`setExpression`；`setRenderingPaused`。
- `VrmCharacterRuntime`：未来；VRM 1.0 + VRMA；需要 3D 渲染器；同一接口。
- `StaticCharacterRuntime`：WebP/PNG 静态或 2–3 帧呼吸；所有平台兜底。
- `CharacterStage` widget：负责舞台尺寸、渐变过渡、折叠、生命周期；不关心底层是 Live2D 还是 VRM。

### 平台矩阵（Live2D 全平台）

| 平台 | Live2D runtime | 状态 |
|---|---|---|
| Android / iOS | `flutter_live2d`（Cubism Native + OpenGL ES） | v1 |
| Windows / macOS / Linux | 独立 `DesktopLive2D`（Cubism Native + FFI/Texture，或 WebView 兜底） | v1 后补；先静态 |
| Web | 不做主目标；必要时 WebView/pixi-live2d | 不做 |

- 用户接受“多套代码”：`CharacterRuntime` 接口不变，平台各自实现 adapter。
- v1 先保证 Android/iOS；桌面先静态，后续补 `DesktopLive2D`。
- 不要在 UI 层判断平台；`CharacterRuntimeFactory` 在 data/platform 层选择。

## 3. 外部模型导入（预留）

> 用户要求“留好加载外部模型的准备”；v1 不实现 UI，但接口/目录/校验先定。

流程：

1. 文件选择器：选 `.model3.json` 所在目录、`.zip`，或 `.vrm` 文件。
2. 复制到 `ApplicationSupport/chatvv/characters/<uuid>/`；不覆盖已有模型。
3. 校验：
   - Live2D：`model3.json` + 引用的 `.moc3`/贴图/动作/表情/物理都存在；拒绝 `../` 路径。
   - VRM：文件头 `glTF`，扩展 `VRMC_vrm`；限制大小（例如 ≤ 80 MB）。
   - 图片：png/webp/jpeg；限制尺寸。
4. 读取/展示 license/attribution；用户确认“仅本地使用/有权使用”后才加入模型列表。
5. 写入本地 registry（SQLite/JSON），记录来源、许可、导入时间；不自动上传。
6. 失败回滚：删除临时目录，保留旧模型。

安全：

- 不允许执行 HTML/JS；Live2D 只走原生 SDK，不 WebView。
- zip 解压限制文件数/总大小，防 zip bomb；路径规范化。
- 外部模型默认 `bundled=false`，不进入安装包；导出/备份时提示许可。

## 4. 状态 → 动作/表情

| App 状态 | Live2D | VRM（未来） |
|---|---|---|
| idle | `idle` motion | idle VRMA |
| thinking | 轻微偏头 + `晕晕`/`呆呆眼` | think pose |
| streaming | 口型 + 眨眼，不切大动作 | viseme blend shape |
| completed | `开心兴奋` / `爱心眼` | happy expression |
| error | `悲伤` / `晕晕` | sad |
| pat/tap | `脸红` / `开心兴奋` | happy + look |
| TTS stop | `ParamMouthOpenY=0` | mouth=0 |
| background | `pause()` | pause/destroy |

- 只挑 6–8 个表情/动作，避免道具（手机、蛋包饭、墨镜）乱入。
- 摸头/点击用 HitAreas：Head/Body；不要全屏手势抢聊天滚动。

## 5. 口型

- TTS 播放器输出 RMS/包络（30–60Hz）→ `setMouthOpen`。
- Live2D：`ParamMouthOpenY`；说话时 `ParamMouthForm` 略微笑；停止归零。
- 不要每个音频采样都过 platform channel；在 Dart 侧合并/节流。
- 无 TTS：口型保持 0；不伪造随机开合。

## 6. 性能

- 同一时间只有一个 runtime；离开聊天页 `pause()`，返回 `resume()`。
- 低端设备/省电：`StaticCharacterRuntime`；不加载 Live2D。
- 舞台不在滚动列表内；`RepaintBoundary` 包舞台；聊天列表独立。
- 3D：只在一个页面渲染，离开销毁；限制 30fps；低端关闭。
- 启动：先显示静态头像，再异步加载 Live2D；加载失败保持静态，不阻塞聊天。

## 7. 许可

- 内置 Live2D：CC BY-NC-SA 4.0，署名 上善无形 / ZipZipPipe / 氵六青；见 `reference/avatar-tech/LIVE2D.md`。
- 外部模型：许可由用户/模型作者决定；app 只做本地加载，不重新分发。
- VRM `BlueFatFish`：授权在谈；未授权前不打包。
- 关于页展示每个模型的 license/attribution；外部模型也显示来源。

## 8. 测试清单

- [ ] Live2D 加载/卸载/暂停；无内存泄漏。
- [ ] 模型缺文件/路径穿越/超大 zip 被拒绝。
- [ ] 口型随 TTS RMS 开合，停止归零。
- [ ] 舞台折叠/展开、键盘、横竖屏。
- [ ] 低端 fallback 静态图。
- [ ] 外部模型导入后重启仍在；删除后清理目录。
- [ ] 关于页显示所有许可。

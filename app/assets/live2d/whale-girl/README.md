# 鲸鱼娘 Live2D (Cubism 4)

运行时模型目录。Flutter 侧用 `live2d_flutter` 加载：

```dart
final ctrl = Live2DViewController();
await ctrl.whenAttached;
await ctrl.loadModel(
  modelDir: 'assets/live2d/whale-girl/',
  modelFileName: 'c_0120.model3.json',
);
ctrl.startMotion(group: 'idle');
```

## 结构

- `c_0120.moc3` + `c_0120.2048/texture_*.png`：模型与贴图。
- `motions/`：8 组动作（`idle`、`selfie`、`ketchup` 等）。
- `expressions/`：44 个表情（开心、哭、爱心眼、鲸鱼等）。
- `c_0120.physics3.json`：头发/饰品物理。
- `c_0120.cdi3.json`：参数/部件清单。
- `c_0120.model3.json`：入口；已补 `Expressions` 列表，并把 `ParamMouthOpenY` 加入 `LipSync` group。
- `manifest.json` / `icon.png`：原插件的表情清单和图标。

## 口型 / 动作

- 口型：TTS 音频 RMS → `ctrl.setParameter('ParamMouthOpenY', 0..1)`（约 30–60Hz，节流）。
- 动作：`startMotion(group: 'idle')`；点击/思考/完成可切 `selfie` 等。
- 表情：`setExpression(index)`；index 对应 `model3.json` 的 `Expressions` 顺序（与 `manifest.json` 一致）。
- 触控：`live2d_flutter` 自带触摸跟踪，眼睛/头会跟手。
- 不可见/后台：`setRenderingPaused(true)`，回前台恢复。

## 许可（必须保留）

- **模型美术：CC BY-NC-SA 4.0，非商业**。
- 署名链：**上善无形（上善）** 原作「溟月」→ **ZipZipPipe** 女仆鲸鱼娘 → **氵六青** Live2D 绑定/动作/表情。
- 来源：https://github.com/Andersen216/dsh-whale-girl-live2d
- 本目录的 `AUTHORS.md`、`NOTICE.md`、`PROVENANCE.md`、`LICENSE-CC-BY-NC-SA-4.0.txt` 必须随模型保留。
- `LICENSE` 是上游插件代码的 MIT 许可，不覆盖模型素材。
- App 内“关于 → 许可”必须展示以上署名、来源、许可和修改说明。
- 修改：本目录补充了 `Expressions` 与 `LipSync` 分组（为 Flutter 播放器准备），未改模型/贴图本身。
- 商业分发前必须替换模型或取得三位权利人的明确授权。

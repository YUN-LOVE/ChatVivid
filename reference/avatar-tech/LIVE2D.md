# Live2D 鲸鱼娘 · 接入笔记

## 模型

- 已放入：`app/assets/live2d/whale-girl/`
- 入口：`c_0120.model3.json`
- 核心：`c_0120.moc3`（2.1 MB）、`c_0120.2048/texture_00.png`（1.77 MB）+ `texture_01.png`
- **44 个表情**（`.exp3.json`）：开心兴奋、哭、爱心眼、生气、脸红、晕晕、鲸鱼、问号、墨镜、手机、蛋包饭……
- **8 组动作**：`idle`、`aidale`、`selfie`、`selfieQuick`、`ketchup`、`openLid`、`bubble`、`splash`
- `c_0120.physics3.json`：头发/饰品物理
- `c_0120.cdi3.json`：参数清单
- `ParamMouthOpenY` 存在；`model3.json` 的 `LipSync` group 已补上
- `Expressions` 列表是我从原插件的 `manifest.json` 生成的（原 `model3.json` 没有），共 44 条

来源：

- 模型/渲染插件：https://github.com/Andersen216/dsh-whale-girl-live2d
- 原始模型包：B站 **氵六青**（UID 11272072）的 `DS鲸鱼娘/DS鼠控版.zip`
- B站免费模型预告：https://www.bilibili.com/video/BV1ALnw6YEGK/
- 角色形象链：上善无形「溟月」→ ZipZipPipe 女仆鲸鱼娘 → 氵六青 Live2D

## Flutter 接入：flutter_live2d

- 包：https://pub.dev/packages/flutter_live2d
- 仓库：https://github.com/linh18nd/flutter_live2d
- 版本：1.0.2（2026-05 发布；2026-09 仍在更新）
- 许可：BSD-3-Clause（插件）；内置 **Live2D Cubism Core** 为 Live2D Inc. 专有许可
- 平台：Android API 24+ / iOS 13+（**不支持桌面**）
- 能力：透明背景、`setParameter`、`setExpression`、`startMotion`、触控跟随、暂停/恢复
- 支持 `.moc3` 3.0–5.3；这个模型是 Cubism 4，兼容

### 依赖

```yaml
dependencies:
  flutter_live2d: ^1.0.2
flutter:
  assets:
    - assets/live2d/whale-girl/
    - assets/live2d/whale-girl/c_0120.2048/
    - assets/live2d/whale-girl/motions/
    - assets/live2d/whale-girl/expressions/
```

> Flutter 的 asset 目录不会自动递归子目录；`c_0120.2048/`、`motions/`、`expressions/` 要单独声明。
> 插件首次加载会把 asset 复制到临时目录，并写 `.ready` 标记。

### 最小用法

```dart
final ctrl = Live2DViewController();

@override
void initState() {
  super.initState();
  ctrl.whenAttached.then((_) async {
    await ctrl.loadModel(
      modelDir: 'assets/live2d/whale-girl/',
      modelFileName: 'c_0120.model3.json',
    );
    await ctrl.startMotion(group: 'idle');
  });
}

@override
void dispose() {
  ctrl.dispose();
  super.dispose();
}

// 透明背景，叠在 Flutter 渐变/图片上
Stack(
  fit: StackFit.expand,
  children: [
    const _StageBackground(),
    Live2DView(controller: ctrl),
    const _ChatOverlay(),
  ],
)
```

### 口型

TTS 播放时取音频 RMS（或直接用 edge-tts 的 WordBoundary 做包络）：

```dart
// 30–60 Hz 节流，不要每个音频采样都过 MethodChannel
final mouth = (rms * 1.8).clamp(0.0, 1.0);
await ctrl.setParameter('ParamMouthOpenY', mouth);
```

- 停止朗读：`setParameter('ParamMouthOpenY', 0)`。
- 说话时避免同时用会改嘴巴的 expression；可把 `ParamMouthForm` 稍微拉向微笑。
- 模型有 `ParamEyeLOpen/ParamEyeROpen`，插件通常会做眨眼；如果没有，可自己驱动。
- 触控跟随：插件自带；也可以手动 `ParamAngleX/Y`、`ParamEyeBallX/Y`。

### 动作/表情映射

| App 状态 | Live2D |
|---|---|
| 空闲 | `startMotion(group: 'idle')` |
| 思考 | idle + `ParamAngleX` 轻微偏头 / 晕晕表情 |
| 回复完成 | `开心兴奋` 或 `爱心眼`，短动作 `selfieQuick` |
| 出错 | `悲伤` / `晕晕` |
| 被摸头 | `脸红` / `开心兴奋` |
| 晚安 | `闭眼口水` / idle 慢速 |

表情 index 顺序等于 `model3.json` 的 `Expressions` 数组（与 `manifest.json` 一致）。正式实现时按 `Name` 建映射，不要硬编码 index。

## 性能与低占用

- 只保留 **一个** `Live2DView`；聊天页离开/退后台 `setRenderingPaused(true)`。
- 模型 4.3 MB；native Cubism Core + GL 会增加 APK；Android/iOS 分包。
- 低端设备可关闭 Live2D，回退到静态头像（`MascotAvatar`）。
- 不在列表滚动时同时跑高帧率；GL 层与 Flutter 列表分离。
- 桌面没有 `flutter_live2d` 支持：桌面版用静态头像/预渲染 WebP，或后续找桌面方案。

## 许可清单

- 模型：**CC BY-NC-SA 4.0**，署名 **上善无形 / ZipZipPipe / 氵六青**。
- 插件：BSD-3-Clause。
- Cubism Core：Live2D Inc. 专有许可；发布前核对 Cubism SDK 条款。
- App 内 About/Third-party licenses 必须展示以上全部。

## 风险

1. `flutter_live2d` 很新（5 stars、2 issues），需要真机验证 Android/iOS。
2. Cubism Core 的移动端许可/分发条款要确认，尤其是上架应用商店。
3. 模型是 Cubism 4；如果未来换 Cubism 5 模型，确认插件版本支持。
4. 44 个表情里很多带道具（手机/蛋包饭/墨镜），App 里只挑少量，避免舞台变成杂货铺。

# Material 3 Expressive × Flutter × 毛玻璃

## 结论

- **Flutter 的 Material 3 基础是成熟的**：`ColorScheme`、`ThemeData`、动态取色、组件主题。
- **M3 Expressive 的“形状 morph / springy 组件”在 Flutter 核心仍未完整**。官方 issue：
  https://github.com/flutter/flutter/issues/168813
- 用第三方 **`m3_expressive` 1.0.0（MIT）** 补：
  - `M3LoadingIndicator`
  - `M3RefreshIndicator`
  - `M3DismissibleListItem`
  - `M3UndoPill`
  - `DraggableContainerButton` / `openContainerTransform`
  https://pub.dev/packages/m3_expressive
- 其余（大圆角、typography、color roles、部分 shape morph）用 Flutter 自带 + 自定义 `AnimationController`/`SpringSimulation`。
- 动态取色用官方 **`dynamic_color`**（Apache-2.0）：
  https://github.com/material-foundation/flutter-packages/tree/main/packages/dynamic_color

## 设计要点（实现时对照）

### Color

- 用 `ColorScheme.fromSeed` / `dynamic_color` 生成 roles；不要硬编码 `Colors.blue`。
- 品牌兜底：深海蓝 `#3254B5`；动态色只取 hue 在蓝/青范围，避免壁纸把品牌变成粉色。
- Surface 用 tonal elevation，不用纯白/纯黑。

### Shape

- Expressive 的核心是**大形状 + 形状变化**：
  - 卡片 28–32；按钮/输入 pill；FAB 20。
  - 按下/发送时做圆角/比例 morph，不要只做 scale。
  - 页面切换用 container transform 或 shared axis。
- `m3_expressive` 的 `DraggableContainerButton` 可以做“按住上拖打开”的容器变换；聊天主界面不必用，适合打开记忆/助手详情。

### Motion

- Spring 参数建议：`stiffness 220–260`、`damping 24–28`；短交互 120–220 ms，页面 280–320 ms。
- 遵守 `MediaQuery.disableAnimations`；低端设备降级。
- 不要对 blur 做动画（非常耗）。

### Glass

- Flutter 没有 iOS `UIVisualEffectView` 的直接等价；`BackdropFilter` + `ClipRRect` 是标准做法。
- 只给 2–3 个浮层用；列表卡片用实色 `surfaceContainer`。
- 低端/省电模式关闭；同屏 blur 层数受限；滚动列表内避免 blur。
- 可选 `liquid_glass_widgets` 包做更“Apple”的折射/高光，但它增加依赖/性能成本；v1 先用自定义 `GlassPanel`。

### Typography

- M3 Expressive 的 display/headline 很大；中文要降一档，避免“大字压脸”。
- Noto Sans SC 正文 + Noto Serif SC 点缀；字体子集，避免几 MB 的全量 CJK。
- 行高：中文正文 1.55–1.65；标题 1.2。

### Accessibility

- 玻璃上文字对比度 ≥ 4.5:1；必要时加 scrim。
- 触控 ≥ 48dp；支持 200% 字体缩放。
- 动态颜色下也要检查深色/浅色对比。

## 参考链接

- Material 3 for Flutter: https://m3.material.io/develop/flutter
- M3 Expressive 官方: https://m3.material.io/blog/building-with-m3-expressive
- Flutter issue: https://github.com/flutter/flutter/issues/168813
- m3_expressive: https://pub.dev/packages/m3_expressive
- dynamic_color: https://github.com/material-foundation/flutter-packages/tree/main/packages/dynamic_color
- liquid_glass_widgets（可选）: https://pub.dev/packages/liquid_glass_widgets

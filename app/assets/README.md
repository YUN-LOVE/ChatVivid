# App assets

## 已有

- `cacert.pem`：curl/Mozilla CA bundle，Android Full 的 OpenSSL 直连使用；
  由 `curl.se/ca` 生成，随 App 打包，不包含私钥。

- `live2d/whale-girl/`：**鲸鱼娘 Live2D Cubism 4 模型**，约 4.3 MB。
  - 44 表情、8 动作、物理、`ParamMouthOpenY` 口型参数。
  - 入口：`c_0120.model3.json`；Flutter 用 `flutter_live2d`。
  - 许可：**CC BY-NC-SA 4.0**，署名 **上善无形 / ZipZipPipe / 氵六青**。
  - 详见 [live2d/whale-girl/README.md](live2d/whale-girl/README.md) 与 [MODEL-LICENSE.md](live2d/whale-girl/MODEL-LICENSE.md)。

## 计划

- `mascot/avatar.webp`：256×256，透明，来自 `reference/deepseek-mascot/crops/avatar.png`。
- `mascot/full.webp`：512×512，透明，空状态/Onboarding。
- `mascot/hanfu.webp`：512×512，古风皮肤/季节限定。
- `fonts/`：Noto Sans SC / Noto Serif SC 子集（400/500/600）。
- `icons/`：Material Symbols 只保留用到的图标（或用 `material_symbols_icons` 按需 tree-shake）。

## 3D（暂不放入）

`BlueFatFish.vrm`（18.5 MB，木子恶魔）仅随原插件授权分发，未取得 chatvv 的分发许可，**不提交**。
3D 评估见 [reference/avatar-tech/VRM-3D.md](../../reference/avatar-tech/VRM-3D.md)。

## 约束

- 不要把 1536×1024 的六视图整张打进 App；只放裁剪后的透明 PNG/WebP。
- 图片统一 WebP、透明、sRGB；头像 ≤ 256，空状态 ≤ 768。
- Live2D 模型是 CC BY-NC-SA 4.0，非商业；App 内必须展示完整署名与许可。
- 商业分发前替换素材，或取得上善无形、ZipZipPipe、氵六青等权利人的授权。
- 桌面没有 `flutter_live2d` 支持：用静态头像，或另做预渲染 WebP。

## 署名

- 设定图：[reference/deepseek-mascot/ATTRIBUTION.md](../../reference/deepseek-mascot/ATTRIBUTION.md)
- Live2D：[reference/avatar-tech/LIVE2D.md](../../reference/avatar-tech/LIVE2D.md)

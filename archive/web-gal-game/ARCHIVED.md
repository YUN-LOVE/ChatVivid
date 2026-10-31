# ARCHIVED · Web GalGame frontend

> **2026-10-31 归档。** 旧版 Astro + Vue 3 + Tailwind 4 + Three.js GalGame 前端。
> 新主线是 Flutter app + C++ 可嵌入核心；本目录不再维护。

## 归档原因

- Web/WebGL 占用高，和“低占用、可移植”的目标冲突。
- Flutter 无法复用 Vue/Three.js 代码。
- 3D 角色与新的 Material 2D / 大肥鱼视觉方向不一致。

## 内容

- 源码：`src/`、`astro.config.mjs`、`package.json`、`pnpm-lock.yaml`、`tsconfig.json`。
- 文档：`README.md`（旧前端说明）、`public/ASSETS.md`、本文件。
- 预览：`preview.png`。
- 背景：`public/backgrounds/kanazawa-night.jpg`（歌川广重，CC0）。
- 模型：已移到 `../galgame-assets/`；`public/models/README.md` 有说明。
- 已移除：`node_modules/`、`.store/`、`dist/`、`.astro/`、Chromium 缓存。

## 如果还想跑

```bash
cd archive/web-gal-game
# 先把模型复制回 public/models/，见 public/models/README.md
pnpm install
pnpm dev
```

还需要旧的 C++ server（`build/dev/chatvvd`）和 Python TTS（`../python-tts/`）。
这只是历史参考，不建议继续修。

## 许可

3D 模型版权归原作者，不在仓库许可内；背景 CC0；Web 代码按原项目许可。

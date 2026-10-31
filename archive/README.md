# Archive / 归档

这里保存**不再进入新主线**、但还想留着的代码/资产。新方向是 Flutter app + C++ 可嵌入核心；
旧 Web GalGame 前端、Python TTS sidecar、3D 模型都不再维护。

| 目录 | 内容 | 状态 |
|---|---|---|
| `web-gal-game/` | Astro + Vue + Three.js GalGame 前端源码 | 归档，不维护 |
| `python-tts/` | edge-tts Python sidecar | 归档，不维护 |
| `legacy-docs/` | Redis/Boost.Asio/React 时期的旧设计文档 | 归档，不维护 |
| `galgame-assets/` | PMX/GLB/贴图/背景（本地大文件，gitignore） | 本地保留，不进 git |

## 为什么归档

- Web/WebGL 与“低占用、可嵌入”的目标冲突。
- Flutter 不能直接复用 Vue/Three.js 代码。
- Python TTS 不可移植；新 app 优先用系统 TTS。
- 3D 角色资产（17 MB PMX + 6.2 MB GLB）与 Material 2D 视觉方向不一致。

## 还能跑吗

`web-gal-game/` 保留了源码、`package.json`、`pnpm-lock.yaml` 和 README，但：

- `node_modules/`、`.store/`、`dist/` 已清理（不归档依赖/构建产物）。
- 3D 模型已移到 `galgame-assets/`，`web-gal-game/public/models/` 只剩说明。
- 要跑旧版：把模型复制回 `public/models/`，`pnpm install`，再起旧的 C++ server 和 Python TTS。

旧版只是历史参考，不建议继续投入。

## 许可

- 3D 模型：由项目所有者提供，版权归原作者；不在仓库许可内。
- Web 代码：按原项目许可（如有）。
- 背景：歌川广重，CC0。
- 详见 `galgame-assets/README.md` 和 `web-gal-game/public/ASSETS.md`。

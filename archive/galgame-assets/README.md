# GalGame assets (local only)

> 这个目录被 `.gitignore` 忽略：大二进制资产不进 git，只保留在本地。
> 新 Flutter app 不使用这些 3D 资产。

## 内容

```
arcore.glb                         # 旧 GLB（6.2 MB），材质有问题
vodyanitsa-source/
  Vodyanitsa.pmx                   # 标准 PMX 2.0（2.7 MB）
  tex/                             # 48 张贴图（PMX 实际引用 6 张）
  preview.png                      # 原始角色预览
  MANIFEST.sha256                  # 原始校验清单
```

## 来源

- 原始 PMX：项目所有者提供的 `Vodyanitsa_MMD_260813/`
- 原始 GLB：项目所有者提供的 `arcore.glb`
- 角色：Vodyanitsa / 水仙女；版权归原作者/权利人，**不在本仓库许可内**。
- 旧的 Web 前端曾经在 `web/public/models/` 放了一份副本；去重后只保留这里。

## 为什么本地-only

- 17 MB PMX + 6.2 MB GLB + 贴图，不适合放进新仓库的初始提交。
- 新 App 不再使用 3D；这些仅作为旧版备份。

如果要恢复旧 Web 版：

```bash
cp -r archive/galgame-assets/vodyanitsa-source archive/web-gal-game/public/models/vodyanitsa
cp archive/galgame-assets/arcore.glb archive/web-gal-game/public/models/arcore.glb
```

如果要迁移到别的机器，请单独拷贝这个目录；不要公开再分发模型。

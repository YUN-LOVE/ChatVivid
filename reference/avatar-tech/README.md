# Avatar tech / 角色舞台

大肥鱼现在有两套可用的现成角色资产：

| 方案 | 资产 | 体积 | 状态 | 结论 |
|---|---|---|---|---|
| **Live2D** | 鲸鱼娘 `.moc3` + 44 表情 + 8 动作 | ~4.3 MB | 已放入 `app/assets/live2d/whale-girl/` | **v1 主方案** |
| **3D VRM** | `BlueFatFish.vrm`（VRM 1.0） | 18.5 MB | 只做参考，未提交 | v2/实验 |

详细：

- [LIVE2D.md](LIVE2D.md)：模型来源、许可、`flutter_live2d` 接入、口型/动作/性能。
- [VRM-3D.md](VRM-3D.md)：VRM 模型、为什么不是第一选择、未来 3D 方案。

## 结论

1. **先做 Live2D**：体积小、2D、原生 GL、无需 WebView/3D 引擎；`flutter_live2d` 已经支持 Android/iOS、透明背景、触控、动作、表情、参数。
2. **静态头像作为兜底**：低端设备/桌面/加载失败时显示 `reference/deepseek-mascot/crops/avatar.png`。
3. **3D 不放进 v1**：VRM 18.5 MB、需要 3D 渲染器/MToon/spring bone，Flutter 生态不成熟；WebView 3D 又违背低占用。
4. **许可**：Live2D 模型 CC BY-NC-SA（非商业）；VRM 模型仅随原插件分发的授权，未拿到 app 授权前不能打包。

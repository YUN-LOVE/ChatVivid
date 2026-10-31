# 3D 大肥鱼 · VRM 方案笔记

## 模型

- 名称：**蓝色小肥鱼Deepseek / BlueFatFish**
- 作者：**木子恶魔**
- 来源：https://www.aplaybox.com/details/model/ayXkRzVflmnd
- 文件：`BlueFatFish.vrm`（18,480,432 bytes，仓库里是 `.br` 压缩）
- 规格：VRM 1.0（`VRMC_vrm`）、152 nodes、6 meshes、53 humanoid bones、18 个 preset expressions + `TiePen`、22 条 spring chains
- 随插件：https://github.com/drliuhuan/dsh-plugin-vrmpet3d（`assets/models/BlueFatFish.vrm.br`）
- 动作：同仓库 `assets/motions/*.vrma`（idle / dance / success / fail）

## 许可

- 插件代码：MIT。
- 模型：**经作者授权随该插件分发，需注明来源与作者**；版权归 **木子恶魔**，不因收录而变成 MIT。
- 授权范围是“随插件分发”；**没有明确授予 chatvv app 的打包/再分发权**。要用，必须先向作者确认，或只在本地导入、不随 app 分发。
- 3D 模型比 Live2D 更容易踩许可/再分发问题；默认不提交到本仓库。

## 为什么不是 v1 首选

1. **体积**：18.5 MB（未压缩）vs Live2D 4.3 MB；加上 3D 引擎/材质/动作，APK 会明显变大。
2. **渲染**：Flutter 没有成熟的 VRM 1.0 + MToon + spring bone 运行时。
   - `thermion_flutter`（Filament）：能渲染 glTF，但 VRM 扩展/MToon/spring bone 要自己做。
   - `three_dart`/`flutter_scene`：生态早期，VRM 支持不确定。
   - WebView + three-vrm：最容易，但违背“无 WebView/低占用”，且后台/触控/性能都差。
3. **GPU/内存**：移动端常驻 3D 场景 + 透明叠加，比 Live2D 的 2D GL 重。
4. **动作/表情**：VRMA 动作包齐全，但 Flutter 侧要自己接 AnimationMixer、表情、口型、spring bone。

## 如果以后要做 3D

- 先做一个**独立的 3D 实验页**，不要塞进主聊天页。
- 评估 `thermion_flutter` + 自写 VRM 扩展（MToon、spring bone）或 WebView + three-vrm。
- 用 VRM 1.0 模型 + VRMA 动作；口型用 `aa/ih/ou/ee/oh` blend shape 或 `VRMExpression`。
- 目标：只在一个页面渲染，离开即销毁；限制 30fps；低端设备默认关闭。
- 许可：先拿到作者对“随 chatvv 分发/商业与否”的书面许可；否则仅本地导入。

## 参考截图

- 原插件 idle：`https://raw.githubusercontent.com/drliuhuan/dsh-plugin-vrmpet3d/main/assets/screenshots/idle.png`
- 状态合成图：`https://raw.githubusercontent.com/drliuhuan/dsh-plugin-vrmpet3d/main/assets/screenshots/states-overview.png`

本仓库不提交 VRM 文件，只保留以上来源与评估。

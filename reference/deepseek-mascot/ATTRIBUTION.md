# 署名与许可 · DeepSeek 大肥鱼 / 鲸鱼娘

本目录中的设定图来自（或改编自）：

- 仓库：https://github.com/xiaoweigen/deepseek-dafeiyu-assets
- 角色：DeepSeek 社区同人“大肥鱼 / 鲸鱼娘”（吃白饭的蓝色大肥鱼）
- 本组改编贡献许可：**CC BY-NC-SA 4.0**
  https://creativecommons.org/licenses/by-nc-sa/4.0/

## 署名链

| 创作者 | 贡献 | 主页 |
|---|---|---|
| 上善无形（上善） | 鲸鱼娘原始角色形象 | https://space.bilibili.com/4456176 |
| ZipZipPipe | 加入 DeepSeek 元素的女仆鲸鱼娘二次设计 | https://space.bilibili.com/4168597 · https://www.pixiv.net/artworks/148186519 |
| YunYueSama | Q 版设定图参考与对应项目新增贡献 | https://github.com/YunYueSama/codex-deepseek-pet |
| xiaoweigen | 本组 AI 辅助改编、造型变体与设定图整理 | https://github.com/xiaoweigen |

推荐署名（转载/App 关于页可直接使用）：

> 大肥鱼／鲸鱼娘改编设定图：原始角色形象「上善无形（上善）」；DeepSeek 女仆形象二次设计「ZipZipPipe」；Q 版设定图参考「YunYueSama」（https://github.com/YunYueSama/codex-deepseek-pet）；本组 AI 辅助改编与整理「xiaoweigen」。来源：https://github.com/xiaoweigen/deepseek-dafeiyu-assets 。本组改编贡献许可：CC BY-NC-SA 4.0（https://creativecommons.org/licenses/by-nc-sa/4.0/）。本次修改：从六视图中裁剪正面/头像、去除白色背景、缩放为 512/256 px。

## 上游许可

- ZipZipPipe《AI娘化》说明：允许取用、须标注作者、不可商用，遵循 CC BY-NC-SA 4.0。
- YunYueSama 的新增贡献使用其自定义署名许可；完整文本保存在原仓库 `licenses/`。
- 本目录 `licenses/` 保存了上游的 `LICENSE`、`LICENSE.zh-CN.md`、`NOTICE.md`，请一并保留。

## 本次修改

- `crops/base-front.png`：从 `source/base-six-views.png` 裁出正面，去白底，缩放到 512×512。
- `crops/hanfu-bun-front.png`：从 `source/hanfu-bun-six-views.png` 裁出正面，去白底，缩放到 512×512。
- `crops/avatar.png`：从基础正面裁出头像区域，去白底，缩放到 256×256。
- 未修改角色设定、颜色、服装或比例。

## Live2D 模型（app/assets/live2d/whale-girl）

Live2D 绑定/动作/表情由 **氵六青**（B 站 UID 11272072）制作，随
[Andersen216/dsh-whale-girl-live2d](https://github.com/Andersen216/dsh-whale-girl-live2d) 分发。
原插件代码 MIT；`assets/model/**` 为 **CC BY-NC-SA 4.0**，非商业。

- 形象链：上善无形「溟月」→ ZipZipPipe 女仆鲸鱼娘 → 氵六青 Live2D。
- 修改：补充 `model3.json` 的 `Expressions` 列表、把 `ParamMouthOpenY` 加入 `LipSync` group；未改模型/贴图。
- 模型目录另有 `AUTHORS.md`、`NOTICE.md`、`PROVENANCE.md`、`LICENSE-CC-BY-NC-SA-4.0.txt`，必须保留。

## 3D 模型（未提交）

`BlueFatFish.vrm`，作者 **木子恶魔**，来源 [APlayBox](https://www.aplaybox.com/details/model/ayXkRzVflmnd)；
仅随 `drliuhuan/dsh-plugin-vrmpet3d` 获得分发授权，未取得 chatvv 的分发许可。
不提交、不随 app 打包；评估见 [VRM-3D.md](../avatar-tech/VRM-3D.md)。

## 免责声明

这是个人非官方同人资源，不代表 DeepSeek 官方；DeepSeek 名称/商标归其权利人。
本项目不授予商业使用许可。商业分发前必须替换素材或取得各权利人的明确授权。

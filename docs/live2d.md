# Live2D

## 运行时

使用 `live2d_flutter`，内置 Live2D Cubism Core，支持 Android / iOS / macOS / Windows。
Linux 没有该插件的原生实现，舞台自动回退到立绘。

内置模型：`assets/live2d/whale-girl/c_0120.model3.json`（DS 鲸鱼娘）。

## 动画

- idle motion：模型自带待机动作，包含呼吸/物理效果
- 眨眼：定时设置 `ParamEyeLOpen` / `ParamEyeROpen`
- 口形：助手流式输出时按节律设置 `ParamMouthOpenY`
- 外部模型：设置 → 角色与舞台 → 导入外部模型，选择包含
  `.model3.json` 及 moc3/贴图/动作/物理文件的 `.zip`
  - 解压到 support/character/live2d_imported
  - 自动寻找第一个 `.model3.json`
  - Android 支持绝对目录；Windows/macOS 的绝对目录支持取决于插件版本

## 许可

模型素材是 **CC BY-NC-SA 4.0**，不是 MIT：

- 上善无形：角色原作「溟月」
- ZipZipPipe：DeepSeek 女仆鲸鱼娘二次设计
- 氵六青（B站 UID 11272072）：Live2D 绑定/动作/表情
- 来源：https://github.com/Andersen216/dsh-whale-girl-live2d

商业使用前必须单独核对模型作者和 Live2D Cubism SDK 条款。

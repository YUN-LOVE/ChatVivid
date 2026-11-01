# 角色模型制作与导入

默认舞台使用 **Rive**（`assets/rive/walking.riv`）；外部导入使用 **Rive `.riv`**。Rive 文件运行时不依赖 Live2D/Spine 编辑器，Android、Linux、Windows 都能加载。

## Rive 制作

1. 在 Rive Editor 新建 Artboard，把角色拆成可动画的图层。
2. 至少创建 **一个 State Machine**；舞台默认播放 State Machine。
3. 建议命名 State Machine 为 `State Machine 1`，并设置默认动画为 idle/loop。
4. 导出 `.riv`，不要只导出 PNG/GIF。
5. 文件建议控制在 10 MB 内；贴图使用图集，避免大量独立纹理。

## 导入应用

设置 → 角色与舞台 → 导入外部模型 → 选择 `.riv` 或 `.svg`。

Rive 文件会复制到 `character/imported.riv`，通过 `FileLoader.fromFile` 加载；
SVG 会复制到 `character/imported.svg`，通过 `flutter_svg` 静态渲染。
导入后角色模式切换为 external；失败会回退内置角色。

导入文件需要包含可用的默认 State Machine，否则 Rive 会报
`Default state machine not found`。如果角色只有 Animation，请先在 Rive Editor 里包一层 State Machine。

## 替换内置角色

把 `.riv` 放到 `app/assets/rive/`，并修改
`app/lib/features/character/character_stage.dart` 中的 asset 路径。
内置资源的授权说明放在 `app/assets/rive/README.md`。

## Spine 备选

Spine 资产是 `skeleton.json`/`.skel` + `.atlas` + 贴图，需要 `spine_flutter` 运行时和 Spine 许可。
当前没有接入 Spine，因为 Rive 的 runtime 和单文件资产更适合这个项目；后续可以按
`CharacterStage` 的接口增加 Spine 实现。

## 动画驱动

舞台目前自动播放 State Machine，并响应点击（舞台互动计数）。
后续可把聊天状态映射成 Rive 输入：
- `speaking` / `thinking` / `happy` 状态机输入
- 发送/完成/失败时设置布尔或触发器
- 角色表情与 TTS 音频口型同步

## 授权

内置 `walking.riv` 来自 Rive 官方 Flutter 示例仓库，仅作 demo；商业发布前请替换成自有或有明确再分发许可的资产。
参见 `app/assets/rive/README.md`。

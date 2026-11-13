# Live2D

## 运行时

使用 **`live2d_flutter`**：pub.dev 包名 `live2d_flutter`（仓库
[hunmer/flutter_live2d](https://github.com/hunmer/flutter_live2d)），版本 1.0.3，
内置 Live2D Cubism Core。

注意不要和 [`flutter_live2d`](https://pub.dev/packages/flutter_live2d)
（linh18nd/flutter_live2d，仅 Android/iOS）混淆：本仓库用的是前者，后者的
C++ 核心是前者的来源，但包名、平台范围和 API 入口都以 `live2d_flutter` 为准。

平台支持情况：

| 平台 | Live2D | 行为 |
|---|---|---|
| Android | ✅ 原生 GL | `Live2DView` 平台视图 |
| iOS | ✅ 原生 GL | `Live2DView` 平台视图 |
| macOS | ✅ 原生 GL | `Live2DView` 平台视图 |
| Windows | ✅ 原生 GL | `Live2DView` 平台视图 |
| Web | ⚠️ 插件声明支持 | 需要 `assets/web/flutter_live2d_web.js` 运行时；本仓库没有 `app/web/` 构建目标，vendored 副本也未带该 JS |
| Linux | ❌ 无原生实现 | 明确回退到静态立绘，不假装支持；后续 Linux/跨平台互动层计划用 `flutter_scene` |

Linux 的行为：`live2dSupported`（`app/lib/features/character/live2d_stage.dart`）
返回 `false`，`CharacterStage` 直接渲染 `assets/mascot/dafeiyu-front.png`，
不会创建平台视图，也不会出现加载转圈。桌面 Linux 不做自研 Cubism 渲染；
后续跨平台互动层计划改用 `flutter_scene`（支持 Linux），不依赖 Live2D 插件补 Linux 实现。

内置模型：`assets/live2d/whale-girl/c_0120.model3.json`（DS 鲸鱼娘）。

## 依赖：为什么是 path 而不是 pub.dev

`app/pubspec.yaml` 用显式 path 依赖指向 `third_party/live2d_flutter`：

```yaml
dependencies:
  live2d_flutter:
    path: ../third_party/live2d_flutter
```

**没有**使用 `dependency_overrides`，也暂时不能改成
`live2d_flutter: ^1.0.3`：pub.dev 上的 1.0.3 归档本身不可构建。

核对方式（2026-11-13，archive sha256
`b16d5d861661427609a692e311f469941526d33a32912616191b8ca5efc84332`）：

```bash
curl -sL -o /tmp/live2d.tar.gz \
  https://pub.dev/api/archives/live2d_flutter-1.0.3.tar.gz
mkdir -p /tmp/live2d-pub && tar xzf /tmp/live2d.tar.gz -C /tmp/live2d-pub
diff -r /tmp/live2d-pub third_party/live2d_flutter   # 排除 .cxx、example 等
```

逐文件对比结论：vendored 副本的 Dart/native 源码与 pub 1.0.3 **完全一致**，
差异只有两处本地打包修复（详见
`third_party/live2d_flutter/PATCHES.md`）：

1. **Android 少了 shader assets（运行时必需）**。Android 原生渲染通过
   `AAssetManager` 从 APK assets 读取
   `FrameworkShaders/VertShaderSrc*.vert`、`FragShaderSrc*.frag`；pub 1.0.3 只
   打包了 `android/src/main/cpp/.../Shaders/StandardES/` 下的 C++ 源码，没有
   把它们作为 Android assets 打包，真机上 shader 加载失败、模型无法渲染。
   vendored 副本补了 36 个字节完全一致的 `FrameworkShaders/*` 资源
   （commit `8aa12f1` 的 “Live2D shaders” 修复）。
2. **pubspec 声明了不存在的 web 资产（构建期失败）**。1.0.3 的
   `flutter.assets` 声明了 `assets/web/flutter_live2d_web.js` 和
   `assets/web/shaders/`，但归档里没有这些文件，任何 `flutter build` 都会报：

   ```text
   Error: unable to find directory entry in pubspec.yaml: .../assets/web/shaders/
   No file or variants found for asset: packages/live2d_flutter/assets/web/flutter_live2d_web.js.
   ```

   vendored 副本删掉了这个 `flutter.assets` 块（本仓库不构建 web Live2D），
   因此它可以正常参与 `flutter build`。

后续上游计划：把这两个打包问题反馈给 hunmer/flutter_live2d；等 pub 发布修复
版本后，删除 `third_party/live2d_flutter`、把 `app/pubspec.yaml` 改回
`live2d_flutter: ^x.y.z`、`flutter pub get` 并做一次 Android 真机渲染验证
（shader 加载 + 模型显示）。

## 动画

- idle motion：模型自带待机动作，包含呼吸/物理效果
- 眨眼：定时设置 `ParamEyeLOpen` / `ParamEyeROpen`
- 口形：助手流式输出时按节律设置 `ParamMouthOpenY`
- 外部模型：设置 → 角色与舞台 → 导入外部模型，选择包含
  `.model3.json` 及 moc3/贴图/动作/物理文件的 `.zip`
  - 解压到 support/character/live2d_imported
  - 自动寻找第一个 `.model3.json`
  - Android 支持绝对目录；Windows/macOS 的绝对目录支持取决于插件版本

## 资源声明

Flutter 的 asset 目录不会自动递归子目录，`app/pubspec.yaml` 里 Live2D 相关
声明保持为：

```yaml
    - assets/live2d/whale-girl/
    - assets/live2d/whale-girl/c_0120.2048/
    - assets/live2d/whale-girl/motions/
    - assets/live2d/whale-girl/expressions/
```

新增模型目录时要同步补这三类子目录声明。

## 验证

```bash
. /home/YUN/development/flutter-env.sh
cd app
flutter pub get     # 会同步 app/pubspec.lock
flutter analyze
```

`flutter test` 由用户在真机/桌面环境执行。Linux 上可验证的是：`flutter analyze`
通过、`live2dSupported == false`、角色页显示静态立绘；Android 真机才验证 Live2D
渲染（shader assets 是否生效）。

## 许可

模型素材是 **CC BY-NC-SA 4.0**，不是 MIT：

- 上善无形：角色原作「溟月」
- ZipZipPipe：DeepSeek 女仆鲸鱼娘二次设计
- 氵六青（B站 UID 11272072）：Live2D 绑定/动作/表情
- 来源：https://github.com/Andersen216/dsh-whale-girl-live2d

插件为 BSD-3-Clause，内置 **Live2D Cubism Core** 为 Live2D Inc. 专有许可。

商业使用前必须单独核对模型作者和 Live2D Cubism SDK 条款。

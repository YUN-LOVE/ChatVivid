# platforms/ios/

iOS 适配目录。**当前未启用**：仓库还没有 `app/ios/`（Flutter iOS runner），也没有 Apple
签名证书/描述文件。

## 文件

| 文件 | 用途 |
|---|---|
| `package.sh` | 未签名 iOS `.ipa`（`flutter build ios --no-codesign` + zip Payload），仅内部 QA |

脚本在 `app/ios` 不存在时会直接退出并打印启用步骤；CI 的 detect/parse-tag 脚本同样不会选中 ios，
tag 里显式写 `-ios` 会 fail 并提示。

## 启用步骤

1. 生成 iOS runner：

   ```bash
   cd app && flutter create --platforms=ios .
   ```

2. 安装依赖并本地验证（需要 macOS + Xcode）：

   ```bash
   cd app && flutter pub get && flutter build ios --release --no-codesign
   ```

3. 配置签名（CI 尚未接入）：
   - Apple Distribution 证书（`.p12` + 密码）
   - Provisioning profile
   - 对应 CI secrets（不要写死在 workflow 里）
4. 在 release tag / `workflow_dispatch` 里选择 `ios`。

## 依赖

- macOS runner（`macos-14`）+ Xcode + CocoaPods。
- Rust `aarch64-apple-ios`（read-aloud 链接进 FFI dylib；iOS 上同样默认 static）。
- Apple 暂时 **不启用 Vulkan**（CPU/Metal），与 macOS 相同，见 `platforms/macos/README.md`。

## CI 引用

启用后：`app-package` 矩阵新增 `ios` 条目（runner `macos-14`），产物名 `chatvv-app-ios`。
在那之前，release 的 `vX.Y.Z`（全平台）**不包含 iOS**——「全平台」指当前已启用平台。

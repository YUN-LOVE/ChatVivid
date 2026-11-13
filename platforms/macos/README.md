# platforms/macos/

macOS 桌面适配：Flutter macOS bundle + `libchatvv_ffi.dylib` 打包。

## 文件

| 文件 | 用途 |
|---|---|
| `package.sh` | 编译 `chatvv_ffi`（`macos-arm64` preset，AppleClang）→ `flutter build macos --release` → 复制 dylib、ad-hoc 签名 → `artifacts/chatvv-macos-arm64.zip` |

## 本地构建

```bash
xcode-select --install
brew install cmake ninja curl
# Rust（read-aloud 静态链接进 libchatvv_ffi）
curl https://sh.rustup.rs -sSf | sh

./platforms/macos/package.sh                 # 旧入口 ./scripts/package-desktop-macos.sh 等价
```

## Vulkan：明确不启用

- Apple 目标保持 **CPU/Metal**：CMake 模块 `cmake/ggml-vulkan.cmake` 在 Apple 上强制
  `GGML_VULKAN=OFF`，`CHATVV_VULKAN=ON` 会直接 FATAL；`package.sh` 默认传 `OFF`。
- 原因：ggml 的 Vulkan 后端需要 MoltenVK，尚未接入。以后可扩展模块支持 MoltenVK，
  届时更新 [docs/ci-cd.md](../../docs/ci-cd.md) 与 release 矩阵。
- Metal 后端由 ggml 自身开关控制，不在本目录脚本范围内。

## read-aloud

- 桌面默认 **static** 链接进 `libchatvv_ffi.dylib`，不需要额外分发 dylib、不需要处理
  `@rpath` / 对 read-aloud 单独签名。
- 若改为 shared，需要复制到 `chatvv.app/Contents/Frameworks/`、处理 `@rpath`
  （`install_name_tool -add_rpath @executable_path/../Frameworks`）并一并 `codesign`。

## CI 引用

- ci.yml：`app-package` 矩阵 `macos` 条目，**受仓库变量 `ENABLE_MACOS_RUNNERS=true` 控制**
  （托管 macOS runner 按 10 倍计费，默认关闭）。
- release.yml：tag 选择 macos（或全平台 tag）时运行，不受变量限制（打 tag 是显式决定）。
- 产物名 `chatvv-app-macos`；后端包 `chatvv-server-macos-arm64`。

## 已知限制

- 只出 arm64 包（`macos-arm64` preset）；x86_64 理论上同预设可编，但未进 CI。
- 签名是 ad-hoc（`codesign -s -`），不是 Developer ID 签名/公证；分发前需补 Apple 证书。

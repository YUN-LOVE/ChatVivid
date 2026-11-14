# platforms/ — 平台适配目录

平台无关的核心代码仍在 `src/`、`app/`；本目录只放**与操作系统 / 打包链路绑定**的适配代码、构建脚本和说明。

## 约定

- `platforms/<platform>/` 只影响该平台：CI 检测到这里的改动时，只构建该平台（见 [docs/ci-cd.md](../docs/ci-cd.md)）。
- `platforms/common/` 是共享代码：改它等同改核心，触发**全部启用平台**。
- 不在平台脚本里复制核心构建逻辑：复用根 `CMakeLists.txt` / `CMakePresets.json` 和
  `platforms/common/build-lib.sh`。
- 每个脚本都能从任意工作目录运行（自己计算仓库根），并尊重这些环境变量：
  `CHATVV_VULKAN`（AUTO/ON/OFF）、`CHATVV_READ_ALOUD_LINKAGE`、`VCPKG_ROOT` 等。
- 每个平台目录的 `README.md` 说明：放什么、依赖、如何本地构建、CI 如何引用。

## 目录与状态

| 目录 | 内容 | 状态 |
|---|---|---|
| `android/` | FFI/read-aloud 构建、APK/AAB 打包、16 KB 对齐与签名校验 | ✅ CI 默认启用 |
| `ios/` | 未签名 iOS `.ipa` 打包（`--no-codesign`） | ⛔ 未启用（缺 `app/ios` 与签名） |
| `linux/` | Linux 桌面 bundle 打包（GTK + Vulkan） | ✅ CI 默认启用 |
| `macos/` | macOS 桌面 bundle 打包（CPU/Metal，无 Vulkan） | ✅ release 启用；CI 需仓库变量 `ENABLE_MACOS_RUNNERS=true` |
| `windows/` | Windows 桌面 bundle 打包（MSVC + vcpkg + Vulkan） | ✅ CI 默认启用 |
| `web/` | Flutter web 构建打包 | ⛔ 未启用（缺 `app/web`；`dart:ffi` 还需条件化） |
| `common/` | 共享 shell 库 + CI 路径/平台分类脚本 + workflow 静态检查 | ✅ |

平台是否「启用」由 `platforms/common/ci/lib.py` 决定：backend（Linux/macOS/Windows）恒在；
app 平台需要 `app/<platform>/` 存在；macOS 在 CI 中额外受 `ENABLE_MACOS_RUNNERS` 变量控制
（托管 macOS runner 按 10 倍计费，release 打 tag 时不受此限制）。

## 脚本迁移映射

原先散落在 `scripts/` 的平台脚本已迁入本目录；`scripts/` 下保留**转发 shim**，旧入口继续可用
（避免文档/本地习惯 404），但新代码、CI 和文档一律引用 `platforms/` 路径：

| 旧路径（兼容 shim） | 新路径（canonical） |
|---|---|
| `scripts/build-android-ffi.sh` | `platforms/android/build-ffi.sh` |
| `scripts/verify-android-apk.sh` | `platforms/android/verify-apk.sh` |
| `scripts/package-desktop-linux.sh` | `platforms/linux/package.sh` |
| `scripts/package-desktop-macos.sh` | `platforms/macos/package.sh` |
| `scripts/package-desktop-windows.ps1` | `platforms/windows/package.ps1` |

`scripts/smoke.sh` 是平台无关的 smoke 测试（`CMakeLists.txt` 的 ctest 直接引用），继续留在 `scripts/`。
新增：`platforms/android/package-apk.sh`（APK/AAB 打包 + 校验 + 产物 staging）。

## 新增一个平台

1. 建 `platforms/<platform>/`，写 `README.md` 和打包脚本（Linux/macOS 用 `*.sh`，Windows 用 `*.ps1`）。
2. 在 `platforms/common/ci/lib.py` 的 `ALL_PLATFORMS` / `APP_RUNNERS` / `APP_PACKAGE_COMMANDS`
   里登记 runner、rust targets、Vulkan 模式和打包命令。
3. 若该平台有 Flutter runner（`app/<platform>/`），检测脚本会自动启用；否则先在 app 里
   `flutter create --platforms=<platform> .`。
4. 更新 [docs/ci-cd.md](../docs/ci-cd.md) 的触发矩阵与依赖表。

## 相关文档

- [CI/CD 与发布](../docs/ci-cd.md)：路径触发矩阵、tag 规则、Vulkan/Rust 依赖。
- [平台支持](../docs/platforms.md)：后端平台矩阵与构建预设。

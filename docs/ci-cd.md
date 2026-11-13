# CI / CD 与发布

> 本文描述重构后的 CI：**按改动路径只构建受影响平台**，release 用 **tag 选择平台**。
> 平台脚本已迁入 `platforms/<platform>/`，`scripts/` 保留兼容入口（见第 2 节）。

## 1. 触发方式

| 事件 | Workflow | 行为 |
|---|---|---|
| push `dev` / `main` / `feature/**` / `fix/**` / `chore/**` | `ci.yml` | 先 `detect` 分类改动，只跑命中的平台 |
| PR → `dev` / `main` | `ci.yml` | 同上，合并前必须绿 |
| `ci.yml` → Run workflow（`platforms` 输入） | `ci.yml` | 手动指定平台子集，如 `android,linux`；留空=全部启用平台 |
| push tag `v*` | `release.yml` | `parse-tag` 解析 tag → 构建/发布对应平台 |
| `release.yml` → Run workflow（`platforms` 输入） | `release.yml` | 只构建并上传 artifacts，**不发 GitHub Release** |

`windows-diag.yml` 已归档，见第 11 节。

## 2. 平台目录约定

平台无关核心仍在 `src/`、`app/`；平台适配代码/构建打包脚本集中在：

```
platforms/
├── android/   build-ffi.sh  package-apk.sh  verify-apk.sh
├── ios/       package.sh        (未启用：缺 app/ios)
├── linux/     package.sh
├── macos/     package.sh
├── windows/   package.ps1
└── common/    build-lib.sh + ci/{lib,detect-changes,parse-tag,lint-workflows}.py
```

规则：

- 改动 `platforms/<p>/**` → 只构建该平台；改动 `platforms/common/**` → 视同核心，触发全部平台。
- 每个平台目录的 `README.md` 写明依赖、本地构建命令、CI 如何引用。
- 平台「启用」判定在 `platforms/common/ci/lib.py`：
  - backend：Linux（x64 + arm64）、macOS、Windows 恒可用；
  - app：`app/<platform>/` 存在才启用 → 当前 `ios` 未启用；**没有 web 平台**（旧 Web 前端在 `archive/`）；
  - macOS 在 CI 中额外受仓库变量 `ENABLE_MACOS_RUNNERS` 控制（见第 9 节）。

### 旧脚本兼容映射

`scripts/` 下保留**转发 shim**，旧入口不会 404；新代码/CI/文档一律用 `platforms/` 路径：

| 旧路径（shim） | canonical |
|---|---|
| `scripts/build-android-ffi.sh` | `platforms/android/build-ffi.sh` |
| `scripts/verify-android-apk.sh` | `platforms/android/verify-apk.sh` |
| `scripts/package-desktop-linux.sh` | `platforms/linux/package.sh` |
| `scripts/package-desktop-macos.sh` | `platforms/macos/package.sh` |
| `scripts/package-desktop-windows.ps1` | `platforms/windows/package.ps1` |

新增：`platforms/android/package-apk.sh`（APK/AAB 打包 + 校验 + staging）。`scripts/smoke.sh`
平台无关，仍在 `scripts/`（被 `CMakeLists.txt` 的 ctest 引用）。

## 3. 路径 → 构建矩阵

`detect` job 用 `git diff`（PR 用 merge-base，push 用 before..sha）分类，规则：

| 改动路径 | backend | app | 说明 |
|---|---|---|---|
| `src/**`、`app/**`、`cmake/**`、`include/**`、`config/**`、`tests/**`、`third_party/**`、`platforms/common/**`、`scripts/**`、根 `CMakeLists.txt`/`CMakePresets.json`/`vcpkg.json`、`.github/workflows/**` | 全部启用平台 | 全部启用平台 | 共享路径 |
| `platforms/<p>/**` | 若 `<p>` 是 backend 平台（linux/macos/windows） | 若 `<p>` 是 app 平台 | 只该平台；`platforms/macos/**` 即使 `ENABLE_MACOS_RUNNERS` 未开也会显式构建 macos |
| `docs/**`、`reference/**`、`archive/**`、`packaging/**`、`*.md`、`README.md`、`LICENSE` 等 | — | — | `light_only=true`，只跑 `lint` |
| 未知路径 | 全部 | 全部 | 保守策略：宁可多构建，不漏构建 |
| 无法计算 diff（新分支/强推/非 PR 无 before） | 全部 | 全部 | 保守回退 |

「全部启用平台」当前 = backend `linux(x64+arm64)`、`macos`、`windows` + app `android`、`linux`、`macos`、`windows`。
iOS 在 `app/ios` 出现前不会自动触发；web 不是目标平台（旧 Web 前端已归档）。

## 4. CI job 矩阵（`ci.yml`）

| Job | Runner | 何时运行 | 内容 |
|---|---|---|---|
| `detect affected platforms` | ubuntu-latest | 总是 | 路径分类，输出 `platforms`/`backend_platforms`/`app_platforms`/`app_matrix`/flags |
| `lint / workflows & scripts` | ubuntu-latest | 总是（含纯文档改动） | workflow YAML 结构/action 版本固定/needs 输出/脚本路径 + `bash -n` + python 编译 |
| `backend / linux x64` | ubuntu-latest | `backend_linux` | `dev` preset 构建 + ctest，Vulkan ON |
| `backend / linux arm64` | ubuntu-24.04-arm | `backend_linux` | `linux-arm64` preset 构建 + ctest，Vulkan ON |
| `backend / macos arm64` | macos-14 | `backend_macos` | `macos-arm64` 构建 + ctest，Vulkan OFF；默认跳过（成本） |
| `backend / windows x64` | windows-2022 | `backend_windows` | vcpkg + `windows-x64` 构建 + ctest，Vulkan ON |
| `app / analyze & test` | ubuntu-latest | `run_app` | `flutter analyze` + `flutter test`（有 test 目录时） |
| `app / <platform>` | 按平台 | `run_app` 且该平台命中 | 动态矩阵，逐个平台 build/package/upload |

`app / <platform>` 的矩阵由 `detect` 输出的 JSON 生成（`strategy.matrix: ${{ fromJSON(needs.detect.outputs.app_matrix) }}`），
每个平台自带 runner/超时/rust targets/Vulkan 模式/打包命令/artifact 名，命令来自 `platforms/<p>/`：

| 平台 | CI 命令 | 产物 artifact |
|---|---|---|
| android | `build-ffi.sh` + `CHATVV_APK_MODE=debug package-apk.sh` | `chatvv-app-android-debug` |
| linux | `platforms/linux/package.sh` | `chatvv-app-linux` |
| windows | `platforms/windows/package.ps1` | `chatvv-app-windows` |
| macos | `platforms/macos/package.sh` | `chatvv-app-macos`（需 `ENABLE_MACOS_RUNNERS` 或显式平台改动） |
| ios | `platforms/ios/package.sh` | 未启用（缺 `app/ios`） |

跳过（skipped）的 job 不会阻塞 PR；`lint` + `detect` 始终有结果。

## 5. Release tag 规则（`release.yml`）

| Tag | 构建范围 | GitHub Release |
|---|---|---|
| `vX.Y.Z` | 全部启用平台 | 发布，`prerelease=false` |
| `vX.Y.Z-<platform>[-<platform>...]` | 只构建/发布列出的平台，如 `v0.2.0-android-linux` | 发布，`prerelease=false` |
| `vX.Y.Z-rc.N` / `-beta.N` / `-alpha.N` / `-pre.N` / `-dev.N` | 全部启用平台 | 发布，`prerelease=true` |
| 平台后缀 + 预发布组合（如 `v0.2.0-rc.1-android`） | 按预发布处理（全平台） | 暂不支持「预发布 + 子集」 |
| 未知后缀 / 格式错误 | **fail**，输出合法格式与平台清单 | — |

说明：

- 「全平台」指**当前已启用平台**：backend `linux`（x64+arm64）、`macos`、`windows`；app `android`、`linux`、`macos`、`windows`。
  `ios` 在 `app/ios` scaffold 之前不在「全平台」内；tag 里显式写 `-ios` 会 fail 并提示启用步骤。
- tag 里选 `linux` = Linux 后端 x64 + arm64 + Linux 桌面 app；选 `android` = Android app（含 FFI）；
  选 `windows` = Windows 后端 + 桌面 app；选 `macos` = macOS 后端 + 桌面 app（release 不受成本变量限制）。
- 预发布兼容：旧约定 `v0.1.0-rc.1` 仍会全平台构建并标记 prerelease。

示例：

```bash
# 全平台正式发布
git tag -a v0.2.0 -m "chatvv v0.2.0" && git push origin v0.2.0

# 只发 Android + Linux
git tag -a v0.2.0-android-linux -m "chatvv v0.2.0 (android, linux)" && git push origin v0.2.0-android-linux

# 预发布（全平台，Release 标记 prerelease）
git tag -a v0.2.0-rc.1 -m "chatvv v0.2.0-rc.1" && git push origin v0.2.0-rc.1
```

Release 产物（GitHub Actions artifact 名 / 包内文件名，均带平台）：

- backend：artifact `chatvv-server-linux-x64` → `chatvv-server-linux-x64.tar.gz`；
  `chatvv-server-linux-arm64`、`chatvv-server-macos-arm64`（`.tar.gz`）、`chatvv-server-windows-x64`（`.zip`）；
- app：artifact `chatvv-app-android` → `chatvv-app-android.apk` + `.aab`；
  `chatvv-app-linux` → bundle 内 `chatvv-linux-x64.tar.gz`；
  `chatvv-app-windows` → `chatvv-windows-x64.zip`；`chatvv-app-macos` → `chatvv-macos-arm64.zip`。

release job 统一生成 `SHA256SUMS`。

`release.yml` 结构：`parse-tag`（输出平台矩阵）→ 各平台 job 用
`if: contains(fromJSON(needs.parse-tag.outputs.backend_platforms), 'linux')` 等条件运行 →
`gate`（`jq` 校验：所有被选中的 job 为 success/skipped，任何 fail 则阻止发布）→
`release`（下载 artifacts + 生成 SHA256SUMS + `softprops/action-gh-release@v2`）。

### 手动按需构建

`workflow_dispatch` 的 `platforms` 输入接受逗号/空格分隔的平台（留空=全部启用平台）：

```text
android,linux
ios                     # 未启用 → 直接 fail 并给启用提示
```

手动运行**只上传 artifacts，不发 Release**；正式发版请打 tag。

## 6. Vulkan（whisper.cpp / llama.cpp 共用 ggml）

`CHATVV_VULKAN` = `AUTO`（本地默认，有 SDK 才启用）/ `ON`（CI 用，缺依赖 FATAL）/ `OFF`。
它控制 llama.cpp 与 whisper.cpp 共用的 ggml Vulkan 后端，Apple 目标强制跳过。

| 平台 | CI 依赖 | CI 传参 | 说明 |
|---|---|---|---|
| Linux x64/arm64 | apt `libvulkan-dev` + `glslc` + `spirv-headers` + `vulkan-tools` | `-DCHATVV_VULKAN=ON` | `FindVulkan COMPONENTS glslc` 由 shaderc 的 glslc 满足；SPIRV-Headers CONFIG 来自 `spirv-headers` 包 |
| Windows x64 | `jakoch/install-vulkan-sdk-action@v1`（LunarG SDK：headers+loader+glslc+SPIRV-Headers） | `-DCHATVV_VULKAN=ON` | 运行时需 `vulkan-1.dll`（显卡驱动自带） |
| Android | NDK sysroot 提供目标 Vulkan 头/`libvulkan.so`；host 侧用 apt `glslc` + `spirv-headers` | `-DCHATVV_VULKAN=ON` | CI 显式传 `-DSPIRV-Headers_DIR` 与 `-DVulkan_GLSLC_EXECUTABLE`，避免交叉 configure 误取 host x86_64 Vulkan；兜底 `ANDROID_VULKAN_CMAKE_ARGS` |
| macOS / iOS | — | `-DCHATVV_VULKAN=OFF` | **明确不启用 Vulkan**：保持 CPU/Metal；ggml Vulkan 需要 MoltenVK，尚未接入；CMake 模块对 Apple 传 ON 会 FATAL |

运行时：Linux 包依赖目标机 `libvulkan.so.1`（GPU 驱动提供，不随包分发）；没有 Vulkan 的机器可用
`CHATVV_VULKAN=OFF` 重新打包。Android 由系统提供 `libvulkan.so`。

## 7. Rust / read-aloud

`third_party/read_aloud/` 是 vendored 的 Rust C ABI crate，由 `cmake/readaloud.cmake`（Lead 集成）在
CMake 构建中调用 cargo；CI 只负责装 Rust 工具链和传环境。

| Job | 安装内容 |
|---|---|
| backend linux / app linux | `dtolnay/rust-toolchain@stable`（host） |
| backend windows / app windows | rust stable + `x86_64-pc-windows-msvc` |
| backend macos / app macos | rust stable + `aarch64-apple-darwin,x86_64-apple-darwin` |
| app android | rust stable + `aarch64-linux-android,armv7-linux-androideabi` + `cargo-ndk` |
| app ios | rust stable + `aarch64-apple-ios` |

- `platforms/android/build-ffi.sh` 导出 NDK 的 `CC_aarch64_linux_android` / `CXX_...` / `AR_...` /
  `CARGO_TARGET_AARCH64_LINUX_ANDROID_LINKER`，CMake 子进程里的 cargo 可直接交叉编译。
- **Android 必须 shared**：传 `-DCHATVV_READ_ALOUD_LINKAGE=shared`，并把 CMake staging 到
  `build/<preset>/read_aloud/lib/libread_aloud.so` 的产物复制进 `jniLibs/arm64-v8a/`；脚本对缺失产物
  `exit 1` 并打印搜索路径。
- **16 KB 页兼容**：Rust cdylib 不继承 CMake 的链接参数，`build-ffi.sh` 通过
  `CARGO_TARGET_<TRIPLE>_RUSTFLAGS="-C link-arg=-Wl,-z,max-page-size=16384 -C link-arg=-Wl,-z,common-page-size=16384"`
  设置；strip 后校验 `LOAD align ∈ {0x4000, 0x10000}`，`verify-apk.sh` 再逐个校验 APK 内所有 `.so`。
- 桌面（Linux/Windows/macOS）默认 **static** 链接进 `libchatvv_ffi`，无需额外分发 read-aloud 动态库。
- cargo 缓存：`actions/cache@v4` 缓存 `~/.cargo/registry`、`~/.cargo/git`，key 含
  `third_party/read_aloud/Cargo.lock` 哈希。

## 8. 缓存、超时、成本

- 缓存：Flutter（`subosito/flutter-action` cache）、cargo（`~/.cargo`）、vcpkg 由 action/脚本自管理。
- 超时：`detect`/`lint` 10 分钟；backend Linux 90、macOS 60、Windows 90；app android/linux 90、macOS 60、Windows 120。
- **macOS 成本**：托管 macOS runner 按 10 倍计费，`ENABLE_MACOS_RUNNERS` 未设时：
  - 共享路径改动**不自动**构建 macOS；
  - 改动 `platforms/macos/**` 或手动 `platforms=macos` 视为显式选择，仍会构建；
  - release 打 tag（含全平台 tag）不受限制。
  需要在仓库 Settings → Variables 里设置 `ENABLE_MACOS_RUNNERS=true` 才让共享改动也覆盖 macOS。
- 纯文档 PR 只跑 `lint`（~10 秒级），不占构建 runner。

## 9. 本地跑单平台 / 模拟 CI

```bash
# 模拟 detect（打印平台矩阵）
DISPATCH_PLATFORMS=android,linux python3 platforms/common/ci/detect-changes.py

# 模拟 tag 解析
python3 platforms/common/ci/parse-tag.py v0.2.0
python3 platforms/common/ci/parse-tag.py v0.2.0-rc.1      # 全平台 + prerelease=true
python3 platforms/common/ci/parse-tag.py v0.2.0-android-linux

# 单独构建某个平台（不经过 CI）
./platforms/android/build-ffi.sh && CHATVV_APK_MODE=debug ./platforms/android/package-apk.sh
./platforms/linux/package.sh
./platforms/windows/package.ps1
./platforms/macos/package.sh
```

各平台依赖与限制见 `platforms/<platform>/README.md`；后端本地预检：

```bash
cmake --preset dev && cmake --build --preset dev && ctest --preset dev
```

## 10. CI 静态检查说明

本机（Arch Linux ARM aarch64 chroot）无法运行 GitHub Actions，因此重构时的验证只包括：

- `python3`（标准库 `json`）本地模拟 `detect-changes.py` / `parse-tag.py` 的路径与 tag 分类；
- YAML 语法与结构校验（PyYAML/js-yaml 解析、唯一 key、action 版本固定、needs 输出引用、脚本路径存在）；
- `bash -n` 全部 shell 脚本、`py_compile` 全部 CI python 脚本。

**未在 GitHub 上实际运行过**。首次 push 后可能出现的问题列在第 14 节，按提示修正即可。

## 11. `windows-diag.yml` 归档

旧 `windows-diag.yml`（`diag/windows-rag` 分支专用诊断）已合并进 `ci.yml` 的
`backend / windows x64` job：vcpkg bootstrap、configure 日志错误提取都在里面；需要单独诊断时用
`ci.yml` 的 `workflow_dispatch` + `platforms=windows`。

该 workflow 文件已删除，不再有重复构建 job。

## 12. 保护建议

仓库 Settings → Branches：

- `main` / `dev`：Require a pull request；Require status checks；Dismiss stale approvals；禁止 force push/删除。
- 必选 checks：`detect affected platforms`、`lint / workflows & scripts`、`app / analyze & test`
  以及各 backend job。路径触发的 job 可能显示 skipped，不会阻塞合并。
- Tag `v*` 仅 maintainer 可创建；Release 使用 `GITHUB_TOKEN`（`contents: write`），不需要 PAT。
- 不要提交 keystore/证书；Android 统一签名使用 secrets（`ANDROID_KEYSTORE_BASE64` 等），
  见 [android-signing.md](android-signing.md)。iOS 需 macOS runner + Apple 证书（尚未接入）。

## 13. Android 统一签名（摘要）

debug 和 release、本地和 CI 全部使用**同一张证书**，因此同包名的包可以互相覆盖安装。
secrets：`ANDROID_KEYSTORE_BASE64`（必填）、`ANDROID_KEYSTORE_PASSWORD`、
`ANDROID_KEY_ALIAS`、`ANDROID_KEY_PASSWORD`、可选 `ANDROID_CERT_SHA256`（构建后校验指纹）。
CI 的 Android job 在打包前执行 `platforms/android/setup-signing.sh --required`，secrets 缺失会
直接失败而不是产出未统一签名的包。生成/轮换/备份与 Play App Signing 说明见
[android-signing.md](android-signing.md)。

## 14. 未验证点与已知风险

1. **CI 未实际跑过**（本机只做了 YAML/脚本静态校验与本地 CMake 构建验证）。Rust read-aloud 的
   `cmake/readaloud.cmake` 与 `build/<preset>/read_aloud/lib/` staging 已接入并在本机通过，
   但 Android/Windows/macOS/iOS 的交叉编译链路未在本机验证；首次 CI 若失败会由 `build-ffi.sh`
   或 fragment 给出明确错误。
2. Android 交叉 configure 的 `FindVulkan` 可能误取 host x86_64 Vulkan 库/头；CI 已显式 pin
   `SPIRV-Headers_DIR` / `Vulkan_GLSLC_EXECUTABLE`，仍失败时按 `platforms/android/README.md` 用
   `ANDROID_VULKAN_CMAKE_ARGS` 指定 NDK sysroot 的 `libvulkan.so` 与 `include`。
   read-aloud 的 staging 路径由 Lead 的 `cmake/readaloud.cmake` 固定为 `build/<preset>/read_aloud/lib/`，
   `platforms/android/build-ffi.sh` 已按该路径查找，找不到会列出搜索路径并 `exit 1`。
3. Linux/Windows 的 Vulkan 构建依赖假定 `glslc`/`spirv-headers` 在 runner 镜像可用（Ubuntu 24.04 已验证包存在）；
   若 runner 镜像变化，改用 LunarG SDK 并 `export VULKAN_SDK`。Windows 用
   `jakoch/install-vulkan-sdk-action@v1`（floating major tag；若上游未维护 `v1`，固定到具体版本
   `@v1.x.y` 或改用 LunarG installer）。
4. macOS 构建保留 CPU/Metal；未接入 MoltenVK，也没有 x86_64 macOS job。
5. iOS 未启用：缺 `app/ios`（需 macOS runner + 签名）。web 不是目标平台，`platforms/` 里已移除。
6. Windows 只跑 `core` 测试（smoke 是 bash 脚本）；Windows arm64 未验证。
7. macOS runner 成本开关默认关闭，共享改动不会覆盖 macOS，靠 release tag 或显式平台改动兜底。
8. 动态矩阵用 `fromJSON(needs.*.outputs.app_matrix)`；输出是脚本校验过的合法 JSON（`{"include":[...]}`），
   如果为空平台列表，job 会被 `run_app` 条件跳过。

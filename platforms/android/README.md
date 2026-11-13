# platforms/android/

Android arm64 适配：C++ FFI + read-aloud（Rust cdylib）构建、APK/AAB 打包、16 KB 页对齐校验。

## 文件

| 文件 | 用途 |
|---|---|
| `build-ffi.sh` | 构建 `chatvv_ffi` + read-aloud，把 `libchatvv_ffi.so`、`libread_aloud.so`、`libc++_shared.so` 放进 `app/android/app/src/main/jniLibs/arm64-v8a/` |
| `package-apk.sh` | `CHATVV_APK_MODE=debug/release`：flutter 打包 + 校验 + 产物 staging 到 `artifacts/` |
| `verify-apk.sh` | 校验 APK 的 zipalign 16 KB、签名（可对比 `ANDROID_CERT_SHA256`）、每个 native ELF 的 `PT_LOAD` 对齐 |
| `make-keystore.sh` | 生成**统一签名** keystore（debug/release/所有机器共用），打印 base64 与 `gh secret set` 命令 |
| `setup-signing.sh` | 本地复用 `key.properties`；CI 从 `ANDROID_KEYSTORE_BASE64` 等 secrets 还原 keystore |

## 本地构建

```bash
# 前置：Android SDK 36 / build-tools 36.0.0 / NDK 27.2.12479018 / JDK 17 / Rust
export ANDROID_HOME=$HOME/Android/Sdk
export CHATVV_VULKAN=AUTO          # 本机无 Vulkan SDK 时自动回退 CPU

./platforms/android/build-ffi.sh   # 旧入口 ./scripts/build-android-ffi.sh 等价
CHATVV_APK_MODE=debug ./platforms/android/package-apk.sh
```

`jniLibs/` 是 gitignore 的生成目录，CI 每次重新生成。

## 统一签名（必读）

debug 与 release、本机与 CI 全部用**同一张证书**，否则手机上的包不能互相覆盖升级（只能卸载重装）。
第一次使用先生成一次 keystore，并把 base64/密码配到 GitHub Secrets：

```bash
./platforms/android/make-keystore.sh    # 生成 app/android/chatvv-release.jks + 打印 gh secret set 命令
```

- CI：`.github/workflows/{ci,release}.yml` 的 Android job 会运行
  `setup-signing.sh --required`（secrets 缺失直接失败）。
- 本地：`setup-signing.sh` 优先用 `app/android/key.properties`；没有时给出警告并使用 Gradle
  debug key（可安装但**不是**统一签名）。
- 完整说明、备份/轮换/Play App Signing：见 [../../docs/android-signing.md](../../docs/android-signing.md)。

## Rust（read-aloud）

- read-aloud 以 C ABI crate 形式 vendored 在 `third_party/read_aloud/`，由
  `cmake/readaloud.cmake`（Lead 集成）在 CMake 构建中调用 cargo。
- **Android 必须用 shared**：`build-ffi.sh` 会传 `-DCHATVV_READ_ALOUD_LINKAGE=shared`，
  并把 CMake staging 到 `build/android-arm64/read_aloud/lib/libread_aloud.so` 的产物复制进 jniLibs
  （`platforms/common/build-lib.sh` 的查找顺序：`read_aloud/lib/` → `build/**` → `third_party/read_aloud/target/**`，
  找不到直接 `exit 1` 并打印搜索路径）。
- 脚本导出 NDK 的 `CC_aarch64_linux_android` / `CXX_...` / `AR_...` /
  `CARGO_TARGET_*_LINKER`，CMake 子进程里的 cargo 可直接交叉编译。
- CI 另外安装 `cargo-ndk`（备选路径）与 rust targets：
  `aarch64-linux-android,armv7-linux-androideabi`。
- **16 KB 页兼容**：`build-ffi.sh` 给 Rust target 设置
  `CARGO_TARGET_<TRIPLE>_RUSTFLAGS="-C link-arg=-Wl,-z,max-page-size=16384 -C link-arg=-Wl,-z,common-page-size=16384"`，
  strip 后用 `llvm-readelf` 校验 `LOAD align ∈ {0x4000, 0x10000}`。`verify-apk.sh`
  还会逐个检查 APK 里所有 `.so`。

## Vulkan（whisper.cpp / ggml）

- NDK sysroot 提供目标 Vulkan 头文件与 `libvulkan.so`；**glslc 必须来自 host LunarG Vulkan SDK**
  （CI 在 Linux runner 用 apt `glslc` + `libvulkan-dev` + `spirv-headers`）。
- CI 传 `-DCHATVV_VULKAN=ON`（缺 SDK 会 FATAL，让 CI 暴露依赖缺失）；本地默认 `AUTO`，
  没有 SDK 时回退 CPU。
- **交叉编译的两半 SDK**（脚本已自动处理）：
  - 目标侧：NDK sysroot 提供 `vulkan/vulkan.h` + `libvulkan.so`（arm64）；
  - 头文件侧：ggml 的 Vulkan 后端要用 C++ 绑定 `vulkan/vulkan.hpp`，**NDK 不自带**，
    所以 `build-ffi.sh` 默认用 host 的 `/usr/include`（`libvulkan-dev` 含 vulkan.hpp）
    并显式 `-DVulkan_LIBRARY=<NDK sysroot>/libvulkan.so`，可通过 `ANDROID_VULKAN_INCLUDE_DIR` 覆盖。
- 已知风险：Android 交叉 configure 时 `FindVulkan` 可能错误找到 host x86_64 的 libvulkan/headers。
  若 CI 报这个错，用 `ANDROID_VULKAN_CMAKE_ARGS` 显式覆盖（脚本已支持）：

  ```bash
  NDK_SYSROOT=$ANDROID_NDK_HOME/toolchains/llvm/prebuilt/linux-x86_64/sysroot
  export ANDROID_VULKAN_CMAKE_ARGS="-DVulkan_LIBRARY=$NDK_SYSROOT/usr/lib/aarch64-linux-android/24/libvulkan.so -DVulkan_INCLUDE_DIR=$NDK_SYSROOT/usr/include"
  ```

## CI 引用

- ci.yml：`app-package` 矩阵里的 `android` 条目 → `build-ffi.sh` + `package-apk.sh`（debug）。
- release.yml：tag 选择 android 时 → `package-apk.sh`（release，产出 APK + AAB）。
- 产物名：`chatvv-app-android-debug`（CI） / `chatvv-app-android`（release）。

## 已知限制

- 本机（Arch ARM aarch64 chroot）没有官方 NDK `linux-x86_64` host 工具链，无法本地打 APK；
  请在 x86_64 主机/CI 上构建，见 [docs/install-arch-aarch64-chroot.md](../../docs/install-arch-aarch64-chroot.md)。
- 签名：CI 无 keystore secrets 时使用 debug 签名（内测用）；正式签名见 [docs/android-16kb.md](../../docs/android-16kb.md)。

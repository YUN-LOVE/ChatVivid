# Arch Linux ARM (aarch64) / Android chroot 开发环境

> 适用：在**安卓手机上的 Arch Linux ARM aarch64 chroot**里开发 chatvv。
> 实测环境：`Arch Linux` + 内核 `5.10.269-[Evo]Shinomiya`（Android）、8 核、10 GiB 内存；
> 2026-11 记录。x86_64 桌面环境见 [install-arch.md](install-arch.md)。

## 0. 结论先说

| 目标 | 状态 | 说明 |
|---|---|---|
| C++ 后端（core/server/ffi/TTS/ASR）+ ctest | ✅ 本机跑通 | `cmake --preset linux-arm64`（CPU 回退），core/tts/ffi/smoke 4/4 测试通过 |
| Flutter 工具链（aarch64 host） | ✅ 本机跑通 | 官方不发行 arm64 Linux SDK，按本文用源码 + arm64 Dart SDK 组装 |
| `flutter pub get` / `analyze` / `test` | ✅ 本机跑通 | analyze 无告警，测试全绿 |
| `flutter build linux`（桌面） | ❌ 本机受阻 | `rive_native` 的 Linux 预编译静态库只有 x86_64 |
| `flutter build apk`（Android） | ❌ 本机受阻 | 官方 NDK 只有 `linux-x86_64` 主机工具链 |
| Android SDK | ⚠️ 部分可用 | Java 版 cmdline-tools 22.0 可装；`apksigner`、`adb` 可用，`aapt2`/`zipalign`/`d8` 是 x86_64 二进制 |

受阻的两项都**不是项目代码问题**，是上游预编译产物只出 x86_64：桌面/APK 打包请在
x86_64 主机或 GitHub Actions 上做（`ci.yml` 已有四平台 + app 打包 job）。

## 1. 系统包

> 需要 root（`sudo`）。系统已 `pacman -Qu` 为 0 时直接装缺的包，不要做无谓的全量升级。

```bash
sudo pacman -S --needed --noconfirm \
  base-devel clang cmake ninja git curl openssl sqlite pkgconf \
  unzip zip jq python-pip xz-utils jdk17-openjdk android-tools \
  rustup          # read-aloud TTS 需要 cargo（原生构建，无需交叉 target）
# 可选：Vulkan 后端（没有就 CHATVV_VULKAN=AUTO 自动回退 CPU）
sudo pacman -S --needed --noconfirm vulkan-devel shaderc
```

- 后端只依赖系统 `sqlite`/`curl`/`openssl` 头文件，**不需要 vcpkg**。
- `jdk17-openjdk`：Android/Gradle 需要 JDK 17（`java -version` 必须是 17）。
- `android-tools`：提供 `adb`（与 SDK 的 platform-tools 二选一）。
- `mesa`、`gtk3`、`libsecret` 若已有就不用动；`flutter build linux` 需要 GTK3 开发包。

验证：

```bash
clang++ --version && cmake --version && ninja --version
```

## 2. C++ 后端

```bash
. /home/YUN/development/flutter-env.sh 2>/dev/null || true
cmake --preset linux-arm64            # 无 Vulkan SDK 时自动 CPU（AUTO），会有 WARNING
cmake --build build/linux-arm64 -j3   # 内存紧张时用 -j2，llama.cpp/whisper.cpp 编译吃内存
ctest --test-dir build/linux-arm64 --output-on-failure
```

- 现在构建会顺带：cargo 编译 `third_party/read_aloud`（staging 到
  `build/linux-arm64/read_aloud/`）、编译 vendored whisper.cpp（复用 llama.cpp 的 ggml）。
- 想要 Vulkan：装 `vulkan-devel shaderc` 后 `cmake --preset linux-arm64 -DCHATVV_VULKAN=ON`
  （缺 SDK 会 FATAL；不传则 AUTO 自动回退 CPU）。
- 只要 CPU/不想装 Rust：`-DCHATVV_ENABLE_READ_ALOUD=OFF`（TTS 变 stub，其余照常编译）。

实测（CPU 模式）：`core` / `tts` / `ffi` / `smoke` 四个测试全部通过（约 1 秒）。

- 首次构建要编译 vendored 的 llama.cpp + ggml（130 个目标，8 核约 5–10 分钟）。
- 嵌入式 3 GiB 可用内存时不要 `-j8`，容易 OOM；`-j2`/`-j3` 稳。
- 内存模型按 ARMv8 通用构建，不写 `-march`，产物可在其它 ARM64 设备跑。

## 3. Flutter（aarch64 host，非官方支持）

### 3.1 为什么不能直接下官方 tarball

`releases_linux.json` 里 **所有 stable 构建的 `dart_sdk_arch` 都是 `x64`**，
官方 Linux tarball 自带 x64 `dart-sdk`，无法在 aarch64 上执行。
但 Flutter 的引擎产物**有** `linux-arm64` 版本（`dart-sdk-linux-arm64.zip`、
`linux-arm64/artifacts.zip`、`linux-arm64-debug/linux-arm64-flutter-gtk` 都能下载），
所以可以「框架源码 + arm64 Dart SDK」自己拼一个 SDK。

版本选择：**Flutter 3.44.2 / Dart 3.12.2**，正好满足 `app/pubspec.yaml` 的 `sdk: ^3.12.2`。

### 3.2 下载框架源码

GitHub `git clone` 在本机可能被 `~/.gitconfig` 里的失效代理挡住；用 codeload tarball 更稳：

```bash
mkdir -p ~/development && cd ~/development
curl -sSL -o flutter-3.44.2.tar.gz \
  "https://codeload.github.com/flutter/flutter/tar.gz/refs/tags/3.44.2"
tar xzf flutter-3.44.2.tar.gz
mv flutter-3.44.2 flutter
```

### 3.3 关键一步：让它变成「git 仓库」并钉住引擎版本

Flutter 工具要求 SDK 是 git 仓库，否则报
`The Flutter directory is not a clone of the GitHub project.`
另外源码包里的 `bin/internal/engine.version` 被 `.gitignore` 忽略，不显式跟踪的话
脚本会去猜引擎版本并下载到 404。

```bash
cd ~/development/flutter
git init -q && git config user.email dev@localhost && git config user.name dev
git checkout -q -b stable
git add -A
git add -f bin/internal/engine.version    # 必须 -f，它被 .gitignore 忽略了
git commit -qm "flutter 3.44.2" && git tag 3.44.2
git remote add origin https://github.com/flutter/flutter.git   # 安抚 flutter doctor
```

### 3.4 引导工具链（自动下载 arm64 Dart SDK）

`bin/internal/update_dart_sdk.sh` 会把 `uname -m == aarch64` 映射成 `arm64`，
从引擎产物地址下载 `dart-sdk-linux-arm64.zip`（约 220 MB）：

```bash
export FLUTTER_STORAGE_BASE_URL=https://storage.flutter-io.cn   # 引擎/Dart SDK 镜像，快 2~3 倍
export FLUTTER_GIT_URL=https://github.com/flutter/flutter.git

~/development/flutter/bin/flutter --version
```

首次会下载 Dart SDK、`dart pub get` 引导 flutter_tools。看到下面的输出即成功：

```
Flutter 3.44.2 • channel stable
Engine • revision 77e2e94772
Tools • Dart 3.12.2 • DevTools 2.57.0
```

### 3.5 环境变量（已写入 shell 配置）

写入 `~/development/flutter-env.sh`，并接到 `~/.bashrc`；fish 用 `set -Ux` 持久化：

```bash
export PATH="$HOME/development/flutter/bin:$PATH"
export FLUTTER_STORAGE_BASE_URL="https://storage.flutter-io.cn"
# pub 镜像会改写 pubspec.lock 里的 source url，默认不设；需要时临时加 PUB_HOSTED_URL
export FLUTTER_GIT_URL="https://github.com/flutter/flutter.git"
export JAVA_HOME="/usr/lib/jvm/java-17-openjdk"
export ANDROID_HOME="$HOME/Android/Sdk"
export ANDROID_SDK_ROOT="$ANDROID_HOME"
export PATH="$ANDROID_HOME/cmdline-tools/latest/bin:$ANDROID_HOME/platform-tools:$PATH"
```

### 3.6 验证 app

```bash
cd app
flutter pub get      # 直连 pub.dev 即可（用镜像会改写 pubspec.lock，不建议）
flutter analyze      # 实测 No issues found
flutter test         # 实测 All tests passed
```

## 4. Android SDK（不含 NDK）

**cmdline-tools 必须用 22.0（`16111833`→ 新版的 `sdkmanager` 只是 x86_64 `android` 二进制的壳，
aarch64 上直接 `可执行文件格式错误`）**：

```bash
export JAVA_HOME=/usr/lib/jvm/java-17-openjdk
export ANDROID_HOME=$HOME/Android/Sdk
mkdir -p "$ANDROID_HOME/cmdline-tools" /tmp/andtools && cd /tmp/andtools
curl -sSL -O "https://dl.google.com/android/repository/commandlinetools-linux-15859902_latest.zip"
unzip -q commandlinetools-linux-15859902_latest.zip
mv cmdline-tools "$ANDROID_HOME/cmdline-tools/latest"

export PATH="$ANDROID_HOME/cmdline-tools/latest/bin:$ANDROID_HOME/platform-tools:$PATH"
yes | sdkmanager --licenses
sdkmanager --install "platform-tools" "platforms;android-36" "build-tools;36.0.0"
flutter config --android-sdk "$ANDROID_HOME"
```

装好之后的状态（实测）：

- `apksigner`（shell 脚本 + Java）✅ 可用；
- `platform-tools/adb` 是 x86_64，本机需替换成系统原生 adb：
  `mv adb adb.x86_64 && ln -s /usr/sbin/adb adb`（`android-tools` 提供 aarch64 版，flutter doctor 才不崩）；
- `build-tools/36.0.0` 下的 `aapt2`、`zipalign`、`d8`、`r8` 都是 `ELF 64-bit x86-64`
  → 本机直接 `可执行文件格式错误`，所以 [verify-android-apk.sh](../platforms/android/verify-apk.sh)
  里的 `zipalign` 检查也只能在 x86_64 主机跑。

结论：Android SDK 在本机只适合看文档/装 `apksigner`、用 `adb`，不能产出 APK。

## 5. 两个上游限制（本机没法绕过）

### 5.1 `flutter build linux`：rive_native 只有 x86_64 预编译库

`app` 依赖 `rive_native 0.1.11`（`rive 0.14.11`），它从 Rive 官方 artifacts 服务器下载**按平台**的预编译库：

```
https://rive-flutter-artifacts.rive.app/rive_native_versions/<ver>/rive_native_artifacts_linux.zip
```

这个 zip 里的 `librive_native.a` 等是 `ELF 64-bit x86-64`，在 arm64 上链接会报
`skipping incompatible librive_native.a` / `找不到 -lrive_native`。
Flutter 引擎本身的 arm64 产物是好的（`linux-arm64-flutter-gtk` 能正常下载、链接除 rive 外都成功），
**只卡在 rive_native 这一个第三方预编译库**。

可行路径：

1. **在 x86_64 Linux / CI 上打包桌面版**（`platforms/linux/package.sh`，CI 的 `app-linux` job 即如此）；
2. 等 Rive 上游发布 arm64 Linux 静态库，或从 rive-flutter monorepo 源码自行构建（需要 premake5 等，未验证）；
3. 本机只做 `flutter analyze` / `flutter test` + 后端本机构建。

### 5.2 `flutter build apk`：官方 NDK 没有 aarch64 主机工具链

除 NDK 外，SDK 的 **build-tools 也是 x86_64**（`aapt2`/`zipalign`/`d8`/`r8`，见上一节实测）。
另外用 HTTP Range 检查过 NDK 包内容：`ndk;27.2.12479018`（r27c）、`29.0`（r29）、`30.0`（r30）
的 Linux 包内都只有：

```
toolchains/llvm/prebuilt/linux-x86_64/
```

没有 `linux-aarch64`。而 `app` 的 Android 构建需要 NDK（`ndkVersion = 27.2.12479018`，
`live2d_flutter` / `rive_native` 都有 native 代码），加上 build-tools 的 x86_64 限制，
因此**在 arm64 宿主上无法产出 APK**。
`platforms/android/build-ffi.sh` 里的 `llvm-strip` 路径也写死了 `linux-x86_64`。

可行路径：

1. **在 x86_64 主机或 GitHub Actions 上打 APK**（CI 的 Android job 已配置）；
2. 本机只做 API/单元测试、后端联调（Client 模式连局域网里的 `chatvvd`）。

## 6. 自检清单

```bash
# 后端
cmake --preset linux-arm64 && cmake --build build/linux-arm64 -j3
ctest --test-dir build/linux-arm64 --output-on-failure

# Flutter
flutter --version          # 3.44.2 / Dart 3.12.2 / arm64
cd app && flutter analyze && flutter test

# Android 工具
java -version              # 17
sdkmanager --list_installed
adb version
```

`flutter doctor` 预期：`Linux toolchain`、`Connected device (linux-arm64)`、`Network` 通过，
`Android toolchain` 依赖 SDK 配置；`Chrome` 只在做 web 时才需要。
`eglinfo` 警告（缺 `mesa-utils`）不影响构建。

## 7. 备注

- `~/.gitconfig` 里原有的 `http.proxy=127.0.0.1:7890` 在本机没有对应进程，会让 `git clone github.com` 直接失败；
  本文的下载都走 `curl` 绕开了它。要用 git 访问 GitHub 时先确认代理已启动，或临时覆盖：
  `git -c http.proxy= -c http.https://github.com.proxy= clone ...`。
- 内存只有 10 GiB（可用约 3–4 GiB）时，并行度取 2–3；Flutter 首次构建和 llama.cpp 同时编译容易触发 swap。
- 磁盘：Flutter SDK + pub 缓存 + Android SDK 约 2.5 GB。

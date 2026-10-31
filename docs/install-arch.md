# Arch Linux 开发/构建环境（不依赖 Android Studio）

> 适用：Arch Linux x86_64（aarch64 类似，AUR/官方包按架构取）。
> 目标：编 C++ server、跑 Flutter Android/Linux、给 Live2D 做真机测试。
> **不安装 Android Studio**；Android SDK 用 Google 官方 command-line tools 手动管理。
> 版本是 2026-10 的参考值；以 `flutter doctor` / `sdkmanager --list` 的实际提示为准。

## 0. 先决条件

- 建议 30 GB 以上空闲（Android SDK + Gradle + Flutter 缓存）。
- 有可用的 AUR helper（`paru`/`yay`）；没有就手动 `git clone` AUR + `makepkg -si`。
- Android 真机：开启开发者选项/USB 调试；装官方 `android-udev`。
- 不需要 Android Studio，也不需要 AUR 的 `android-sdk` 包；SDK 目录自己管。

## 1. 基础工具 + C++ 后端

```bash
sudo pacman -Syu --needed \
  base-devel clang cmake ninja git curl openssl sqlite pkgconf \
  python jq github-cli unzip zip
```

- 后端用系统库：`sqlite`（头文件）、`curl`、`openssl`；CMake 会 `find_package`。
- 不需要 vcpkg（Linux/macOS）；vcpkg 只在 Windows CI/交叉编译时用。
- `clang` + `ninja` 与 `CMakePresets.json` 一致。

验证：

```bash
clang++ --version
cmake --version
ninja --version
cmake --preset dev
cmake --build --preset dev
ctest --preset dev
```

## 2. Flutter（不装 Android Studio）

### 方案 A：AUR（推荐）

```bash
paru -S --needed flutter
```

当前 AUR 参考版本：以 AUR 实际为准；本机实测 Flutter **3.44.2**。
如果 AUR 的 Flutter 与系统 Dart 冲突，先移除独立 `dart`，或改用方案 B。
不要安装 `android-studio`；下面手动装 SDK。

### 方案 B：官方 tarball（可控版本）

1. 从 https://docs.flutter.dev/get-started/install/linux 下载 stable 的
   `flutter_linux_*_stable.tar.xz`。
2. 解压到固定目录，例如 `~/development/flutter`。
3. 加入 PATH（写进 `~/.zshrc` 或 `~/.bashrc`）：

```bash
export PATH="$PATH:$HOME/development/flutter/bin"
```

4. 检查：

```bash
flutter --version
flutter doctor -v
```

## 3. Android SDK / NDK（全手动）

### 3.1 官方依赖

```bash
sudo pacman -S --needed android-tools android-udev jdk17-openjdk
```

- `android-tools`：adb/fastboot（系统包；SDK 的 platform-tools 会覆盖更高版本，PATH 顺序见下）。
- `android-udev`：真机 udev 规则。
- `jdk17-openjdk`：Gradle/AGP 需要 JDK 17。

### 3.2 下载并安装 command-line tools

Google 官方下载页（**不是 Android Studio**）：
https://developer.android.com/studio#command-line-tools-only

当前 Linux 包（2026-10 核对）：

```bash
export ANDROID_HOME="$HOME/Android/Sdk"
export ANDROID_SDK_ROOT="$ANDROID_HOME"
export JAVA_HOME=/usr/lib/jvm/java-17-openjdk
mkdir -p "$ANDROID_HOME/cmdline-tools"

cd /tmp
curl -fLO https://dl.google.com/android/repository/commandlinetools-linux-15859902_latest.zip
rm -rf commandlinetools
unzip -q commandlinetools-linux-15859902_latest.zip -d commandlinetools

# 必须是 cmdline-tools/latest/bin/sdkmanager 这一层
rm -rf "$ANDROID_HOME/cmdline-tools/latest"
mv commandlinetools/cmdline-tools "$ANDROID_HOME/cmdline-tools/latest"
```

如果上面的版本号 404，去官方页面复制最新的 `commandlinetools-linux-*_latest.zip` 链接替换。

把环境变量写进 shell 配置（zsh 示例，bash 改 `~/.bashrc`）：

```bash
cat >> ~/.zshrc <<'EOF'
export ANDROID_HOME="$HOME/Android/Sdk"
export ANDROID_SDK_ROOT="$ANDROID_HOME"
export JAVA_HOME=/usr/lib/jvm/java-17-openjdk
export PATH="$PATH:$ANDROID_HOME/cmdline-tools/latest/bin:$ANDROID_HOME/platform-tools"
EOF
source ~/.zshrc
```

### 3.3 接受许可 + 安装 SDK 组件

```bash
yes | sdkmanager --licenses

sdkmanager --install \
  "platform-tools" \
  "platforms;android-36" \
  "build-tools;36.0.0" \
  "ndk;27.2.12479018" \
  "cmake;3.22.1"

sdkmanager --list_installed
```

- `platforms;android-36` / `build-tools;36.0.0` 是 Flutter 3.44 的要求；如果 `flutter doctor`
  提示 36.1/37 或更高，按提示装对应版本。
- `flutter_live2d` 需要 **NDK + CMake**，版本按插件/Flutter 要求调整。
- `platform-tools` 必须在 PATH 里；否则 `adb` 用系统的 `android-tools` 版本。

### 3.4 让 Flutter 找到 SDK

```bash
flutter config --android-sdk "$ANDROID_HOME"
flutter doctor --android-licenses
flutter doctor -v
```

- `flutter doctor` 的 Android toolchain 应显示 SDK/NDK 路径，而不是 “cmdline-tools component is missing”。
- 如果 `flutter doctor` 仍找不到，检查 `ANDROID_HOME` 是否在当前 shell 生效：
  `echo $ANDROID_HOME`、`which sdkmanager`。
- Flutter 生成 Android 工程后会写 `android/local.properties` 的 `sdk.dir`；如果没生成，
  手动写：`sdk.dir=$HOME/Android/Sdk`。

### 3.5 真机 / 模拟器（可选）

真机：

```bash
adb devices
```

- 看不到设备：确认 `android-udev` 已装、USB 调试已开、换线/端口；必要时重新插拔。

模拟器（可选，需要 KVM）：

```bash
sudo gpasswd -a "$USER" kvm   # 重新登录生效
ls -l /dev/kvm

sdkmanager --install "emulator" "system-images;android-36;google_apis;x86_64"
avdmanager create avd -n chatvv -k "system-images;android-36;google_apis;x86_64" -d pixel_7
flutter emulators
```

## 4. Linux 桌面 Flutter

```bash
sudo pacman -S --needed gtk3 libsecret pkgconf
flutter config --enable-linux-desktop
flutter devices
```

- `gtk3`：Linux embedder。
- `libsecret`：`flutter_secure_storage` 的 Linux 后端。
- 桌面版**没有** `flutter_live2d` 支持；v1 先用静态头像。后续按“多套 adapter”补
  `DesktopLive2D`（Cubism Native/FFI 或 WebView 兜底）。

## 5. macOS / iOS

Arch 上不能构建 iOS。需要一台 macOS + Xcode：

- macOS：Xcode + Command Line Tools；`flutter doctor`。
- iOS：CocoaPods（`brew install cocoapods`）、Xcode license、签名团队。
- 可以依赖 GitHub Actions 的 macOS runner 做 CI 构建，但 iOS 发布签名仍需 Apple 证书。

## 6. 3D（以后）

- v1 不做 3D；不需要额外系统包。
- 如果后续上 VRM：需要 3D 渲染器（`thermion_flutter`/`three_dart`/自写），
  Android NDK/CMake 已具备；iOS 需要 Xcode。
- VRM 模型授权见 `reference/avatar-tech/VRM-3D.md`，未拿到授权前不要打包。

## 7. GitHub CLI / CI

```bash
gh auth login
# 可选：本地跑 GitHub Actions
paru -S --needed act
sudo pacman -S --needed podman   # act 的后端之一
```

- CI 在 GitHub 上跑；backend job 不需要本机 Android SDK。
- 本机要跑 Flutter/Android 构建才需要第 2–3 节的 SDK/NDK。

## 8. 验证清单

```bash
# 后端
cmake --preset dev && cmake --build --preset dev && ctest --preset dev

# Flutter / Android toolchain
flutter doctor -v
flutter devices
adb devices

# app scaffold 后
cd app
flutter pub get
flutter analyze
flutter build apk --debug
```

## 9. 常见问题

| 问题 | 处理 |
|---|---|
| `flutter: command not found` | 把 `flutter/bin` 加进 PATH，重开 shell |
| `sdkmanager: command not found` | 检查 `$ANDROID_HOME/cmdline-tools/latest/bin` 在 PATH；目录层级必须是 `latest/bin` |
| `cmdline-tools component is missing` | command-line tools 没放到 `latest`，或 `flutter config --android-sdk` 指错 |
| Android licenses 未接受 | `yes \| sdkmanager --licenses`，再 `flutter doctor --android-licenses` |
| `flutter doctor` 找错 SDK | `flutter config --android-sdk "$ANDROID_HOME"`，重开 shell |
| Java 版本报错 | `export JAVA_HOME=/usr/lib/jvm/java-17-openjdk`，确认 `java -version` |
| `adb` 看不到设备 | 装 `android-udev`，开 USB 调试，换线/端口 |
| `flutter build apk` 卡在 Gradle | 首次下载依赖；检查网络/代理 |
| `flutter_live2d` 编译失败 | 确认 NDK + CMake 已装，`sdkmanager --list_installed` 有 `ndk`/`cmake` |
| 桌面没有 Live2D | `flutter_live2d` 只覆盖 Android/iOS；桌面 v1 静态，后续补 adapter |
| CMake 找不到 SQLite/CURL | 装 `sqlite curl openssl pkgconf`，清空 `build/` 重配 |
| AUR Flutter 与 dart 冲突 | 移除独立 `dart`，或用官方 tarball |

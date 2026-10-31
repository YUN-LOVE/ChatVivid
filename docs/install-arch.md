# Arch Linux 开发/构建环境

> 适用：Arch Linux x86_64（aarch64 类似，AUR/官方包按架构取）。
> 目标：能编 C++ server、能跑 Flutter Android/Linux、能给 Live2D 做真机测试。
> 版本是 2026-10 的参考值；以 `flutter doctor` / `sdkmanager --list` 的实际提示为准。

## 0. 先决条件

- 建议 30 GB 以上空闲（Android SDK + Gradle + Flutter 缓存很占地方）。
- 有可用的 AUR helper（`paru`/`yay`）；没有就手动 `git clone` + `makepkg -si`。
- 如果要 Android 真机：开启开发者选项/USB 调试；装 `android-udev` 规则。

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

## 2. Flutter

### 方案 A：AUR（推荐，省事）

```bash
paru -S --needed flutter android-studio android-udev
```

当前 AUR 版本参考：`flutter 3.41.2-3`、`android-studio 2026.2.2.8-1`。
如果 AUR 的 Flutter 与系统 Dart 冲突，先移除独立 `dart`，或改用方案 B。

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

## 3. Android SDK / NDK

Android Studio 的 SDK Manager 最稳；也可以用 AUR 的 `android-sdk` + `sdkmanager`。

```bash
# 官方 adb/fastboot + JDK
sudo pacman -S --needed android-tools jdk17-openjdk

# 如果使用 AUR 的 command line tools
paru -S --needed android-sdk android-sdk-platform-tools android-sdk-build-tools

# 安装平台、构建工具、NDK、CMake（flutter_live2d 需要 NDK/CMake）
sdkmanager --install \
  "platform-tools" \
  "platforms;android-35" \
  "build-tools;35.0.0" \
  "ndk;27.2.12479018" \
  "cmake;3.22.1"

flutter doctor --android-licenses
flutter doctor -v
```

- 版本说明：`android-35` / `35.0.0` / `NDK 27.2` 是参考值。Flutter 3.41 可能提示
  Android 36 或更高 build-tools；按 `flutter doctor` 的提示装对应版本即可。
- `flutter_live2d` 通过 NDK + CMake 编译 native GL 插件；Android 最低 API 24。
- `flutter build apk` 第一次会下载 Gradle 依赖，比较慢。
- 真机权限：装 AUR 的 `android-udev`，重新插拔设备；`adb devices` 应能看到。

## 4. Linux 桌面 Flutter

```bash
sudo pacman -S --needed gtk3 libsecret pkgconf
flutter config --enable-linux-desktop
flutter devices
```

- `gtk3`：Linux embedder。
- `libsecret`：`flutter_secure_storage` 的 Linux 后端。
- 桌面版**没有** `flutter_live2d` 支持；v1 先用静态头像。用户接受多套代码，后续可补 `DesktopLive2D`（Cubism Native/FFI 或 WebView）。

## 5. macOS / iOS

Arch 上不能构建 iOS。需要一台 macOS + Xcode：

- macOS：Xcode + Command Line Tools；`flutter doctor`。
- iOS：CocoaPods（`brew install cocoapods`）、Xcode license、签名团队。
- 可以只依赖 GitHub Actions 的 macOS runner 做 CI 构建，但 iOS 发布签名仍需要 Apple 证书。

## 6. 3D（以后）

- v1 不做 3D；不需要额外系统包。
- 如果 v2 上 VRM：需要 3D 渲染器（`thermion_flutter`/`three_dart`/自写），
  以及 Android NDK/CMake（已有）；iOS 需要 Xcode。
- VRM 模型授权见 `reference/avatar-tech/VRM-3D.md`，未拿到授权前不要打包。

## 7. GitHub CLI / CI

```bash
gh auth login
# 可选：本地跑 GitHub Actions
paru -S --needed act
sudo pacman -S --needed podman   # act 的后端之一
```

- CI 在 GitHub 上跑，不需要在本机装 Android SDK 才能跑 backend job。
- 本机要跑 Flutter job 才需要上面的 Android SDK/NDK。

## 8. 验证清单

```bash
# 后端
cmake --preset dev && cmake --build --preset dev && ctest --preset dev

# Flutter
flutter doctor -v
flutter devices
cd app && flutter pub get && flutter analyze

# Android 设备
adb devices
```

## 9. 常见问题

| 问题 | 处理 |
|---|---|
| `flutter: command not found` | 把 `flutter/bin` 加进 PATH，重开 shell |
| Android licenses 未接受 | `flutter doctor --android-licenses` |
| `adb` 看不到设备 | 装 `android-udev`，开 USB 调试，换线/端口 |
| `flutter build apk` 卡在 Gradle | 首次下载依赖；检查网络/代理 |
| `flutter_live2d` 编译失败 | 确认 NDK + CMake 已装，`flutter doctor -v` 看 Android toolchain |
| 桌面没有 Live2D | `flutter_live2d` 只覆盖 Android/iOS；桌面 v1 静态，后续补独立 adapter |
| CMake 找不到 SQLite/CURL | 装 `sqlite curl openssl pkgconf`，清空 `build/` 重配 |
| AUR Flutter 与 dart 冲突 | 移除独立 `dart`，或用官方 tarball |

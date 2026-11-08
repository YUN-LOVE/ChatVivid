# Android 16 KB / 签名验证

Android 15+（含 Android 17）要求 16 KB page-size 兼容。

## 已完成

- `chatvv_ffi` 在 Android 链接时增加：
  - `-Wl,-z,max-page-size=16384`
  - `-Wl,-z,common-page-size=16384`
- 检查 APK 内所有 arm64 ELF 的 LOAD align：
  - `libchatvv_ffi.so` / `libc++_shared.so` / `libflutter_live2d.so` / `librive_native.so` = `0x4000`
  - `libflutter.so` = `0x10000`
- `scripts/verify-android-apk.sh` 同时验证：
  - `zipalign -c -P 16 -v 4`
  - `apksigner verify --print-certs`
  - 每个 native ELF 的 LOAD 对齐
- CI Android job 已接入该脚本

## 签名

- `android/key.properties`（不存在时使用 debug 签名，仅测试）
- 示例：`android/key.properties.example`
- 生产构建提供真实 keystore 后，release 自动使用 release signingConfig
- CI 目前没有 secrets，因此构建产物是 debug 签名；发布前需要配置 keystore

## 目标 SDK

当前使用 Flutter 的 `targetSdkVersion`（36）。Android 17 的 API 37 还没有对应的稳定编译 SDK；
16 KB 页对齐和签名验证是当前可落地的 Android 17 兼容项。

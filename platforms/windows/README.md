# platforms/windows/

Windows 桌面适配：Flutter Windows bundle + `chatvv_ffi.dll` 打包（MSVC + vcpkg）。

## 文件

| 文件 | 用途 |
|---|---|
| `package.ps1` | vcpkg（`x64-windows-static`）装 curl/sqlite3 → CMake `Visual Studio 17 2022` 构建 `chatvv_ffi` → `flutter build windows --release` → `artifacts/chatvv-windows-x64.zip` |

## 本地构建

```powershell
# 需要 Visual Studio 2022（C++ 工作负载）、vcpkg、Flutter、Rust（x86_64-pc-windows-msvc）
git clone https://github.com/microsoft/vcpkg C:\vcpkg
C:\vcpkg\bootstrap-vcpkg.bat
$env:VCPKG_ROOT = "C:\vcpkg"

.\platforms\windows\package.ps1      # 旧入口 .\scripts\package-desktop-windows.ps1 等价
```

## Vulkan

- CI 用 `jakoch/install-vulkan-sdk-action@v1` 装 LunarG Vulkan SDK（headers + loader + glslc +
  SPIRV-Headers），并传 `CHATVV_VULKAN=ON`。
- 运行时依赖 `vulkan-1.dll`（显卡驱动自带）；没有 Vulkan 的机器用 `CHATVV_VULKAN=OFF` 重新打包。
- 本地默认 `AUTO`：装了 SDK 就启用，否则 CPU + warning。

## read-aloud

- 默认 **static** 链接进 `chatvv_ffi.dll`（Rust MSVC target），不需要额外分发 DLL。
- 若改为 shared，需要把 `read_aloud.dll` 复制到 Flutter 输出目录并确认 MSVC runtime 分发。

## CI 引用

ci.yml / release.yml 的 `app-package` 矩阵 `windows` 条目 → `./platforms/windows/package.ps1`。
后端 Windows job 直接走 `windows-x64` preset + vcpkg 动态库（与 app 打包的 static triplet 不同，
避免 app bundle 依赖额外 DLL）。产物名 `chatvv-app-windows`。

## 已知限制

- 只支持 x64；Windows arm64 未验证、未进 CI。
- 后端 CI 测试只跑 `core`（smoke 是 bash 脚本，Windows 没有对应实现）。
- 之前单独的 `windows-diag.yml` 已归档删除；需要诊断时在 `ci.yml` 用
  `workflow_dispatch` + `platforms=windows` 手动跑。

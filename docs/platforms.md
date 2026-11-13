# 平台支持

> 状态：Linux x86_64 已在本地验证；Linux aarch64 / macOS arm64 / Windows x64 由 CI 覆盖。
> 目标：**64 位 Linux、macOS、Windows，x86_64 与 aarch64/arm64。**

---

## 1. 支持矩阵

| 平台 | 架构 | 状态 | 说明 |
|---|---|---|---|
| Linux | x86_64 | ✅ 本地验证 | 系统 SQLite + libcurl |
| Linux | aarch64 | ✅ CI（原生 arm64 runner） | 树莓派 5 / Jetson / ARM 服务器 |
| macOS | arm64 | ✅ CI | Apple Silicon，AppleClang |
| macOS | x86_64 | ✅ 理论支持 | Intel Mac，同一套预设 |
| Windows | x86_64 | ✅ CI | MSVC 2022 + vcpkg |
| Windows | arm64 | ⚠️ 未验证 | 代码无架构假设，但未进 CI |
| 32 位 / 大端 | — | ❌ 不支持 | 只保证 64 位小端 |

---

## 2. 依赖

代码本身只依赖 C++23 标准库；外部依赖：

- **SQLite 3**（事实源）
- **libcurl**（调用云端 LLM / 以后的 MCP HTTP）
- **Rust / cargo**（编译 vendored 的 `read_aloud` TTS 库；本机/CI 都需要）
- **Vulkan SDK**（可选：ggml 的 Vulkan 后端；`CHATVV_VULKAN=AUTO` 缺 SDK 时回退 CPU，
  CI 传 `-DCHATVV_VULKAN=ON` 强制。Apple 暂不启用 Vulkan）

加上三个固定版本的单头文件（nlohmann/json、toml++、cpp-httplib），已放在 `third_party/`，不依赖网络。

### Linux

Debian / Ubuntu：

```bash
sudo apt install clang cmake ninja-build libsqlite3-dev libcurl4-openssl-dev
```

Arch：

```bash
sudo pacman -S clang cmake ninja sqlite curl rustup
# 需要 Vulkan 后端时（可选）：
sudo pacman -S vulkan-devel shaderc
```

### macOS

```bash
xcode-select --install
brew install cmake ninja curl
```

macOS 自带 SQLite，`native-tls` 用系统 Security 框架，不需要 OpenSSL。Rust 用 rustup 安装：
`curl https://sh.rustup.rs -sSf | sh`。Vulkan 暂不启用（Apple 后端保持 CPU/Metal）。
libcurl 建议用 Homebrew 的版本（系统版本被标记为 deprecated）：

```bash
cmake --preset macos-arm64 -DCURL_ROOT=$(brew --prefix curl)
```

### Windows

需要 Visual Studio 2022（含 C++ 工作负载）和 vcpkg：

```powershell
git clone https://github.com/microsoft/vcpkg C:\vcpkg
C:\vcpkg\bootstrap-vcpkg.bat
$env:VCPKG_ROOT = "C:\vcpkg"
C:\vcpkg\vcpkg.exe install --triplet x64-windows   # 读取 vcpkg.json
cmake --preset windows-x64
cmake --build --preset windows-x64
```

默认 `x64-windows` 是动态库 triplet，运行 `chatvvd.exe` 时需要 `libcurl.dll`、`sqlite3.dll` 在 PATH 或同目录。想要单文件分发，改用 `x64-windows-static`，并把预设里的 triplet 一起改掉。

---

## 3. 构建

| 目标 | 命令 |
|---|---|
| Linux x86_64（开发） | `cmake --preset dev && cmake --build --preset dev` |
| Linux x86_64（发布） | `cmake --preset release && cmake --build --preset release` |
| Linux aarch64（原生） | `cmake --preset linux-arm64 && cmake --build --preset linux-arm64` |
| macOS arm64 | `cmake --preset macos-arm64 && cmake --build --preset macos-arm64` |
| Windows x64 | `cmake --preset windows-x64 && cmake --build --preset windows-x64` |
| Linux aarch64（交叉） | `cmake --preset arm64-cross && cmake --build --preset arm64-cross` |

测试：

```bash
ctest --preset dev
```

Windows 只跑 `core`（smoke 是 bash 脚本）；Linux/macOS 跑 `core + smoke`。

---

## 4. aarch64 的两种路径

### 4.1 在设备上原生构建（推荐）

树莓派 5、Jetson 或 ARM 服务器上直接：

```bash
sudo apt install clang cmake ninja-build libsqlite3-dev libcurl4-openssl-dev
cmake --preset linux-arm64
cmake --build --preset linux-arm64
ctest --preset linux-arm64
```

默认不加 `-march`，产物对所有 ARMv8 设备可用。确认只在 Pi 5 上跑，可以自行加：

```bash
cmake --preset linux-arm64 -DCMAKE_CXX_FLAGS="-march=armv8.2-a+dotprod+fp16"
```

### 4.2 交叉编译（x86 主机 → aarch64）

要求：

- `aarch64-linux-gnu-g++`（Debian/Ubuntu：`g++-aarch64-linux-gnu`）
- 一个 aarch64 sysroot（交叉工具链自带 glibc；curl/sqlite 由 vcpkg 编译）
- vcpkg，并且设置 `VCPKG_ROOT`

```bash
export VCPKG_ROOT=~/vcpkg
cmake --preset arm64-cross
cmake --build --preset arm64-cross
```

预设会把 `arm64-linux` triplet 和 `cmake/toolchains/aarch64-linux-gnu.cmake` 一起交给 vcpkg：curl 和 sqlite 会按 arm64 重新编译。

在 x86 主机上跑测试需要 qemu：

```bash
qemu-aarch64 -L /usr/aarch64-linux-gnu ./build/arm64-cross/chatvv_tests
```

`ctest` 不配置交叉测试，因为运行时依赖目标机的动态库；用 CI 的原生 arm64 runner 做真实测试。

---

## 5. 源码里的可移植性处理

| 问题 | 处理 |
|---|---|
| `localtime_r` 是 POSIX | Windows 走 `localtime_s`，其他走 `localtime_r` |
| `std::format` 在旧 MSVC 上不稳 | 日志时间戳改用 `snprintf`，不再依赖 `<format>` |
| Windows 套接字 | 链接 `ws2_32`，定义 `WIN32_LEAN_AND_MEAN` / `NOMINMAX` |
| 路径分隔符 | `std::filesystem::path` 拼 `data/chatvv.db`、`chatvv.log` |
| `long` 在 Windows 是 32 位 | HTTP 载荷大小用 `CURLOPT_POSTFIELDSIZE_LARGE` + `curl_off_t` |
| 编译告警开关 | MSVC 用 `/W4 /permissive- /utf-8`，Clang/GCC 用 `-Wall -Wextra -Wpedantic` |
| 信号 | Windows 只有 Ctrl+C（`SIGINT`）；服务化以后再做 |

代码没有：

- 架构相关的 intrinsics / 内联汇编
- 依赖 `long` 宽度或指针宽度的逻辑（统一 `int64_t` / `size_t`）
- 大端假设
- 依赖 `/proc`、`epoll` 等 Linux 专有接口（httplib 自己处理 socket 抽象）

**小端假设**：目前消息和数据库都是文本/整数，没有跨平台的二进制向量格式。等 memory 把 f32 embedding 落盘时，需要固定 little-endian，或在读写时显式转换。

---

## 6. CI

CI 已改为**按改动路径选择平台**（`platforms/<p>/**` 只触发该平台；共享路径触发全部启用平台），
release 用 tag 选择平台子集；完整规则、tag 表与依赖清单见 [ci-cd.md](ci-cd.md)。平台适配脚本在
`platforms/<platform>/`（`scripts/` 保留兼容转发入口）。

| Job | Runner | 验证内容 |
|---|---|---|
| `detect affected platforms` | `ubuntu-latest` | 改动分类 → 输出平台矩阵（`platforms/`、backend/app 子集） |
| `lint / workflows & scripts` | `ubuntu-latest` | workflow YAML + 脚本静态检查；纯文档改动只跑这个 |
| `backend / linux x64` | `ubuntu-latest` | `dev` preset 构建 + `core` + `smoke`，Vulkan ON |
| `backend / linux arm64` | `ubuntu-24.04-arm` | `linux-arm64` preset 构建 + 测试（原生 arm64），Vulkan ON |
| `backend / macos arm64` | `macos-14` | `macos-arm64` 构建 + 测试；CPU/Metal，Vulkan OFF；默认被 `ENABLE_MACOS_RUNNERS` 成本开关跳过 |
| `backend / windows x64` | `windows-2022` | MSVC + vcpkg，构建 + `core`，Vulkan ON |
| `app / <platform>` | 按平台 | Android APK / Linux / Windows / macOS desktop 打包（动态矩阵） |

说明：

- Linux/Windows/Android 在 CI 传 `-DCHATVV_VULKAN=ON` 并安装对应 Vulkan SDK/glslc；
  macOS（以及未启用的 iOS）明确 `-DCHATVV_VULKAN=OFF`，保持 CPU/Metal（MoltenVK 未接入）。
- iOS/web 需要先 scaffold `app/ios`、`app/web`，之后才会自动进入 CI/release 矩阵。
- 如果账号没有 arm64 runner，把 `backend / linux arm64` 换成 `arm64-cross` 构建 + qemu 跑测试；
  或者只在自建 ARM 设备上跑。

---

## 7. 发布物

- Linux/macOS：单个 `chatvvd` + `config.example.toml` + `data/` 目录；`cmake --install build/release --prefix /opt/chatvv`。
- Windows：`chatvvd.exe` + 对应的 DLL（或改用 static triplet）+ 配置。
- 模型文件（本地嵌入）以后单独分发，不塞进二进制。

---

## 8. 已知限制

- 交叉编译只在 vcpkg + `aarch64-linux-gnu` 组合下验证过流程，没有本地跑通（本机无 ARM 工具链）。
- Windows 只验证 core 测试；smoke 是 bash 脚本，后续可补 PowerShell/Python 版。
- Windows 路径按 UTF-8 处理，非 ASCII 路径没有专门测试；建议数据目录用 ASCII。
- macOS x86_64 没有单独 CI job；同一份代码、同一套预设，理论上可用。
- 32 位和大端不支持，也不打算支持。
- **Linux aarch64 私有环境受限**：C++ 后端可在 aarch64 本机原生构建并跑测试；
  但 `flutter build linux` 会被 `rive_native` 的 x86_64 预编译静态库卡住，
  `flutter build apk` 会因官方 NDK 只提供 `linux-x86_64` 主机工具链而无法进行。
  Android 包和桌面包请在 x86_64 主机/CI 上构建，详见
  [install-arch-aarch64-chroot.md](install-arch-aarch64-chroot.md)。

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

代码本身只依赖 C++23 标准库；外部依赖只有两个运行库：

- **SQLite 3**（事实源）
- **libcurl**（调用云端 LLM / 以后的 MCP HTTP）

加上三个固定版本的单头文件（nlohmann/json、toml++、cpp-httplib），已放在 `third_party/`，不依赖网络。

### Linux

Debian / Ubuntu：

```bash
sudo apt install clang cmake ninja-build libsqlite3-dev libcurl4-openssl-dev
```

Arch：

```bash
sudo pacman -S clang cmake ninja sqlite curl
```

### macOS

```bash
xcode-select --install
brew install cmake ninja curl
```

macOS 自带 SQLite。libcurl 建议用 Homebrew 的版本（系统版本被标记为 deprecated）：

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

`.github/workflows/ci.yml`：

| Job | Runner | 验证内容 |
|---|---|---|
| `linux-x64` | `ubuntu-latest` | 构建 + `core` + `smoke` |
| `linux-arm64` | `ubuntu-24.04-arm` | 构建 + 测试（原生 arm64） |
| `macos-arm64` | `macos-14` | 构建 + 测试 |
| `windows-x64` | `windows-latest` | MSVC + vcpkg，构建 + `core` |

如果账号没有 arm64 runner，把 `linux-arm64` 换成 `arm64-cross` 构建 + qemu 跑测试；或者只在自建 ARM 设备上跑。

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

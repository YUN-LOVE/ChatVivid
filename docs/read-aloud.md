# read-aloud TTS（Rust C ABI 后端）

chatvv 的语音合成（TTS）已改为使用 vendored 的
[`read_aloud`](https://github.com/naskopw/read_aloud) v0.3.3（Rust 实现，暴露 C ABI），
由 C++ 封装成 `chatvv::Synthesize()` 供 FFI `chatvv_tts_synthesize` 调用。
原来的手写 C++ Edge WebSocket 客户端（`src/tts/edge_tts.{h,cpp}`，466 行）已删除，
迁移说明见 [edge-tts.md](edge-tts.md)。

- 上游版本：`read-aloud` 0.3.3（固定 tag，源码在 `third_party/read_aloud/`）
- 来源/补丁/校验和：`third_party/read_aloud/VENDORED.chatvv.md`
- 许可：GPL-3.0-only（与仓库根 `LICENSE` 的 GPL-3.0 兼容）

## 1. 调用链

```
Dart  app/lib/features/chat/tts_service.dart
        │  动态库查找 chatvv_tts_synthesize，voice 固定为 "zh-CN-XiaoxiaoNeural"
        ▼
C ABI src/ffi/chatvv_ffi.cpp : chatvv_tts_synthesize(text, voice, output_path, error_json)
        │  参数校验；voice 为空时传默认值
        ▼
C++  src/tts/synthesize.{h,cpp} : chatvv::Synthesize(text, voice, output_path)
        │  1. 文本/路径均为空 → 直接返回错误（不联网）
        │  2. 非法 UTF-8 → 直接返回错误（不联网）
        │  3. voice 字符串 → read_aloud Voice 枚举（见第 3 节）
        │  4. read_aloud_text_to_speech(text, voice_enum, nullptr, output_path)
        │  5. 校验输出文件存在且非空（对应旧实现的 "no audio received"）
        ▼
Rust third_party/read_aloud/src/ffi.rs
        │  CStr → &str（空指针/非法 UTF-8/选项尺寸校验）→ catch_unwind
        ▼
Rust src/lib.rs : text_to_speech()
        └─ tungstenite + native-tls 连接
           wss://speech.platform.bing.com/consumer/speech/synthesize/readaloud/edge/v1
           发送 speech.config（audio-24khz-48kbitrate-mono-mp3）与 SSML，收 audio 帧，
           拼接后写入 output_path；`Path:turn.end` 结束
```

`chatvv::Synthesize()` 的返回结构保持旧语义：

```cpp
struct SynthesizeResult {
  bool ok = false;          // 成功标志
  std::string error;        // 失败原因（FFI 会包进 error_json 的 message）
  std::string audio_path;   // 成功时等于 output_path
};
```

除 `Synthesize()` 外，头文件还导出三个无网络依赖的辅助函数（测试/诊断用）：

| 函数 | 说明 |
|---|---|
| `DefaultVoiceName()` | 默认音色 `zh-CN-XiaoxiaoNeural` |
| `ResolveVoiceName(voice)` | 把任意输入解析为规范短名；未知/空回退默认值 |
| `ReadAloudAvailable()` | 本次构建是否编入了 read_aloud（否则为 stub） |

日志（`src/util/log.h`，JSON 行）事件：
`tts_synthesized`、`tts_failed`、`tts_output_missing`、`tts_output_empty`、
`tts_voice_unknown`、`tts_unavailable`、`tts_voice_table_corrupt`。

## 2. read_aloud C ABI（v0.3.3）

头文件由 `build.rs` 用 cbindgen 生成到 cargo target 目录，再由 CMake staging 到
`build/<preset>/read_aloud/include/read_aloud.h`。注意 cbindgen 生成的是**纯 C 头**
（没有 `extern "C"` 保护），C++ 侧必须这样包含：

```cpp
extern "C" {
#include "read_aloud.h"
}
```

导出的 4 个符号：

```c
const char *read_aloud_status_string(enum ReadAloudStatus status);   // 静态串，勿 free
const char *read_aloud_last_error_message(void);                     // 线程内有效，勿 free

enum ReadAloudStatus read_aloud_speech_options_init(
    struct ReadAloudSpeechOptions *options);                         // 填默认值 + size

enum ReadAloudStatus read_aloud_text_to_speech(
    const char *text,                          // UTF-8，非空，可含任意 XML 特殊字符（上游转义）
    enum Voice voice,                          // VOICE_* 枚举值
    const struct ReadAloudSpeechOptions *options,  // 可为 NULL = 服务默认韵律
    const char *file_path);                    // UTF-8 输出 MP3 路径
```

状态码（`ReadAloudStatus`）：

| 值 | 常量 | C++ 侧错误文案 |
|---|---|---|
| 0 | `READ_ALOUD_STATUS_SUCCESS` | — |
| 1 | `READ_ALOUD_STATUS_INVALID_INPUT` | `invalid TTS input: ...` |
| 2 | `READ_ALOUD_STATUS_CONNECTION_FAILED` | `TTS connection failed/timed out: ...` |
| 3 | `READ_ALOUD_STATUS_PROTOCOL_ERROR` | `TTS protocol error: ...` |
| 4 | `READ_ALOUD_STATUS_IO_ERROR` | `TTS I/O error: ...` |
| 255 | `READ_ALOUD_STATUS_INTERNAL_ERROR` | `TTS internal error: ...` |

细节错误串来自 `read_aloud_last_error_message()`（thread-local，下一次同线程调用前有效），
因此 `Synthesize()` 在拿到状态码后立即拷贝。连接错误会按错误文本含
`timed out` / `timeout` / `deadline exceeded` 归类为 "connection timed out"；read_aloud
本身没有超时参数，无法在 C++ 层强制取消。

`ReadAloudSpeechOptions { size, pitch_hz, rate, volume }` 是 size-prefix 结构（向后兼容
ABI）。chatvv 目前传 `NULL` 使用服务默认韵律（与旧 edge_tts 的 `+0Hz/+0%/+0%` 等价）。

## 3. Voice 枚举与 voice 字符串映射

read_aloud 的 `Voice` 是 `#[repr(C)]` 枚举（322 个音色，C 常量 `VOICE_*`，
如 `VOICE_ZH_CN_XIAOXIAO_NEURAL`），而 app/FFI 传的是 Microsoft Edge 音色短名
（如 `zh-CN-XiaoxiaoNeural`）。映射表由脚本从 vendored 源码生成：

- 生成器：`third_party/read_aloud/chatvv-gen-voice-table.py`
  （解析 `src/voices.rs` 的枚举顺序 + `impl From<Voice> for &str`，并用生成的
  `read_aloud.h` 里的 `VOICE_*` 常量交叉校验）
- 产物：`src/tts/read_aloud_voice_table.inc`（322 条，按大小写不敏感名称排序，
  `synthesize.cpp` 用二分查找）

`chatvv::ResolveVoiceName()` 接受的输入形式（全部大小写不敏感，前后空白会去掉）：

| 输入 | 解析结果 |
|---|---|
| `zh-CN-XiaoxiaoNeural` | `zh-CN-XiaoxiaoNeural`（app 默认音色） |
| `zh_CN_XiaoxiaoNeural` | `zh-CN-XiaoxiaoNeural`（下划线转连字符） |
| `ZH-CN-XIAOXIAONEURAL` | `zh-CN-XiaoxiaoNeural` |
| `Microsoft Server Speech Text to Speech Voice (en-US, AriaNeural)` | `en-US-AriaNeural`（上游 `From<Voice>` 返回的完整名） |
| `""` / 仅空白 | `zh-CN-XiaoxiaoNeural`（静默回退） |
| 未知名称（如 `xx-YY-NoSuchNeural`） | `zh-CN-XiaoxiaoNeural` + `tts_voice_unknown` 警告日志 |

覆盖情况：322 个 read_aloud 音色全部可映射，包括 app 默认的
`zh-CN-XiaoxiaoNeural`、全部 `zh-CN`/`zh-TW`/`zh-HK` 音色，以及常见
`en-US-*`（Aria/Ava/Andrew/Emma/Brian/Ana/Christopher/Eric/Guy/Jenny/Michelle/
Roger/Steffan/`*Multilingual`）与 `en-GB-*`（Sonia/Ryan/Thomas/Libby 等）。

更新 read_aloud 版本时重新生成：

```sh
cargo build --release --manifest-path third_party/read_aloud/Cargo.toml
python3 third_party/read_aloud/chatvv-gen-voice-table.py \
  --voices third_party/read_aloud/src/voices.rs \
  --header third_party/read_aloud/target/release/read_aloud.h \
  --out src/tts/read_aloud_voice_table.inc
```

## 4. 构建依赖

| 依赖 | 用途 | 说明 |
|---|---|---|
| Rust stable ≥ 1.80 + cargo | 编译 read_aloud | `Cargo.lock` 里 `openssl` 0.10.82 要求 rustc ≥ 1.80 |
| OpenSSL 开发包 + pkg-config | Linux/Android 的 native-tls | Linux 宿主 `libssl-dev`/`openssl`+`pkgconf`；Android 交叉需要目标 OpenSSL |
| 平台 TLS | Windows/macOS/iOS | native-tls 用 SChannel / Security.framework，无需 OpenSSL |
| CMake ≥ 3.28、Ninja | `cmake/readaloud.cmake` | 通过 `cargo build --locked` 构建 |

`third_party/read_aloud/Cargo.toml` 相对上游只有两处构建配置补丁（不改业务逻辑）：
`crate-type = ["cdylib", "staticlib", "rlib"]`（iOS/静态链接需要 staticlib），
`Cargo.lock` 的 openssl/openssl-sys 升级（支持 OpenSSL 4.x，兼容 3.x）。
详见 `third_party/read_aloud/VENDORED.chatvv.md`。

构建命令就是正常的 CMake 构建，无需手工 cargo：

```sh
cmake --preset dev
cmake --build --preset dev
ctest --preset dev -R tts        # 离线单测：voice 映射/参数校验/ABI 链接
```

## 5. cmake/readaloud.cmake（fragment）

根 `CMakeLists.txt` 在 `project()` 之后 `include(cmake/readaloud.cmake)`，fragment
自动调用 `chatvv_add_read_aloud()`（幂等），创建 IMPORTED 目标：

```cmake
chatvv::read_aloud   # IMPORTED GLOBAL
#  INTERFACE_INCLUDE_DIRECTORIES = build/<preset>/read_aloud/include
#  INTERFACE_COMPILE_DEFINITIONS = CHATVV_HAVE_READ_ALOUD=1
#  IMPORTED_LOCATION / IMPORTED_IMPLIB = 下表的库文件
```

`chatvv_core` 以 `PUBLIC` 链接它，因此 `-DCHATVV_HAVE_READ_ALOUD=1` 与头文件路径会
自动传给 `src/tts/synthesize.cpp` 和 `tests/test_tts.cpp`。若未创建目标
（`CHATVV_ENABLE_READ_ALOUD=OFF`，或没有 cargo 且调用方选择关闭），
`synthesize.cpp` 编译 stub：`Synthesize()` 返回
`TTS backend is not built (read_aloud was disabled at configure time)`，不联网。

主要缓存变量：

| 变量 | 默认 | 说明 |
|---|---|---|
| `CHATVV_ENABLE_READ_ALOUD` | `ON` | `OFF` 时只编译 stub |
| `CHATVV_READ_ALOUD_LINKAGE` | `auto` | `auto` = Android `shared`，其余 `static`；可强制 `static`/`shared` |
| `READ_ALOUD_TARGET` | 空 | 覆盖 cargo target triple（如 `aarch64-linux-android`） |
| `CHATVV_READ_ALOUD_PROFILE` | `auto` | `Debug` 构建 → cargo `debug`，否则 `release`；可强制 |
| `CHATVV_READ_ALOUD_CARGO` | 空 | 显式 cargo 路径（默认 PATH / `$CARGO_HOME/bin`） |
| `CHATVV_READ_ALOUD_OFFLINE` | `OFF` | 给 cargo 加 `--offline` |
| `CHATVV_READ_ALOUD_OPENSSL_DIR` | 空 | 交叉构建的 OpenSSL 前缀（含 `include/openssl`、`lib/libssl*`） |
| `CHATVV_READ_ALOUD_STAGING_DIR` | `${CMAKE_BINARY_DIR}/read_aloud` | staging 目录 |
| `CHATVV_READ_ALOUD_CARGO_TARGET_DIR` | `${CMAKE_BINARY_DIR}/read_aloud/cargo` | `CARGO_TARGET_DIR` |

### staging 路径（CI/打包依赖，稳定不变）

`CMAKE_BINARY_DIR` 在 preset 下是 `build/<presetName>`，所以：

```
build/<preset>/read_aloud/
├── include/read_aloud.h             # cbindgen 生成头
└── lib/
    ├── libread_aloud.a             # staticlib（Linux/Android/macOS/iOS；MSVC 为 read_aloud.lib）
    ├── libread_aloud.so            # cdylib（Linux/Android）
    ├── libread_aloud.dylib         # cdylib（macOS）
    ├── read_aloud.dll              # cdylib（Windows MSVC）
    └── read_aloud.dll.lib          # cdylib 导入库（Windows MSVC）
```

无论 `CHATVV_READ_ALOUD_LINKAGE` 选哪个，cargo 一次构建都会产出 cdylib + staticlib
（Cargo.toml 同时列了两种 crate-type），fragment 会把它们**全部** staging 到该目录；
只是实际链接进 chatvv 的只有选中的那一个。

- Linux/Windows/macOS/iOS：默认 `static`，Rust 代码被链进 `libchatvv_ffi`，
  不需要额外分发 `.so`/`.dll`/`.dylib`。
- Android：默认（CI 显式设 `CHATVV_READ_ALOUD_LINKAGE=shared`）产出
  `libread_aloud.so`，CI/打包脚本
  （`platforms/android/build-ffi.sh`）必须把它和 `libchatvv_ffi.so` 一起拷进
  `app/android/app/src/main/jniLibs/<abi>/`，并校验 16 KB 页对齐
  （`platforms/android/verify-apk.sh` 会检查所有 bundled ELF）。

## 6. 交叉编译 target 与 env

fragment 根据 CMake 工具链自动选择 cargo triple 并设置环境变量：

| 平台 | cargo target triple | TLS | 链接方式 |
|---|---|---|---|
| Linux 宿主（原生） | 不传 `--target`（cargo 用 host triple） | 系统 OpenSSL | static |
| Linux 交叉 aarch64 | `aarch64-unknown-linux-gnu` | 目标 OpenSSL | static |
| Android arm64 | `aarch64-linux-android` | NDK 目标 OpenSSL | shared |
| Android armv7 | `armv7-linux-androideabi` | 同上 | shared |
| Android x86_64 / x86 | `x86_64-linux-android` / `i686-linux-android` | 同上 | shared |
| Windows x64（MSVC） | 原生不传 `--target`（triple `x86_64-pc-windows-msvc`） | SChannel | static |
| Windows arm64（MSVC 交叉） | `aarch64-pc-windows-msvc` | SChannel | static |
| macOS arm64 | 原生 `aarch64-apple-darwin` | Security.framework | static |
| macOS x86_64 | `x86_64-apple-darwin`（Arm Mac 上为交叉） | Security.framework | static |
| iOS device | `aarch64-apple-ios` | Security.framework | static（强制） |
| iOS simulator | `aarch64-apple-ios-sim` / `x86_64-apple-ios` | Security.framework | static（强制） |

自动设置的交叉环境变量（仅 target 编译，不影响宿主 build script）：

- `CARGO_TARGET_<TRIPLE>_LINKER` = CMake 的 C 编译器（Android 即 NDK clang，
  如 `<NDK>/toolchains/llvm/prebuilt/linux-x86_64/bin/aarch64-linux-android24-clang`）
- `CC_/CXX_/AR_/RANLIB_<triple>`（下划线与连字符两种写法）= CMake 工具链二进制，
  供 `openssl-sys` 的 `cc` 探测使用
- `CARGO_TARGET_<TRIPLE>_RUSTFLAGS`：
  - ELF 平台（Linux/Android）`-C relocation-model=pic`（staticlib 要链进共享库）
  - Android 额外 `-Wl,-soname,libread_aloud.so`
    和 16 KB 页对齐参数
    `-Wl,-z,max-page-size=16384 -Wl,-z,common-page-size=16384`
  - Android 静态 OpenSSL 时补 `-lz`
  - macOS `shared` 时 `-Wl,-install_name,@rpath/libread_aloud.dylib`
- Apple：`SDKROOT`、`IPHONEOS_DEPLOYMENT_TARGET` / `MACOSX_DEPLOYMENT_TARGET`
- Linux/Android：`OPENSSL_DIR`、`OPENSSL_STATIC`、`OPENSSL_NO_VENDOR`
  （优先用 `CHATVV_READ_ALOUD_OPENSSL_DIR`，其次 `$OPENSSL_DIR`，再其次
  `$VCPKG_INSTALLED_DIR/$VCPKG_TARGET_TRIPLET` 与 `.vcpkg_installed/<triplet>`）

交叉构建前置条件：

```sh
# Rust 标准库（CI 用 dtolnay/rust-toolchain@stable + targets: ...）
rustup target add aarch64-linux-android armv7-linux-androideabi \
                  x86_64-pc-windows-msvc aarch64-apple-darwin \
                  x86_64-apple-darwin aarch64-apple-ios

# Android/Linux 交叉的 OpenSSL（vcpkg 示例：CI 装 curl[openssl] 时已带 openssl）
export VCPKG_ROOT=$PWD/.vcpkg
$VCPKG_ROOT/vcpkg install --classic --triplet arm64-android \
  --x-install-root=$PWD/.vcpkg_installed "curl[openssl,websockets]" sqlite3
# fragment 会自动发现 .vcpkg_installed/arm64-android；也可显式：
#   -DCHATVV_READ_ALOUD_OPENSSL_DIR=$PWD/.vcpkg_installed/arm64-android
```

若找不到 cargo：configure 阶段直接 `FATAL_ERROR`，文案给出安装 Rust、
`-DCHATVV_READ_ALOUD_CARGO=...` 和 `-DCHATVV_ENABLE_READ_ALOUD=OFF` 三种选择。
若 rustup 存在但目标 std 未安装：configure 阶段提示
`rustup target add <triple>`。交叉构建缺目标 OpenSSL 时也给出可操作的 FATAL。

## 7. CI 需要的 Rust 步骤

每个编译 C++ core 的 job 在 configure 前安装 Rust，并缓存 cargo registry：

```yaml
- uses: dtolnay/rust-toolchain@stable      # 原生 Linux; Windows x64 加 targets: x86_64-pc-windows-msvc
- uses: actions/cache@v4
  with:
    path: |
      ~/.cargo/registry
      ~/.cargo/git
    key: cargo-${{ runner.os }}-${{ hashFiles('third_party/read_aloud/Cargo.lock') }}
    restore-keys: cargo-${{ runner.os }}-
```

Android job 在 `dtolnay/rust-toolchain` 里加
`targets: aarch64-linux-android,armv7-linux-androideabi`（CI 只构建 arm64 时
`aarch64-linux-android` 即可），并在 build 时设
`CHATVV_READ_ALOUD_LINKAGE=shared`；`platforms/android/build-ffi.sh` 会导出 NDK
linker/CC/AR 与 16 KB RUSTFLAGS（fragment 内的同类变量与之等价/覆盖）。
iOS job（若启用）需要 `targets: aarch64-apple-ios`。

## 8. 与旧自研 edge_tts 的差异

| 维度 | 旧实现 `src/tts/edge_tts.{h,cpp}` | 新实现 read_aloud v0.3.3 |
|---|---|---|
| 代码位置 | 仓库内 466 行手写 C++（curl WebSocket、自算 `Sec-MS-GEC`、CS64 混淆、SSML 拼装） | vendored Rust crate，C ABI 封装 |
| TLS/WS | libcurl 的 `curl_ws_*`（部分发行版 libcurl 无 WS 支持，旧文档已记录隐患） | tungstenite + native-tls（OpenSSL/SChannel/Security） |
| 音色 | 任意 voice 字符串透传给服务端 | `Voice` 枚举（322 个），未知字符串回退默认音色 |
| 输出 | mp3 24 kHz 48 kbit/s mono | 相同格式（speech.config 不变） |
| 超时 | 自己控制 connect 10s / 总 45s / 收流 40s 截止 | 上游无超时参数，传输错误按文本归类，C++ 层不能强制取消 |
| 协议维护 | 跟随 Edge 客户端改动手改代码 | 升级 crate 版本（固定 tag，升级需重新生成 voice 表） |
| 错误语义 | `ok/error/audio_path`，无 audio 时 "no audio received" | 保持一致（额外校验输出文件存在且非空） |
| 许可 | GPL-3.0（本仓库） | GPL-3.0-only |

## 9. 服务限制与风险

- read_aloud 是对 **Microsoft Edge Read Aloud** 私有协议的逆向实现，上游 README
  明确声明：Edge 服务端任何协议/鉴权/请求头变化都可能让库失效，即使 C ABI 不变。
  当前固定 v0.3.3；若线上服务变更，需要升级 `third_party/read_aloud` 版本
  （并重新生成 voice 表），或在 C++ 层保留降级路径（app 侧已有系统 TTS 兜底）。
- 需要联网 + 可用的系统时间：`Sec-MS-GEC` 由当前时间派生，时间偏差会 403，
  上游会用响应 `Date` 校正一次时钟偏移（skew retry）。
- 语音列表由 crate 版本固定（322 个），新增音色需要升级 crate；未知音色不会报错，
  会静默回退到 `zh-CN-XiaoxiaoNeural` 并写警告日志。
- 阻塞式调用：`chatvv_tts_synthesize` 在合成期间阻塞调用线程；app 侧
  `tts_service.dart` 已在独立 isolate 里调用，Dart 侧保持不变。
- 输出文件语义：成功后才保证文件非空；上游在连接成功后才创建文件，若中途失败可能
  留下空文件，C++ 层会删除空文件并返回错误。
- Android 需要为 NDK 构建的 OpenSSL（CI 通过 vcpkg `curl[openssl]` 提供）；若只做
  C++ 构建而不希望引入 Rust/OpenSSL，可用 `-DCHATVV_ENABLE_READ_ALOUD=OFF`
  得到只返回明确错误的 stub。

## 10. 许可 / License

read_aloud v0.3.3 以 **GPL-3.0-only** 发布（`third_party/read_aloud/LICENSE`），
与本仓库根目录的 GPL-3.0 兼容。分发二进制时需要遵守 GPL-3.0 的相应义务。

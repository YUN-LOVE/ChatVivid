# ASR（whisper.cpp）

语音转文字（Speech-to-Text）在 native core 内实现，Dart 侧通过 C ABI 调用。
UI 尚未接入，本页描述构建集成、C ABI、Dart 绑定、模型下载与已知风险。

## 1. 组成

| 层 | 位置 | 说明 |
|---|---|---|
| 上游引擎 | `third_party/whisper.cpp/` | vendored whisper.cpp（固定 commit，见 `UPSTREAM.md`），只保留编译必需部分；**不含** ggml |
| 构建 | `cmake/whisper.cmake` | `chatvv_add_whisper()`：设置上游 option 并 `add_subdirectory`，产出静态 `whisper` target |
| C++ 封装 | `src/asr/asr.{h,cpp}` | `chatvv::AsrEngine`：模型加载、WAV/PCM 转写、JSON、日志、CPU 回退 |
| C ABI | `include/chatvv/chatvv.h` + `src/ffi/chatvv_ffi.cpp` | `chatvv_asr_create/destroy/transcribe_file/transcribe_pcm/capabilities` |
| Dart 绑定 | `app/lib/data/asr_api.dart` | `AsrApi` / `AsrEngine`，`DynamicLibrary` + `Isolate.run`，不接 UI |

### 为什么只有一份 ggml

`third_party/llama.cpp` 已经 vendor 了 ggml（0.28.0），根 CMake 会构建
`ggml` / `ggml-base` / `ggml-cpu`（以及 Lead 在 `cmake/ggml-vulkan.cmake` 中统一
开启的 Vulkan 后端）。whisper.cpp 自己的 `CMakeLists.txt` 顶部逻辑是：

```cmake
if (NOT TARGET ggml)      # 父工程已有 ggml 时才跳过下面这段
    ...
    add_subdirectory(ggml)  # 仅在没有父级 ggml 时才编译自带副本
endif()
add_subdirectory(src)
```

因此本仓库：

- 不 vendor `third_party/whisper.cpp/ggml/`（已在 vendor 时删除，切勿恢复）；
- `cmake/whisper.cmake` 必须在 `add_subdirectory(third_party/llama.cpp)` **之后**
  被 `include()`（`chatvv_add_whisper()` 会检查 `TARGET ggml`，缺失时直接
  `FATAL_ERROR`，防止误集成顺序导致重复编译或找不到 ggml）；
- whisper 链接父工程的 `ggml` target，因此 ASR 与 LLM/RAG 共用同一套
  CPU/Vulkan 后端，符号只有一份。

`WHISPER_USE_SYSTEM_GGML=ON` 会在 fragment 中设置（语义记录 + 兼容上游未来改动）；
在本 pin 的 whisper 源码里，只要父工程有 `ggml` target 就不会走
`find_package(ggml)` 分支。

## 2. 版本与 ggml 0.28.0 兼容性

| 项 | 值 |
|---|---|
| whisper.cpp commit | `cfcacb9b35fdbed31f521cab39bc0431509e2761`（upstream `master`，2026-11-05） |
| `WHISPER_VERSION` | 1.9.5-dev（最近 release tag 为 `v1.9.5`，但它是 ggml 0.26.0） |
| whisper 自带 ggml 版本 | **0.28.0**（`ggml/CMakeLists.txt`；未 vendor） |
| 本仓库 llama.cpp ggml 版本 | **0.28.0** |
| 许可 | MIT（`third_party/whisper.cpp/LICENSE`，The ggml authors） |

选这个 commit 的理由：whisper.cpp 在 2026-10-28 把自带 ggml 升到 0.28.0，在
2026-11-05 的 `826098654f6b`（"ggml : bump version to 0.29.0"）进入 0.29 周期。
`cfcacb9b` 是该窗口内最后一个仍为 0.28.0 的 `master` commit，与仓库已有 ggml
同版本；而 `v1.9.5` release tag 仍是 ggml 0.26.0，会造成「whisper 按 0.26 编写、
却链接 0.28」的 API 漂移风险，因此不用。

### 已做的实际验证（本机 aarch64 Arch chroot，CPU-only，无 Vulkan SDK）

1. `/tmp` 独立 scratch CMake 工程：
   - 先 `add_subdirectory(/home/YUN/ChatVivid/third_party/llama.cpp)`（仓库现有
     ggml 0.28.0，`GGML_VULKAN=OFF`、`GGML_OPENMP=OFF`、`GGML_NATIVE=OFF`）；
   - 再 `include(/home/YUN/ChatVivid/cmake/whisper.cmake)` +
     `chatvv_add_whisper()`（即真实 fragment + 真实 vendored 源码，非 probe 目录）；
   - 构建 `whisper` 及依赖目标：`llama`、`ggml`、`ggml-base`、`ggml-cpu`。
2. 结果：configure 成功（日志含 `ggml version: 0.28.0`、
   `whisper.cpp version: 1.9.5-dev`），`libwhisper.a` 编译、链接
   `asr_exec`（可执行）与 `libchatvv_asr_smoke.so`（共享库，验证 PIC）均成功。
   说明 whisper 源码 API 与仓库 ggml 0.28.0 在编译/链接层面兼容。
3. `src/asr/asr.cpp` + `src/util/log.cpp` 在 scratch 工程编译为
   `libchatvv_asr.a` 并通过自写 selftest（见第 7 节）：WAV 16/24/float32 解码、
   重采样、能力 JSON、错误路径；`-Wall -Wextra` 无 warning。
4. `src/ffi/chatvv_ffi.cpp` 用 `clang++ -std=c++23 -fsyntax-only -Wall -Wextra
   -Wpedantic` 检查通过（检查时临时把 TTS include 换成 Lead 正在重构的
   `tts/synthesize.h`，最终 TTS include 由 Lead 集成）。
5. **未验证**：Vulkan 后端（本机无 Vulkan SDK）、macOS CoreML、真机 Android
   Vulkan 驱动、以及带真实模型的端到端转写。这些留给 CI / 手工真机测试；
   不要把它们写成「已通过」。

## 3. 集成方式（根 CMakeLists 需要做的事）

`cmake/whisper.cmake` 只负责 whisper 自身；根构建需要：

```cmake
# 1) 在 cmake/ggml-vulkan.cmake 设置好 GGML_VULKAN 之后、llama 之后 include：
add_subdirectory(third_party/llama.cpp EXCLUDE_FROM_ALL)
include(cmake/whisper.cmake)   # 自动调用 chatvv_add_whisper()（与 readaloud.cmake 约定一致）
# 也可以显式调用，幂等：chatvv_add_whisper()

# 2) chatvv_core 需要 ASR 源文件（由根 CMake 加入）：
add_library(chatvv_core STATIC
  ...
  src/tts/synthesize.cpp    # 现有 TTS
  src/asr/asr.cpp)          # 新增 ASR
target_link_libraries(chatvv_core PUBLIC chatvv_deps llama whisper)
```

根 `CMakeLists.txt` 已按上述方式集成（`include(cmake/whisper.cmake OPTIONAL ...)`
+ `if(TARGET whisper)` 链接）；`src/asr/asr.cpp` 通过 `foreach(_chatvv_optional_source
src/asr/asr.cpp)` 加入 `chatvv_core`。`third_party/whisper.cpp/include` 的 include
路径由 `whisper` target 的 PUBLIC usage requirements 传递，无需重复添加；
whisper 用到的 ggml 头文件来自 llama.cpp 的 `ggml` target。

说明：

- fragment 必须在 llama 之后 include；不要重复 `add_subdirectory(ggml)`，不要
  设置 `GGML_VULKAN`/`GGML_OPENMP` 等 ggml option（由 lead 的
  `cmake/ggml-vulkan.cmake` 统一负责）。
- `whisper` 是 upstream 命名的静态 target，不要重命名。
- fragment 内部 `add_subdirectory(... EXCLUDE_FROM_ALL)`：
  - 只有 `chatvv_core` 链接的 `whisper` 会被编译；上游额外加的 `parakeet`
    target 不参与默认构建；
  - CMake 不会把 EXCLUDE_FROM_ALL 子目录的 install 规则加进根 install，因此
    `cmake --install`（release 打包）不会被 whisper 的 install() 规则污染。
- fragment 关闭 `WHISPER_BUILD_TESTS/EXAMPLES/SERVER` 和 `WHISPER_ALL_WARNINGS`
  （第三方代码），`BUILD_SHARED_LIBS=OFF`；whisper target 强制 C++17 + 无 LTO
  （仓库 release preset 全局开 IPO，但 vendored 代码不走 LTO）。
- whisper 的 CMake 会执行 `find_package(Threads)`；上游 `cmake/build-info.cmake`
  在 vendored 目录里跑 `git rev-parse`，会取到 ChatVivid 仓库的 commit（仅影响
  whisper 编译进二进制的版本信息，无功能影响）。

## 4. C ABI

声明在 `include/chatvv/chatvv.h`（`chatvv_asr` opaque + 5 个函数），实现于
`src/ffi/chatvv_ffi.cpp`。所有返回字符串由库分配，调用方用 `chatvv_free()`
释放；失败返回 `NULL` 并写 `error_json`（`{"code","message"}` JSON，同样用
`chatvv_free()` 释放）。

```c
#include "chatvv/chatvv.h"

char* error = NULL;
chatvv_asr* asr = chatvv_asr_create(
    "/data/models/ggml-tiny.bin",          /* UTF-8 路径 */
    "{\"use_gpu\":true,\"threads\":4}",     /* 可 NULL */
    &error);
if (!asr) { /* error 是 JSON，可解析 code/message */ }

char* result = chatvv_asr_transcribe_file(
    asr,
    "/data/recordings/input.wav",
    "{\"language\":\"auto\"}",              /* 可 NULL */
    &error);
if (result) {
  /* {"text","language","model","duration_ms",
      "segments":[{"id","start_ms","end_ms","text"}]} */
  chatvv_free(result);
}
chatvv_asr_destroy(asr);
```

PCM 输入（mono float32、[-1,1]、任意采样率，非 16 kHz 会线性重采样）：

```c
float* pcm = ...; int n = ...;       // 调用期间保持有效，不会保存指针
char* result = chatvv_asr_transcribe_pcm(asr, pcm, n, 16000, NULL, &error);
```

能力查询（不需要模型；`asr` 可传 `NULL` 拿构建级信息）：

```c
char* caps = chatvv_asr_capabilities(asr, &error);
/* {"engine":"whisper.cpp","version":"1.9.5-dev","loaded":true,"model":"...",
    "sample_rate":16000,"audio_formats":["wav","pcm_f32"],
    "languages":["en","zh",...],"backends":["CPU","Vulkan"...],
    "gpu_available":true,"gpu_requested":true,"gpu_active":false,
    "flash_attn":false,"threads":4,"supports_translate":true} */
```

### options / config 字段

`chatvv_asr_create` 的 `config_json`：

| key | 类型 | 默认 | 说明 |
|---|---|---|---|
| `use_gpu` | bool | `true` | 优先 GPU（Vulkan）后端，失败自动回退 CPU 并写 warn 日志 |
| `threads` | int | `0` | 解码线程；0 = whisper 默认（min(4, CPU 核数)） |
| `flash_attn` | bool | `false` | 后端支持时启用 flash attention |

转写 `options_json`：

| key | 类型 | 默认 | 说明 |
|---|---|---|---|
| `language` | string | `"auto"` | `"auto"` 自动检测，或 whisper 语言码（`"zh"`、`"en"`、`"ja"`…，也接受全名如 `"chinese"`）；非法码返回 `invalid_language` |
| `threads` | int | `0` | 覆盖本次调用的解码线程 |
| `translate` | bool | `false` | 翻译成英文（仅多语言模型；`*.en` 模型不支持） |

### 错误码（`error_json.code`）

`invalid_argument`、`invalid_config`、`invalid_options`、`model_load_failed`、
`engine_not_loaded`、`engine_stopped`（不使用）、`invalid_wav`、`audio_empty`、
`audio_too_short`、`audio_too_long`、`invalid_language`、`transcribe_failed`、
`asr_create_failed`、`capabilities_failed`。

异常安全：所有 C ABI 入口都有 `try/catch(...)`，C++ 异常不会穿过 FFI 边界；
断言前检查 NULL/长度/采样率。

## 5. 音频格式与限制

- 文件：RIFF/WAVE；PCM 8/16/24/32-bit、IEEE float32/float64；
  `WAVE_FORMAT_EXTENSIBLE`；mono/stereo/多声道（平均混为 mono）；任意采样率
  线性重采样到 16 kHz。
- 不支持：A-law/µ-law、ADPCM、压缩 WAV（如 MP3 容器），会返回 `invalid_wav`。
- 原始 PCM：必须 mono float32（[-1,1]），任意正采样率。
- 单个 WAV 上限 512 MiB（防 OOM）；短于 100 ms 直接返回 `audio_too_short`。
- 线性重采样质量足够 ASR，但不如 libsamplerate/SoXR；若有高质量需求可后续替换
  `src/asr/asr.cpp` 的 `resample_linear()`（不引入新依赖是有意选择）。
- 每次转写设置 `no_context=true`，不跨请求携带上下文；不做 VAD、不做说话人分离
  （whisper.cpp 的 VAD 需要额外模型，未接入）。
- 转写结果 `duration_ms` 为输入音频时长；segment 时间戳来自 whisper 的 10 ms
  时间单位（`t0/t1 * 10`）。

## 6. Dart 绑定（`app/lib/data/asr_api.dart`）

纯 FFI 数据层，不接 UI、不改其它 Dart 文件。库查找顺序与
`ffi_chat_api.dart` 一致（`CHATVV_FFI_LIB` 环境/`--dart-define` → 平台默认名 →
桌面包内相对路径）。所有 native 调用都放在 `Isolate.run`，不阻塞 UI isolate：

```dart
final api = AsrApi();                        // 加载动态库，不加载模型
try {
  // 一次性：创建 engine → 转写 → 释放，全部在后台 isolate
  final transcript = await api.transcribeFileOnce(
    modelPath: '/data/models/ggml-tiny.bin',
    wavPath: '/data/recordings/input.wav',
    language: 'auto',
  );
  print(transcript.text);

  // 复用 engine（模型只加载一次）
  final engine = await api.createEngine(modelPath: '/data/models/ggml-base.bin');
  final caps = await engine.capabilities();
  final pcm = Float32List(16000);            // mono float32, [-1, 1]
  final second = await engine.transcribePcm(pcm, sampleRate: 16000, language: 'zh');
  await engine.dispose();
} finally {
  await api.dispose();
}
```

- 动态库缺少 `chatvv_asr_*` 符号时抛 `AsrApiException(code: 'asr_symbol_missing')`；
  加载失败为 `asr_sdk_load_failed`。
- native 错误 JSON 转成 `AsrApiException(message, code: <native code>)`。
- PCM 通过 `TransferableTypedData` 传给 worker isolate，避免额外拷贝。
- 同一 engine 的并发转写由 native 互斥串行化；`dispose()` 不要与进行中的转写并发。

## 7. 模型下载、摆放与许可

模型**不提交进仓库**（`.gitignore` 未包含通用 `*.bin`，请勿手动 `git add` 模型）。
下载地址（ggml-org 官方转换，GGML 格式）：

| 模型 | 文件 | 大小 | 下载 |
|---|---|---|---|
| tiny（多语言） | `ggml-tiny.bin` | ~75 MiB | https://huggingface.co/ggml-org/whisper.cpp/resolve/main/ggml-tiny.bin |
| base（多语言） | `ggml-base.bin` | ~142 MiB | https://huggingface.co/ggml-org/whisper.cpp/resolve/main/ggml-base.bin |
| tiny.en / base.en（仅英文） | `ggml-tiny.en.bin` / `ggml-base.en.bin` | ~75 / ~142 MiB | 同仓库 `main` 下同名文件 |

```bash
mkdir -p data/models
curl -L -o data/models/ggml-tiny.bin \
  https://huggingface.co/ggml-org/whisper.cpp/resolve/main/ggml-tiny.bin
# sha256 自检（以官方页面/HF 版本为准），不要把模型提交到 git
```

`data/` 已被 `.gitignore` 忽略（仓库根 `.gitignore` 的 `/data/`），适合放本地
开发模型；桌面打包时不要把模型打进安装包（APK/安装包体积），由 App 在首次使用
时下载或由用户放置，路径通过 `chatvv_asr_create` 的 `model_path` 传入。

许可：

- whisper.cpp 代码：MIT（`third_party/whisper.cpp/LICENSE`）。
- Whisper 模型权重：OpenAI 以 MIT 许可发布；ggml-org 的 GGML 转换文件沿用该许可。
  `ggml-tiny.bin`/`ggml-base.bin` 来自 <https://github.com/ggml-org/whisper.cpp>
  的模型清单（HuggingFace `ggml-org/whisper.cpp`）。分发模型时请附带 MIT 许可与
  来源说明。
- 本仓库 vendored 的 whisper.cpp 只含 MIT 代码；X-ASR / sherpa-onnx 路线（见
  `docs/voice-yolo.md`）与 Whisper 无关，其许可需另行确认。

## 8. 冒烟验证（可复现）

本机 CPU-only 验证（不污染仓库构建；模型不参与）：

```bash
# 1) 构建级兼容性：llama 的 ggml + whisper（真实 fragment）
mkdir -p /tmp/asr-smoke && cd /tmp/asr-smoke
#   见 docs 附带的 scratch CMakeLists：先 add_subdirectory(仓库 llama.cpp)，
#   再 include(仓库 cmake/whisper.cmake) + chatvv_add_whisper()
cmake -S . -B build -G Ninja
cmake --build build --target chatvv_asr_smoke -j"$(nproc)"
```

（本次验证实际执行的等价步骤：配置日志 `ggml version: 0.28.0` /
`whisper.cpp version: 1.9.5-dev`；构建出 `libwhisper.a`、可执行文件和共享库。）

```bash
# 2) ASR 封装自测（不加载模型）：WAV 解码/重采样/能力 JSON/错误路径
cmake --build build --target asr_selftest -j"$(nproc)"
./build/asr_selftest    # 全部 ok，退出码 0
```

CI 建议：

- 构建阶段不需要新增系统依赖：WAV 解析在 `src/asr/asr.cpp` 内自包含，不依赖
  ffmpeg/SDL2/libsndfile。
- Vulkan：Linux/Windows/Android 由 Lead 的 `-DCHATVV_VULKAN=ON` 统一构建 ggml
  Vulkan 后端（Android 从 NDK 取 Vulkan + host `glslc`；macOS 不启用 Vulkan）。
  whisper 不需要单独配置。
- 可选的真实模型测试（不在默认 CI）：下载 `ggml-tiny.bin`（~75 MiB）→
  `chatvv_asr_transcribe_file` 一个 1–3 秒 WAV；建议只在带网络的 nightly 或手工
  真机 job 跑，避免每个 PR 都拉 75 MB 模型。
- 现有 `chatvv_ffi_tests` 可加一个「`chatvv_asr_capabilities(NULL, ...)` 返回合法
  JSON」的用例（不需要模型），但本 task 范围内未改 `tests/`。

## 9. 已知风险与后续

1. **pin 的是 master commit 而非 release tag**：因需要 ggml 0.28.0，pin 在
   `v1.9.5` 之后、ggml 0.29 之前。升级 ggml（例如以后把 llama.cpp 升到 0.29）
   时必须同步重新选择 whisper commit 并重跑第 8 节冒烟；`UPSTREAM.md` 记录了
   更新步骤。
2. **Vulkan 未在本机验证**：CPU 构建已验证；Vulkan 行为依赖 CI/真机。手机 Vulkan
   驱动碎片化，`chatvv_asr_create` 在 GPU 初始化失败时自动回退 CPU（`gpu_active`
   在 capabilities 里可见）。
3. **线性重采样**：质量一般，超长/极低采样率音质损失更大；如后续质量不满足可
   换库（会引入新依赖）。
4. **内存**：WAV 全量读入 + float mono + whisper 计算图。512 MiB 上限防止极端
    OOM；手机端建议限制录音时长（30–60 s 一段）。
5. **模型不在仓库/默认 CI**：端到端转写未在仓库内自动化，需手工或 nightly 验证；
   模型文件按许可与体积要求按需下载。
6. **`parakeet` target**：上游 whisper.cpp 同期还提供 parakeet 语音模型库，fragment
   用 EXCLUDE_FROM_ALL 保证不编译不安装；如未来需要可单独启用。
7. **不是流式 ASR**：当前是「整段 WAV/PCM → 一次 whisper_full」，长语音需要上层
   分段；流式方案（X-ASR/sherpa-onnx）仍按 `docs/voice-yolo.md` 的路线另行评估。

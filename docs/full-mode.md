# Full 模式：Dart FFI + 内嵌 C++ core

> 状态：**Linux / Android arm64 已跑通**。Android 真机在停止 `chatvvd`、移除
> `adb reverse` 后仍能收到 mock 回复，证明 Full 不经过本地服务器。
> Windows 交叉构建、真实 DeepSeek 网络和 macOS 仍待补。

## 1. 三种产物

```text
chatvv_core     STATIC   配置、SQLite、context、provider、dialog
chatvv_ffi      SHARED   C ABI；Dart FFI 入口
chatvvd         EXECUTABLE  core + HTTP/SSE + main（Only client 的服务器）
```

`chatvv_core` 不再包含 `src/http/server.cpp`。HTTP 是 server adapter，不属于内嵌 core。

## 2. C ABI

头文件：[`include/chatvv/chatvv.h`](../include/chatvv/chatvv.h)

```c
chatvv_engine* chatvv_create(const char* config_json, char** error_json);
void           chatvv_destroy(chatvv_engine*);
char*          chatvv_send(chatvv_engine*, const char* text,
                           chatvv_event_cb, void*, char** error_json);
void           chatvv_cancel(chatvv_engine*, const char* response_id);
char*          chatvv_history(chatvv_engine*, int32_t limit,
                              int64_t before_seq, char** error_json);
char*          chatvv_capabilities(chatvv_engine*, char** error_json);
void           chatvv_free(char*);
```

- 所有 JSON/字符串由库分配，调用方用 `chatvv_free` 释放。
- `chatvv_send` 立即返回 response id；事件在 worker 线程回调。
- `event_json` **所有权转移给回调**：Dart 侧复制后必须 `chatvv_free`。
  这是为了 `NativeCallable.listener` 异步投递时不会解引用已结束的 C++ 字符串。
- 终态事件在 assistant 消息写库之后才发出，保证回调里查 history 一致。

## 3. Flutter 接口

```text
ChatBackend (Dart interface)
├── RemoteChatApi   /v1/turns SSE（Only client）
└── FfiChatApi      Dart FFI（Full）
```

`ChatController` 只依赖 `ChatBackend`。Full 与 Client 共用聊天 UI。

`FfiChatApi` 用 `NativeCallable.listener` 把 C++ worker 事件 marshal 回主 isolate。
`dispose` 先 `chatvv_destroy`，再留出一个事件队列轮次让排队的终态回调落地，最后关闭
NativeCallable。

## 4. 配置

```json
{
  "data_dir": "/data/user/0/dev.chatvv.chatvv/files/chatvv",
  "injections_dir": ".../injections",
  "provider": "deepseek",
  "base_url": "https://api.deepseek.com",
  "endpoint": "/responses",
  "api_key": "sk-...",
  "model": "deepseek-chat",
  "ca_bundle": ".../cacert.pem"
}
```

- Android 的 app 私有目录由 `MainActivity` 的 `chatvv/paths` MethodChannel 提供，
  避免为 path_provider 引入 jni + NDK 28。
- API Key 目前写入本机 `settings.json`（明文），后续迁移到 Keystore/Keychain。
- Android 使用打包的 `assets/cacert.pem` 作为 OpenSSL CA；Linux 留空走系统 CA。

## 5. 构建

### Linux

```bash
cmake --preset dev
cmake --build build/dev -j
ctest --test-dir build/dev --output-on-failure
```

产物：`build/dev/libchatvv_ffi.so`、`build/dev/chatvvd`。

### Android arm64

```bash
export ANDROID_NDK_HOME=$HOME/Android/Sdk/ndk/27.2.12479018
export VCPKG_ROOT=$PWD/.vcpkg
./platforms/android/build-ffi.sh
cd app
flutter build apk --debug --target-platform android-arm64
```

- vcpkg classic 构建 `curl[openssl] sqlite3`（arm64-android）。
- `libchatvv_ffi.so` 静态链接 curl/OpenSSL/zlib/SQLite，依赖
  `libc++_shared.so`；脚本会把两者放进 `jniLibs/arm64-v8a/`。
- `app/android/app/build.gradle.kts` 固定 NDK 27.2，避免 Flutter 3.44 默认 NDK 28
  与本机工具链不一致。

### Server

```bash
./build/dev/chatvvd --config config/config.toml
```

仍保持 stdio/HTTP/SSE 行为。

## 6. 已知问题

- Windows FFI DLL 尚未在本机验证；CMake preset 已拆好，需要 vcpkg x64-windows。
- 真实 DeepSeek 请求尚未在 Android 上用有效 key 回归；CA 已接入。
- Full 的 `chatvv_history` 目前按 `before_seq` 查询，UI 只取最近一页。
- Live2D 仍为独立实验分支；当前 main 用静态角色。

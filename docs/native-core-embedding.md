# 把 C++ 后端编译成库（FFI 设计）

> 状态：**C ABI 已实现，Linux/Android arm64 已跑通**；Windows/macOS 仍待补。详见 [full-mode.md](full-mode.md)。
> 关联：[Flutter App 设计](flutter-app-design.md) · [app/design/DESIGN.md](../app/design/DESIGN.md)

## 1. 现有代码怎么切

当前 `src/` 已经是按职责分层的，只是被一个 `main.cpp` 和一个 `chatvvd` target 串起来：

| 模块 | 文件 | 归属 |
|---|---|---|
| 配置 | `app/config.*` | core |
| SQLite / 消息 / 响应 / 事件 | `store/db.*` | core |
| 注入槽位 | `context/injections.*` | core |
| 上下文组装 | `context/context_builder.*` | core |
| LLM Provider（mock / DeepSeek Responses） | `llm/*` | core |
| 对话编排、流式事件、取消 | `dialog/*` | core |
| 日志/ULID/工具 | `util/*` | core |
| HTTP/SSE 路由 | `http/server.*` | server adapter |
| 进程启动 | `main.cpp` | server entry |

目标 target：

```
chatvv_core        STATIC   # 无 HTTP，无 main；可被 lib/server 复用
chatvv_ffi         SHARED   # C ABI wrapper，链接 core
chatvv_server      EXECUTABLE # core + http/server + main.cpp
```

- `chatvv_core` 不应依赖 `cpp-httplib`。
- `chatvv_ffi` 只暴露 C ABI；所有 C++ 类型/异常都在内部。
- `chatvv_server` 保持现有 CLI/HTTP 行为，作为 Client-only 模式的后端。

## 2. C ABI 草案

头文件 `include/chatvv/chatvv.h`（未来再建）：

```c
#ifndef CHATVV_H
#define CHATVV_H

#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef struct chatvv_engine chatvv_engine;

typedef enum {
  CHATVV_EVENT_STARTED = 1,
  CHATVV_EVENT_DELTA = 2,
  CHATVV_EVENT_TOOL = 3,
  CHATVV_EVENT_COMPLETED = 4,
  CHATVV_EVENT_FAILED = 5
} chatvv_event_type;

/* event_json is UTF-8 JSON, valid only for the duration of the callback. */
typedef void (*chatvv_event_cb)(void* user_data,
                                int32_t event_type,
                                const char* event_json);

/* config_json: UTF-8 JSON (paths, provider, api_base, api_key, prompts_dir). */
chatvv_engine* chatvv_create(const char* config_json, char** error_json);

void chatvv_destroy(chatvv_engine* engine);

/* Returns response id; ownership transferred to caller (chatvv_free). */
char* chatvv_send(chatvv_engine* engine,
                  const char* text,
                  chatvv_event_cb cb,
                  void* user_data,
                  char** error_json);

void chatvv_cancel(chatvv_engine* engine, const char* response_id);

/* JSON array; caller frees with chatvv_free. */
char* chatvv_history(chatvv_engine* engine,
                     int32_t limit,
                     int64_t before_seq,
                     char** error_json);

char* chatvv_capabilities(chatvv_engine* engine, char** error_json);

void chatvv_free(char* value);

#ifdef __cplusplus
}
#endif
#endif
```

原则：

- 只传 UTF-8 JSON / 简单标量，不传 STL、异常、回调里的 C++ 对象。
- 每个返回字符串都由库分配，Dart 侧用 `chatvv_free` 释放。
- 错误用 `error_json`（`{"code":"...","message":"..."}`），不跨 ABI 抛异常。
- `chatvv_send` 立即返回 response id；事件在后台线程回调。
- 回调里的 `event_json` 只在回调期间有效；Dart 侧立即复制成 String。

事件 JSON 示例：

```json
{"type":"delta","response_id":"01...","text":"你"}
```

```json
{"type":"completed","response_id":"01...","status":"completed","usage":{"input_tokens":930,"output_tokens":46}}
```

## 3. 线程与 Dart 回调

- C++ 侧：`chatvv_send` 在内部线程池/worker 上跑 LLM，回调从 worker 线程发出。
- Dart FFI：使用 `NativeCallable.listener`（异步 listener）把回调 marshal 到主 isolate；不要在 native 线程直接碰 Dart VM。
- 回调可能高频（每个 token）；Dart 侧做批量/节流（例如 16–33 ms 合并一次 UI 更新）。
- `chatvv_cancel` 线程安全；worker 在下一个 chunk 检查取消标志。
- `chatvv_destroy` 等待/停止 worker，确保不再回调；Flutter `dispose` 时调用。
- 事件顺序：`started` → (`delta` | `tool`)* → `completed` | `failed`；允许重连时按 `after_seq` 重放。

## 4. 配置与数据

```json
{
  "data_dir": "/data/user/0/.../chatvv",
  "db_path": "/data/user/0/.../chatvv/chatvv.db",
  "injections_dir": "/data/user/0/.../chatvv/injections",
  "provider": "deepseek",
  "api_base": "https://api.deepseek.com",
  "endpoint": "/responses",
  "api_key": "sk-...",
  "model": "deepseek-chat"
}
```

- Flutter 用 `path_provider` 取 app support dir，传给核心。
- API Key 优先放 `flutter_secure_storage`，启动时读出传给核心；不要写进 SQLite/日志。
- `config_json` 里的 key 只在内存；核心不落盘。
- 注入 MD/提示词作为 Flutter assets 打包，首次启动解压到 `injections_dir`；或编译期嵌入（后续）。
- 日志默认写 app support dir，Release 默认 INFO；不要在日志里打 API Key/消息全文。

## 5. 平台构建

| 平台 | 产物 | 依赖 |
|---|---|---|
| Linux x64 | `libchatvv_core.so` / `chatvv-server` | 系统 sqlite3, libcurl, openssl |
| macOS arm64 | `.dylib` / `.a` + server | Homebrew/vcpkg |
| Windows x64 | `.dll` / `.lib` + server | vcpkg sqlite3/curl |
| Android arm64 | `libchatvv_core.so` + `.a` | NDK + 交叉编译 sqlite/curl/openssl |
| iOS arm64 | `.xcframework` / static | 静态 sqlite/curl/openssl，Bitcode 视 Xcode 版本 |

- 现有 `vcpkg.json` 已声明 curl/sqlite3；Android/iOS 需要额外 triplet。
- 低占用：Release `-Os`/`-O2`、LTO、strip、隐藏符号；只保留需要的 TLS 后端。
- 先做 **Linux/macOS 桌面** FFI 验证 ABI，再攻 Android/iOS 交叉编译。
- 如果移动端 libcurl/OpenSSL 成本过高，备选：
  - 移动端 HTTP 由 Dart 做（`dio`/`http`），C++ 核心只负责 SQLite/context/memory，回调流由 Dart 侧拼装；
  - 但这样 Full 模式会分裂 LLM 调用路径，需权衡。

## 6. Flutter 侧接口

```dart
abstract interface class ChatBackend {
  Stream<ChatEvent> send(String text);
  Future<List<Message>> history({int limit = 30, int? beforeSeq});
  Future<void> cancel(String responseId);
  Future<void> dispose();
}
```

- `RemoteChatBackend`：`POST /v1/turns` + SSE；`/v1/responses/{id}/events` 重连。
- `EmbeddedChatBackend`：`ffi` + `NativeCallable.listener`；把事件 JSON 转 `ChatEvent`。
- 两者共用 `ChatRepository` 和 UI；设置里切换模式只替换 backend。
- Client 模式没有 native lib 时，`EmbeddedChatBackend` 不可用；UI 自动隐藏 Full 选项。

## 7. Server 模式

`chatvv-server` 继续是“core + transport”：

- 单用户/单机；默认绑 `127.0.0.1`，局域网部署时显式 `0.0.0.0` + API Key + 反代 TLS。
- SSE 事件与 Full 模式语义一致，便于 Flutter 两种 backend 复用。
- 后续可以加 `/v1/export` / `/v1/import` 做 Full ↔ Client 数据迁移。
- 不做多租户；鉴权是单 key/Bearer。

## 8. 测试

- C ABI 单测：create/send/cancel/history/destroy；回调线程/顺序；错误 JSON；重复 destroy。
- 用 mock provider 跑 CI，不依赖真实 API。
- Flutter：`ffi` 集成测试在 Linux/macOS 桌面跑；Android 真机 smoke。
- 泄漏：ASan/LSan（桌面）、Xcode Instruments、`simpleperf`/Perfetto。
- 断线/重放：server 侧已有测试；Full 侧用 SQLite 事件重放。

## 9. 风险

1. **移动端 TLS/curl 交叉编译**是最大成本；可能推迟 Android Full。
2. **回调线程与 Dart isolate**：必须用 `NativeCallable.listener`，不要直接 `isolate` 共享内存。
3. **包体**：静态 libcurl/OpenSSL 会显著增大；需要按 ABI 分包、裁剪。
4. **iOS 后台/音频**：TTS/长连接后台策略要单独设计。
5. **数据迁移**：现有 Web 版 SQLite 与 Flutter Full 共用 schema 的话可以直接打开；否则写迁移工具。
6. **安全**：API Key 不落盘明文；Client 模式默认 HTTPS；server 默认 localhost。

## 10. 下一步（按顺序）

1. Client 模式 Flutter UI（不改 C++）。
2. 在 Linux/macOS 加 `chatvv_core` / `chatvv_ffi` target，C ABI + mock 测试。
3. Flutter 桌面 Full 模式跑通。
4. Android NDK 交叉编译（先 SQLite，再 curl/openssl）。
5. Full/Client flavor、体积/内存测量。

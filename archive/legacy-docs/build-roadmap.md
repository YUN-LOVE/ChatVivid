# 构建、测试与路线图

> 状态：设计草案 v0.1
> 目标：一条命令构建、一条命令测试、一个二进制部署。

---

## 1. 工具链现状（本机实测）

```
clang 23.1.3          gcc 16.2.1 (libstdc++)
cmake 4.4.4           ninja 1.13.2
hiredis 1.4.0         openssl 3.6.5
sqlite 3.54.0         yaml-cpp 0.9.0      fmt 12.2.0
boost: 未安装头文件   vcpkg / conan: 未安装
redis-server → valkey 9.1.2，无 search 模块
```

两个坑先说清楚：

1. **CMake 4.x 不再兼容 `cmake_minimum_required(<3.5)`**。引第三方源码时若报策略错误，加
   `-DCMAKE_POLICY_VERSION_MINIMUM=3.5`，或让 vcpkg 打补丁。
2. **Arch 的 `redis` 包已经是 valkey，且不带 vector/search 模块**。开发期必须用
   `docker run -p 6379:6379 redis:8`，或 `valkey/valkey-bundle`。部署文档里也要写清楚。

---

## 2. 依赖管理

### 2.1 方案：vcpkg manifest（固定 baseline）

```bash
git clone https://github.com/microsoft/vcpkg ~/.vcpkg
~/.vcpkg/bootstrap-vcpkg.sh -disableMetrics
export VCPKG_ROOT=~/.vcpkg
```

`vcpkg.json`：

```json
{
  "name": "chatvv",
  "version-string": "0.1.0",
  "builtin-baseline": "<pin-a-commit>",
  "dependencies": [
    "boost-asio",
    "boost-beast",
    "boost-system",
    "curl",
    "openssl",
    "nlohmann-json",
    "hiredis",
    "sqlite3",
    "spdlog",
    "tomlplusplus",
    "utf8proc",
    "libsodium",
    { "name": "catch2", "host": false }
  ]
}
```

| 依赖 | 用途 | 备注 |
|---|---|---|
| Boost.Asio / Beast | HTTP 服务端、协程、定时器 | 头文件为主；版本随 vcpkg |
| libcurl | LLM / MCP 的 HTTP 客户端 | 需要 `CURL_STATICLIB` 时注意证书路径 |
| OpenSSL | TLS、sha256 | 与 curl 共用 |
| nlohmann-json | 配置、API、JSON-RPC | 编译期 `JSON_USE_IMPLICIT_CONVERSIONS=0` |
| hiredis | Redis | 只用同步 API + 连接池 |
| sqlite3 | 事实源 | 需启用 FTS5 |
| spdlog | 日志 | header-only + fmt |
| toml++ | 配置 | 单头文件 |
| utf8proc | 文本规范化 | 处理中文空白/宽度 |
| libsodium | 密钥加密 | secretbox |
| Catch2 | 测试 | v3 |

**sqlite3 的 FTS5**：vcpkg 的 `sqlite3` 默认带 FTS5；若自行编译，必须定义 `SQLITE_ENABLE_FTS5`。集成测试里加一条 `PRAGMA compile_options` 断言，避免上线才发现。

**llama.cpp**：用 FetchContent 固定 tag，不要用 vcpkg 的版本（更新太快）：

```cmake
FetchContent_Declare(llama_cpp
  GIT_REPOSITORY https://github.com/ggml-org/llama.cpp.git
  GIT_TAG        <pin>
  GIT_SHALLOW    TRUE)
set(LLAMA_BUILD_TESTS   OFF CACHE BOOL "" FORCE)
set(LLAMA_BUILD_SERVER  OFF CACHE BOOL "" FORCE)
set(LLAMA_CURL          OFF CACHE BOOL "" FORCE)
set(GGML_NATIVE         OFF CACHE BOOL "" FORCE)
set(GGML_OPENMP         OFF CACHE BOOL "" FORCE)
set(BUILD_SHARED_LIBS   OFF CACHE BOOL "" FORCE)
FetchContent_MakeAvailable(llama_cpp)
```

第一次构建约 8–12 分钟（4 核），之后增量。CI 用 ccache 或预编译缓存。

### 2.2 为什么不用 conan

能用，但 vcpkg 的 triplet 机制对 ARM64 交叉编译更省心，且 Windows 开发机也能复用。CMake 4.4 + vcpkg 的组合已经很稳。

---

## 3. 目录结构

```
chatvv/
├── CMakeLists.txt
├── CMakePresets.json
├── vcpkg.json
├── config/
│   ├── config.example.toml
│   └── dev.toml
├── cmake/
│   ├── CompilerWarnings.cmake
│   ├── Sanitizers.cmake
│   └── EmbedAssets.cmake
├── src/
│   ├── main.cpp
│   ├── app/            # 组合根：配置、依赖注入、生命周期、CLI
│   ├── http/           # Beast server、router、SSE、auth、CORS、限流
│   ├── api/            # handlers、DTO、错误映射、OpenAPI 生成
│   ├── agent/          # Run 状态机、context builder、budget、approvals、events
│   ├── tools/          # registry、内置工具、policy、sandbox
│   ├── rag/            # parser、chunker、embedder、indexer、retriever、rerank、eval
│   ├── skills/         # scanner、validator、registry、loader
│   ├── mcp/            # client、jsonrpc、transport_stdio、transport_http、version
│   ├── llm/            # provider、openai_compat、stream_parser、usage
│   ├── store/          # sqlite、migrations、repositories、fts
│   ├── vector/         # redis pool、index、search
│   ├── domain/         # 实体与值对象（无依赖）
│   ├── rt/             # io、blocking pool、channel、cancellation、clock
│   └── util/           # json、strings、ulid、result、log、crypto、path jail
├── tests/
│   ├── unit/
│   ├── integration/
│   ├── evals/
│   └── fixtures/
├── web/                # 前端空壳（独立 pnpm 项目）
├── scripts/
│   ├── bootstrap.sh
│   ├── fetch-models.sh
│   ├── dev-redis.sh
│   └── bench.sh
└── docs/
```

**依赖方向**：`http → api → agent → 各能力层 → store/vector`。`domain` 与 `util` 不依赖任何上层。用 CMake 的 `PRIVATE` 链接强制，不允许头文件互相穿透。

---

## 4. 构建配置

### 4.1 顶层 CMakeLists（骨架）

```cmake
cmake_minimum_required(VERSION 3.28)
project(chatvv VERSION 0.1.0 LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 23)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_CXX_EXTENSIONS OFF)
set(CMAKE_EXPORT_COMPILE_COMMANDS ON)

add_library(chatvv_core STATIC)
target_sources(chatvv_core PRIVATE ${CHATVV_SOURCES})
target_include_directories(chatvv_core PUBLIC src)
target_link_libraries(chatvv_core PRIVATE
  Boost::asio Boost::beast Boost::system
  CURL::libcurl OpenSSL::SSL OpenSSL::Crypto
  nlohmann_json::nlohmann_json hiredis::hiredis
  unofficial::sqlite3::sqlite3 spdlog::spdlog tomlplusplus::tomlplusplus
  utf8proc unofficial-sodium::sodium
  llama)
# 目标名以 `vcpkg install` 输出的 usage 为准，不同 baseline 偶有差异；
# 首次配置若报 target 不存在，按提示改名即可（逻辑代码不受影响）。

add_executable(chatvvd src/main.cpp)
target_link_libraries(chatvvd PRIVATE chatvv_core)
```

实际落地时按 `src/*` 拆成多个 `target_sources`，但保持 **单一静态库**，避免目标爆炸。

### 4.2 CMakePresets.json

```json
{
  "version": 7,
  "configurePresets": [
    {
      "name": "dev",
      "generator": "Ninja",
      "binaryDir": "${sourceDir}/build/dev",
      "cacheVariables": {
        "CMAKE_BUILD_TYPE": "Debug",
        "CMAKE_CXX_COMPILER": "clang++",
        "CHATVV_SANITIZE": "address;undefined",
        "CMAKE_POLICY_VERSION_MINIMUM": "3.5"
      }
    },
    {
      "name": "release",
      "generator": "Ninja",
      "binaryDir": "${sourceDir}/build/release",
      "cacheVariables": {
        "CMAKE_BUILD_TYPE": "RelWithDebInfo",
        "CMAKE_CXX_COMPILER": "clang++",
        "CMAKE_INTERPROCEDURAL_OPTIMIZATION": "ON",
        "CMAKE_POLICY_VERSION_MINIMUM": "3.5"
      }
    },
    {
      "name": "arm64",
      "generator": "Ninja",
      "binaryDir": "${sourceDir}/build/arm64",
      "toolchainFile": "$env{VCPKG_ROOT}/scripts/buildsystems/vcpkg.cmake",
      "cacheVariables": {
        "VCPKG_TARGET_TRIPLET": "arm64-linux",
        "CMAKE_BUILD_TYPE": "Release",
        "GGML_NATIVE": "OFF",
        "GGML_CPU_ARM_ARCH": "armv8.2-a+dotprod+fp16"
      }
    }
  ],
  "buildPresets": [
    { "name": "dev", "configurePreset": "dev", "jobs": 4 },
    { "name": "release", "configurePreset": "release", "jobs": 4 }
  ],
  "testPresets": [
    { "name": "dev", "configurePreset": "dev", "output": { "outputOnFailure": true } }
  ]
}
```

### 4.3 编译选项

| 场景 | 选项 |
|---|---|
| 公共警告 | `-Wall -Wextra -Wpedantic -Wshadow -Wconversion`（`conversion` 先只对 util 开） |
| Debug | `-O0 -g3 -fsanitize=address,undefined -fno-omit-frame-pointer` |
| Release | `-O2 -flto=thin -DNDEBUG -fstack-protector-strong -D_FORTIFY_SOURCE=3` |
| 本地加速 | `-march=x86-64-v3`（**不要**进发布包，ARM 上不通用） |
| 静态分析 | clang-tidy（`bugprone-*`、`performance-*`、`cppcoreguidelines-*` 子集）+ clangd |

C++23 里会重度使用的：`std::expected`（错误返回）、`std::generator`（流式片段）、`std::print`（日志格式化）、`std::flat_map`（小表）、`std::jthread`（阻塞池）。

### 4.4 交叉编译（ARM64）

```bash
cmake --preset arm64 \
  -DCMAKE_TOOLCHAIN_FILE=$VCPKG_ROOT/scripts/buildsystems/vcpkg.cmake \
  -DVCPKG_CHAINLOAD_TOOLCHAIN_FILE=cmake/aarch64-linux-clang.cmake
```

要点：

- `GGML_NATIVE=OFF`，否则会在 x86 上用 AVX 指令，到 ARM 上直接非法指令。
- llama.cpp 的 NEON 优化默认开启；树莓派 5 可加 `-march=armv8.2-a+dotprod+fp16`。
- 静态链接 `libstdc++`/`libgcc`（`-static-libstdc++ -static-libgcc`），减少目标机 glibc 版本问题；OpenSSL/curl 仍动态链接，方便安全更新。
- 在 CI 里用 qemu 跑一遍冒烟测试（`ctest -R smoke`），别等上板才发现。

---

## 5. 测试策略

| 层 | 工具 | 覆盖内容 | 何时跑 |
|---|---|---|---|
| 单元 | Catch2 | chunker、SSE 解析、ULID、路径牢笼、JSON Schema 子集、RRF、token 估算 | 每次提交 |
| 集成 | Catch2 + 临时目录 + 真实 Redis | 上传→索引→检索→对话→事件回放；Redis 断连降级 | 每次提交（无 Redis 则 skip 并标记） |
| 契约 | OpenAPI schema 校验 | 所有响应符合 `openapi.json`；SSE 事件字段齐全 | 每次提交 |
| 端到端 | 脚本 + curl | 启动二进制、发消息、断线续传、取消 | 每日 |
| 评测 | `tests/evals` | recall@5 / MRR / nDCG；固定语料 | 每周 / 改动 RAG 时 |
| 模糊 | libFuzzer（可选） | SSE 行解析、JSON-RPC 帧、PDF 解析器边界 | 每周 |

集成测试的关键是**不 mock Redis**：用 `redis-server --unixsocket` 起临时实例（CI 用 service container），真实执行 `FT.CREATE` / `FT.SEARCH`，否则向量检索的坑一个都测不出来。测试启动时探测 Redis 版本与模块，缺失则 skip 并打印原因。

### CI（GitHub Actions）

```
jobs:
  linux-clang:   configure(dev) → build → ctest → clang-tidy(diff)
  linux-release: configure(release) → build → 冒烟（curl 流式）
  arm64-cross:   configure(arm64) → build → qemu 冒烟
  web:           pnpm install → tsc → eslint → build（产物作为 artifact）
```

缓存：vcpkg binary cache、ccache、pnpm store。四个 job 控制在 15 分钟内。

---

## 6. 里程碑

> 估算前提：每周 10–15 小时，一个人，熟悉 C++ 但不熟悉 Asio/Beast。

### M0 · 能聊（1–2 周）

- [ ] CMake + vcpkg + 预设 + CI 骨架
- [ ] 配置加载（TOML + 环境变量覆盖）、日志、优雅退出
- [ ] Beast HTTP 服务器 + 路由 + JSON 错误
- [ ] SQLite 迁移 + conversations/messages 仓储
- [ ] OpenAI 兼容 Provider（非流式 + 流式 SSE）
- [ ] `POST /messages` → Run → `GET events` → 完整回放
- [ ] `/healthz`、`/readyz`、`/capabilities`

**验收**：`curl -N` 能看到逐字输出；重启进程后历史消息还在；断线 10s 后重连能补齐；`Ctrl-C` 不丢数据。

### M1 · 有知识（2–3 周）

- [ ] llama.cpp 嵌入 + 模型校验 + 降级
- [ ] 文档上传、解析（txt/md/pdf）、切分、嵌入、双写
- [ ] Redis 索引创建与自检、重建命令
- [ ] KNN + FTS5 + RRF + 引用
- [ ] 检索调试接口与评测脚本

**验收**：30 条查询的 recall@5 ≥ 0.8；删除 Redis 数据后 `reindex` 30 秒内恢复；embedding 缺失时聊天仍可用。

### M2 · 会用工具（2 周）

- [ ] 工具注册表 + JSON Schema 校验 + 风险分级
- [ ] Agent 循环、预算、重复调用检测、取消
- [ ] 内置工具：`rag_search`、`doc_read`、`skill_load`、`time_now`
- [ ] 审批流（SSE `tool.approval.required` + 接口）
- [ ] 上下文压缩、结果 artifact

**验收**：模型能自主调用 `rag_search` 并引用；取消 1 秒内生效；断线重连不重复执行工具；超过步数上限能给出总结。

### M3 · 能扩展（2 周）

- [ ] MCP stdio 客户端 + 工具映射
- [ ] MCP HTTP 客户端 + 版本探测/兼容
- [ ] Skills 扫描、校验、渐进加载、热重载
- [ ] MCP Skills 扩展（`skills/list`、`skill://` 资源）
- [ ] 审计日志

**验收**：接入官方 filesystem MCP server 能列目录/读文件并触发审批；接入一个 HTTP MCP server；非法 SKILL.md 被拒绝且给出原因。

### M4 · 能交付（2–3 周）

- [ ] 前端空壳：会话、流式、引用、文档、设置、审批
- [ ] OpenAPI 类型生成接入 CI
- [ ] ARM64 交叉编译 + systemd + Caddy 配置
- [ ] 压测：4 路并发 SSE，内存 < 1 GB，P95 首字 < 1.5 s（不含 LLM）
- [ ] 安全清单自查（见架构文档 §7）
- [ ] 发布脚本、备份/恢复演练

**验收**：在目标设备上从零部署到对话成功，全程照文档操作不超过 15 分钟。

---

## 7. 需要你拍板的问题

| # | 问题 | 选项 | 我的建议 |
|---|---|---|---|
| 1 | 目标设备 | x86 迷你主机 / ARM64（Pi 5、Jetson）/ 两者 | 先 x86 开发，架构上保证 ARM64 可交叉编译 |
| 2 | LLM 来源 | 云端 OpenAI 兼容（DeepSeek/OpenAI/硅基流动）/ 本地 llama.cpp / 两者 | 先云端（质量与速度），Provider 抽象留本地 |
| 3 | Redis 形态 | Docker / systemd 独立进程 / 由应用托管子进程 | systemd + Unix socket；开发用 Docker |
| 4 | 用户模型 | 纯单人 / 预留多用户 | 单租户实现，表里留 `tenant_id` |
| 5 | 前端 | React / Svelte / 先 CLI 后 Web | React + Vite + TS（生态与组件最多） |

**其中 1、2 会直接影响 M0 的接口设计**，建议先定。

---

## 8. 今天就能开始的清单

```bash
# 1. 初始化仓库
cd ~/Downloads/chatvv
git init && printf 'build/\ndata/\n.env\n*.gguf\nnode_modules/\n' > .gitignore

# 2. 装 vcpkg（约 5 分钟）
git clone https://github.com/microsoft/vcpkg ~/.vcpkg
~/.vcpkg/bootstrap-vcpkg.sh -disableMetrics

# 3. 验证 Clang + CMake 能跑 C++23
cat > /tmp/t.cpp <<'EOF'
#include <expected>
#include <print>
int main() { std::println("c++23 ok"); }
EOF
clang++ -std=c++23 /tmp/t.cpp -o /tmp/t && /tmp/t

# 4. 起 Redis 8（Arch 自带 valkey 不带 search 模块）
docker run -d --name chatvv-redis -p 6379:6379 redis:8
docker exec chatvv-redis redis-cli FT._LIST

# 5. 建骨架（下一步我来做）
#    CMakeLists.txt / CMakePresets.json / vcpkg.json / src/main.cpp
#    目标：/healthz 返回 200，SSE 能发 "hello"
```

---

## 9. 风险登记（按影响排序）

| # | 风险 | 概率 | 影响 | 缓解 |
|---|---|---|---|---|
| 1 | RAG 效果不达预期 | 中 | 高 | 先建评测集；预留 rerank；chunk 参数可调 |
| 2 | C++ 工期超预期 | 中 | 高 | M0 严格限时；HTTP 层一次写对；先跑通再优化 |
| 3 | Redis 内存/依赖问题 | 中 | 中 | 量化、限流；保留 sqlite-vec 退路；Unix socket |
| 4 | MCP 规范再变 | 中 | 中 | 版本适配层隔离；只跟进核心方法 |
| 5 | 工具/脚本被滥用 | 低 | 高 | 默认只读、审批、沙箱、审计 |
| 6 | 中文检索质量 | 中 | 中 | jieba + 向量双路；用真实语料调 |
| 7 | 交叉编译踩坑 | 中 | 中 | CI 里就做 ARM64 构建 + qemu 冒烟 |
| 8 | SSE 被代理缓冲 | 低 | 中 | 文档 + 自检 + Caddy 配置 |

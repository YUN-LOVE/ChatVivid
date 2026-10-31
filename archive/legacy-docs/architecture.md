# chatvv 架构设计

> 状态：设计草案 v0.1（2026-10-24）
> 配套：[API 契约](../../docs/api.md) · [RAG / Agent / MCP / Skills](rag-agent-mcp-skills.md) · [构建与路线图](build-roadmap.md)

---

## 0. 一页纸结论

| 维度 | 选择 | 一句话理由 |
|---|---|---|
| 形态 | 单二进制 `chatvvd` + Redis 守护进程 | 边缘设备上少一个容器、少一层编排 |
| HTTP | Boost.Asio + Beast，C++23 协程 | SSE / WebSocket / 取消传播都在一个事件循环里 |
| 出站 HTTP | libcurl（easy + 多线程） | LLM 流式、MCP HTTP、OAuth 都靠它，TLS/代理/重定向不用自己写 |
| 并发 | N 个 io 线程 + 有界阻塞池 + 单嵌入线程 | io 线程绝不阻塞；CPU 密集任务隔离 |
| 存储 | SQLite（WAL）为事实源，Redis 为派生索引 | Redis 挂了可重建；备份只需拷一个文件 |
| 向量 | Redis 8 内置 Query Engine（HNSW） | 不折腾模块；顺带拿到缓存/限流/队列 |
| 嵌入 | llama.cpp 进程内跑 bge-small-zh-v1.5（512 维） | 一个运行时同时可跑本地 LLM / rerank |
| 契约 | REST + SSE，OpenAPI 3.1 单一来源 | 前端空壳可从 schema 生成类型 |
| 长任务 | Run 模型：`POST` 建 Run → `GET events` 订阅 | 断线重连、多端观察、取消可传递 |
| 前端 | Vite + React + TS，仅消费 API | 换前端不碰后端 |

**总工期估计（每周 10–15 小时）**：可用的 M1 约 4 周，功能完整的 M3 约 9 周，打磨到可部署约 12 周。
最大的进度风险不是 C++，而是 **RAG 效果调优** 和 **工具执行的安全边界**。

---

## 1. 目标与非目标

### 目标

1. 单人/家庭/小团队在边缘设备（x86 迷你主机、ARM64 开发板）上自托管。
2. 聊天体验对标主流产品：流式输出、多轮、可中断、可重试、引用可点。
3. 本地知识库：上传文档 → 自动切分/嵌入/索引 → 对话时自动检索并给出引用。
4. Agent 能力：模型可调用内置工具、MCP 工具、Skill 指令，危险操作需人工批准。
5. API-first：浏览器只是第一个客户端，CLI / 手机 / 其他 agent 都能接同一套 API。
6. 数据不出设备（除显式调用云端 LLM 外），可完全离线运行。

### 非目标（明确不做）

- 不做模型训练/微调；不做推理引擎，直接复用 llama.cpp。
- 不做分布式向量库、不做多租户计费、不做团队权限体系（保留字段，不实现）。
- 不做服务端渲染、不做复杂前端框架抽象。
- 不追求万级 QPS；目标量级是 **个位数并发会话、十万级 chunk**。
- 不实现 MCP 的全部可选特性（Sampling / Roots 已被规范弃用，不跟进）。

---

## 2. 约束与关键取舍

| 约束 | 影响 | 取舍 |
|---|---|---|
| 边缘设备（4 核 / 8 GB 起步） | 内存与冷启动敏感 | 嵌入模型 ≤ 30M 参数；Redis 与 SQLite 共存；不做本地大模型（可选） |
| 单人 SaaS | 无复杂权限 | 单租户 + API Key；表结构预留 `tenant_id`，逻辑上不实现多租户隔离 |
| C++ 生态 | 没有 LangChain 等价物 | 自己写薄运行时（Agent loop ~800 行），比引入重框架更可控 |
| 中文为主 | 分词、嵌入都要选中文模型 | bge-small-zh-v1.5 + jieba/trigram 双方案 |
| MCP 规范 2026-07 大改（无状态） | 客户端要兼容新旧两代 | 适配层 + 能力探测，见 [MCP 章节](rag-agent-mcp-skills.md#9-mcp) |
| 工具链很新（clang 23 / CMake 4.4） | 老依赖可能编不过 | 统一 vcpkg + `CMAKE_POLICY_VERSION_MINIMUM=3.5` 兜底 |

### 本机实测环境（决定了开发期怎么起步）

```
clang 23.1.3 / GCC 16.2.1 / CMake 4.4.4 / Ninja 1.13.2
hiredis 1.4.0 / OpenSSL 3.6.5 / SQLite 3.54.0 / yaml-cpp 0.9.0 / fmt 12.2.0
boost: 仅 boost-libs，无头文件；无 vcpkg / conan；无 drogon
redis-server 实际指向 valkey 9.1.2，且未安装 search 模块
```

**结论**：开发机需要先装 vcpkg（或系统装 `boost` 头文件），Redis 用 Docker 的 `redis:8`，不要指望发行版包。

---

## 3. 总体架构

```
┌──────────────────────────────────────────────────────────────────────┐
│ 浏览器 / CLI / 其他 Agent                                             │
│   React 空壳：会话列表 · 消息流 · 引用卡片 · 文档管理 · 设置          │
└───────────────┬──────────────────────────────────────────────────────┘
                │ HTTPS + SSE（OpenAPI 3.1 生成客户端）
┌───────────────▼──────────────────────────────────────────────────────┐
│ chatvvd                                                              │
│                                                                      │
│  http/          Beast 服务器 · 路由 · 鉴权 · CORS · SSE 编码 · 限流   │
│  api/           处理器 · DTO · 错误映射 · OpenAPI                     │
│  ─────────────────────────────────────────────────────────────────   │
│  agent/         Run 状态机 · 上下文装配 · 预算 · 审批 · 事件总线      │
│  tools/         工具注册表 · 参数校验 · 策略 · 沙箱                    │
│  rag/           解析 · 切分 · 嵌入 · 检索 · 融合 · 重排 · 评估        │
│  skills/        SKILL.md 扫描 · 校验 · 注册 · 渐进式加载               │
│  mcp/           JSON-RPC 客户端 · stdio/HTTP 传输 · 工具映射           │
│  llm/           Provider 接口 · OpenAI 兼容实现 · 流式解析 · 用量      │
│  ─────────────────────────────────────────────────────────────────   │
│  store/         SQLite 仓储 · 迁移 · FTS5                             │
│  vector/        hiredis 连接池 · 索引管理 · KNN 查询                   │
│  rt/            io_context · 阻塞池 · 取消 · 有界通道 · 计时器         │
└──────┬───────────────────┬───────────────────┬───────────────────────┘
       │                   │                   │
  ┌────▼─────┐      ┌──────▼──────┐     ┌──────▼───────────┐
  │ SQLite   │      │ Redis 8     │     │ llama.cpp (in-proc)│
  │ 事实源   │      │ 向量/缓存   │     │ bge-small-zh-v1.5 │
  └──────────┘      └─────────────┘     └──────────────────┘
       │
       └──────────────► 云端 LLM（OpenAI 兼容 /v1/chat/completions）
```

### 3.1 模块依赖方向

```
http → api → agent → {llm, tools, rag, skills, mcp, store, vector}
                 └→ store / vector 只被下层调用，不反向依赖
util / rt 为叶子，禁止依赖业务
```

用 CMake 的 `target_link_libraries(... PRIVATE)` 强制这个方向：`chatvv_core` 是一个静态库，测试直接链接它，HTTP 层不进测试。

### 3.2 为什么不用现成 Web 框架

- **Drogon**：路由/ORM 齐全，但对 SSE 的逐块控制和请求取消的暴露程度不如直接握 Asio；且引入 trantor + jsoncpp 等一整条依赖链。
- **cpp-httplib**：一天能跑通，但线程每连接，长 SSE 会占住线程，Agent 一次运行几分钟，几个标签页就把池子耗干。
- **Boost.Beast**：样板代码多（约 800–1200 行），但换来完整的流控、TLS、超时和 `cancellation_signal`。对“长连接 + 可取消”的产品形态，这是核心需求，不是可选项。

**备选方案**：如果 M0 想先验证 API 形状，可以用 cpp-httplib 做一次性 spike，确认后再换 Beast；**不要**在中间抽象一层 `IHttpServer`，两种流式模型的抽象一定会漏。

---

## 4. 进程、线程与并发

### 4.1 线程划分

| 池 | 数量 | 职责 | 规则 |
|---|---|---|---|
| io | `min(4, hw)` | 接受连接、解析 HTTP、SSE 写出、定时器、信号 | **绝不**执行 SQL、Redis、嵌入 |
| blocking | 4 | SQLite 读写、Redis 命令、文件解析 | 有界队列；排队超时直接 503 |
| embed | 1 | llama.cpp 编码（独占 context） | 批量合并请求，micro-batch 32 |
| curl | 每请求 1 个 worker（可复用池） | LLM / MCP HTTP 流式读取 | 通过 `asio::post` 把增量投回 io |

> 为什么嵌入要独占线程：llama.cpp 的 context 不是线程安全的；用单线程 + 批处理比加锁更简单，也更省内存。CPU 打满时用信号量做背压。

### 4.2 一次请求的协程形态

```cpp
asio::awaitable<void> handle_chat(Request req) {
  auto run = co_await runs_.create(req);          // SQLite，走 blocking 池
  co_spawn(io_, agent_.execute(run), detach);     // 与连接解耦
  co_await sse_.attach(req.response, run.id);     // 订阅事件；断线即 detach
}
```

- **连接与执行解耦**：客户端断开不会杀 Run；重新 `GET /v1/runs/{id}/events` 继续看。
- **取消**：`asio::cancellation_signal` 挂在 Run 上，HTTP 请求、curl 传输、子进程 kill 都绑定它。
- **背压**：SSE 写出使用有界队列（默认 256 条事件 / 1 MB）。客户端太慢时合并 `message.delta`，超过阈值则断开并保留事件在 SQLite，客户端重连后补齐。
- **超时**：连接 10s / 首 token 60s / 流空闲 120s / 单次 Run 15min（均可配置）。

### 4.3 为什么不用“一请求一线程”

Agent 一次运行可能包含 3–10 次 LLM 往返和多次工具调用，持续数分钟。线程模型下这是 1 个线程被占死；协程模型下只是 1 个状态机 + 少量内存。边缘设备只有 4 核，这个差别是决定性的。

---

## 5. 存储设计

### 5.1 职责边界

| 数据 | 位置 | 理由 |
|---|---|---|
| 会话、消息、Run、事件、文档、分块文本、embedding 备份、审计 | SQLite | 事务、可备份、可迁移、单文件 |
| 向量索引、检索缓存、限流计数、幂等键、Run 事件热缓存 | Redis | 内存索引、TTL、原子计数 |
| 上传的原始文件 | 数据目录 `uploads/` | 大对象不进 DB；DB 存 sha256 与路径 |
| 模型文件 | 数据目录 `models/` | 只读，sha256 校验 |
| Skills | 数据目录 `skills/` | 用户可直接编辑，热重载 |

**关键决定**：`chunks.embedding` 在 SQLite 里存一份 f32 blob。Redis 索引是纯派生数据，重建时只做 HSET，不重新跑模型。10 万 chunk 重建约几十秒（受 Redis pipeline 与内存带宽限制），而不是几十分钟。

### 5.2 SQLite 表结构（节选）

```sql
PRAGMA journal_mode=WAL;
PRAGMA synchronous=NORMAL;
PRAGMA foreign_keys=ON;
PRAGMA busy_timeout=5000;

CREATE TABLE tenants (
  id          TEXT PRIMARY KEY,          -- ULID，无标点，方便做 Redis TAG
  name        TEXT NOT NULL,
  created_at  INTEGER NOT NULL
) STRICT;

CREATE TABLE api_keys (
  id          TEXT PRIMARY KEY,
  tenant_id   TEXT NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,
  prefix      TEXT NOT NULL,             -- 展示用，如 cv_7f3a
  key_hash    BLOB NOT NULL,             -- sha256(完整 key)
  scopes      TEXT NOT NULL,             -- JSON: ["chat","documents","admin"]
  created_at  INTEGER NOT NULL,
  last_used_at INTEGER,
  revoked_at  INTEGER
) STRICT;

CREATE TABLE conversations (
  id          TEXT PRIMARY KEY,
  tenant_id   TEXT NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,
  title       TEXT NOT NULL DEFAULT '',
  model       TEXT NOT NULL,
  system_prompt TEXT,
  archived    INTEGER NOT NULL DEFAULT 0,
  created_at  INTEGER NOT NULL,
  updated_at  INTEGER NOT NULL
) STRICT;
CREATE INDEX idx_conv_tenant ON conversations(tenant_id, updated_at DESC);

CREATE TABLE messages (
  id              TEXT PRIMARY KEY,
  conversation_id TEXT NOT NULL REFERENCES conversations(id) ON DELETE CASCADE,
  run_id          TEXT,
  seq             INTEGER NOT NULL,
  role            TEXT NOT NULL,         -- user | assistant | tool | system
  content_json    TEXT NOT NULL,         -- parts 数组，见 api.md
  token_count     INTEGER NOT NULL DEFAULT 0,
  created_at      INTEGER NOT NULL,
  UNIQUE(conversation_id, seq)
) STRICT;

CREATE TABLE runs (
  id              TEXT PRIMARY KEY,
  conversation_id TEXT NOT NULL REFERENCES conversations(id) ON DELETE CASCADE,
  status          TEXT NOT NULL,         -- queued|running|awaiting_approval|completed|failed|cancelled
  model           TEXT NOT NULL,
  params_json     TEXT NOT NULL DEFAULT '{}',
  usage_json      TEXT,
  error_code      TEXT,
  error_detail    TEXT,
  cancel_requested INTEGER NOT NULL DEFAULT 0,
  created_at      INTEGER NOT NULL,
  started_at      INTEGER,
  finished_at     INTEGER
) STRICT;

CREATE TABLE run_events (
  run_id      TEXT NOT NULL REFERENCES runs(id) ON DELETE CASCADE,
  seq         INTEGER NOT NULL,
  type        TEXT NOT NULL,
  data_json   TEXT NOT NULL,
  created_at  INTEGER NOT NULL,
  PRIMARY KEY (run_id, seq)
) STRICT, WITHOUT ROWID;

CREATE TABLE collections (
  id          TEXT PRIMARY KEY,
  tenant_id   TEXT NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,
  name        TEXT NOT NULL,
  embedding_model TEXT NOT NULL,         -- 索引与查询必须一致
  dim         INTEGER NOT NULL,
  chunk_size  INTEGER NOT NULL DEFAULT 500,
  chunk_overlap INTEGER NOT NULL DEFAULT 80,
  config_json TEXT NOT NULL DEFAULT '{}',
  UNIQUE(tenant_id, name)
) STRICT;

CREATE TABLE documents (
  id            TEXT PRIMARY KEY,
  tenant_id     TEXT NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,
  collection_id TEXT NOT NULL REFERENCES collections(id) ON DELETE CASCADE,
  title         TEXT NOT NULL,
  mime          TEXT NOT NULL,
  path          TEXT NOT NULL,           -- uploads/ 下相对路径
  sha256        TEXT NOT NULL,
  size          INTEGER NOT NULL,
  status        TEXT NOT NULL,           -- pending|parsing|indexing|ready|failed
  error         TEXT,
  created_at    INTEGER NOT NULL
) STRICT;

CREATE TABLE chunks (
  id            TEXT PRIMARY KEY,
  document_id   TEXT NOT NULL REFERENCES documents(id) ON DELETE CASCADE,
  collection_id TEXT NOT NULL REFERENCES collections(id) ON DELETE CASCADE,
  idx           INTEGER NOT NULL,
  heading       TEXT,
  text          TEXT NOT NULL,
  token_count   INTEGER NOT NULL,
  hash          TEXT NOT NULL,           -- sha256(normalized text + model)
  embedding     BLOB,                    -- f32 little-endian, dim*4 字节
  created_at    INTEGER NOT NULL,
  UNIQUE(document_id, idx)
) STRICT;
CREATE INDEX idx_chunks_coll ON chunks(collection_id);

-- 中文检索：写入前用 jieba 分词，查询时同样分词；不用 trigram（2 字词会失效）
CREATE VIRTUAL TABLE chunks_fts USING fts5(
  chunk_id UNINDEXED,
  text_seg,
  tokenize='unicode61 remove_diacritics 2'
);
```

其余表：`tool_calls`、`skills`、`mcp_servers`、`usage`、`audit_log`、`settings`、`schema_migrations`。

写入策略：**单写连接 + 互斥量**，读走线程本地只读连接。WAL 下读不阻塞写；单人场景不需要连接池。

### 5.3 Redis 键与索引

```
# 向量（hash，字段值是二进制安全的）
chunk:{tenant}:{chunk_id}
  vec     <512 * 4 bytes, little-endian f32, L2 归一化>
  cid     01J...        # chunk id
  tenant  01J...
  coll    01J...
  doc     01J...
  lang    zh
  ts      1761...

# 其他
rl:{key}:{window}          # 限流计数
idem:{key}                 # 幂等（TTL 24h）
runcache:{run_id}:{seq}    # 事件热缓存（TTL 1h）
sem:{collection}:{hash}    # 可选：语义缓存
```

建索引（Redis 8 / valkey-search 语法兼容）：

```
FT.CREATE idx_chunks ON HASH PREFIX 1 chunk: SCHEMA
  vec    VECTOR HNSW 6 TYPE FLOAT32 DIM 512 DISTANCE_METRIC COSINE M 16 EF_CONSTRUCTION 200
  cid    TAG
  tenant TAG
  coll   TAG
  doc    TAG
  lang   TAG
  ts     NUMERIC
```

检索（先过滤再 KNN，DIALECT 2 支持这种写法）：

```
FT.SEARCH idx_chunks
  "(@tenant:{01J...} @coll:{01J...})=>[KNN 40 @vec $q AS dist]"
  PARAMS 2 q <2048 bytes>
  SORTBY dist
  RETURN 3 cid 1 doc 1 dist 1
  DIALECT 2
```

注意：
- TAG 值里不要出现 `-`、`.`、空格等需要转义字符，所以 ID 统一用 **ULID**（26 位 Crockford Base32，无标点）。
- 单索引 + TAG 过滤，而不是“每个 collection 一个索引”。边缘规模下更省事，也避免索引数量爆炸。
- 向量按 **f32** 存，先不做量化。512 维 × 4 B ≈ 2 KB/条，加上 HNSW 图开销约 2.5–3 KB/条；10 万条约 300 MB，8 GB 设备可接受。若内存吃紧，再评估 Redis 8 的 INT8/SVS-VAMANA（需要全链路一致量化）。

### 5.4 备份与恢复

| 操作 | 做法 |
|---|---|
| 日常备份 | `sqlite3 data/chatvv.db ".backup 'backup.db'"`（在线安全） |
| Redis 丢失 | 启动时比对 `chunks` 与索引，缺失则后台重建；或 `chatvvd reindex --all` |
| 换嵌入模型 | 新 collection（`embedding_model`/`dim` 固定）；或 `reindex --reembed` 全量重算 |
| 迁移设备 | 拷 `data/` 目录 + `config.toml`，Redis 空库即可 |

---

## 6. 一次带 RAG 与工具的对话（时序）

```
客户端            http/SSE          agent/Run         rag            llm        mcp/tools
  │ POST messages    │                  │              │              │             │
  │─────────────────>│ 建 Run(202)      │              │              │             │
  │<── {run_id} ─────│── spawn ────────>│              │              │             │
  │ GET events       │                  │              │              │             │
  │─────────────────>│── subscribe ────>│              │              │             │
  │                  │                  │ 检索(若开启)  │              │             │
  │                  │                  │─────────────>│              │             │
  │                  │                  │<── hits ─────│              │             │
  │                  │                  │ 组装上下文    │              │             │
  │                  │                  │── chat(stream) ────────────>│             │
  │                  │<─ message.delta ─│<── tokens ──────────────────│             │
  │                  │                  │── tool_call ────────────────│             │
  │                  │<─ tool.call ─────│              │              │             │
  │                  │                  │── 执行（可能需审批）─────────────────────>│
  │                  │<─ tool.result ───│<──────────────────────────────────────────│
  │                  │                  │── 第二次 chat ─────────────>│             │
  │                  │<─ message.delta ─│              │              │             │
  │                  │<─ usage/done ────│              │              │             │
  │                  │                  │ 落库 messages/run_events    │             │
```

关键点：

1. **先检索后调用**：RAG 在第一次 LLM 请求前完成；模型也可以主动调用 `rag_search` 做二次检索。
2. **上下文有预算**：`系统提示 + 工具描述 + 检索片段 + 历史 + 用户输入` 共享一个 token 预算，超限时先压缩历史，再截断检索片段。
3. **事件全部落库**：SSE 只是 SQLite 中 `run_events` 的实时投影，重连靠 `after=seq` 回放。
4. **工具结果可截断**：超过 8k token 的结果落盘为 artifact，上下文里只放摘要 + 句柄。

---

## 7. 安全模型

| 威胁 | 对策 |
|---|---|
| API Key 泄漏 | 随机 32 字节 key，只存 SHA-256，比较用常量时间；浏览器走 HttpOnly Cookie，不落 localStorage |
| 未授权访问 | 默认只监听 `127.0.0.1`；对外必须显式 `bind = "0.0.0.0"` + TLS（内置或 Caddy 反代） |
| 提示词注入（文档/网页/工具输出） | 不可信内容用定界符包裹并标注来源；危险工具强制审批；系统提示明确“检索内容是指令之外的资料” |
| 工具越权 | 工具分级 `read_only / mutating / dangerous`；路径牢笼（`weakly_canonical` + 前缀校验）；默认禁用 shell |
| 脚本执行 | 默认关闭；开启后经 `bwrap` 沙箱（只读根、无网络、独立 tmpfs、超时 30s、输出 1 MB 上限） |
| MCP 服务器风险 | 白名单；stdio 不走 shell；环境变量白名单；HTTP 出站做 SSRF 防护（默认拒绝私网地址）；工具名加服务器前缀防覆盖 |
| Skills 投毒 | 内容视为不可信输入；加载时展示来源；MCP 来源的 `allowed-tools` 默认忽略；按内容摘要绑定审批 |
| 上传文件 | 限制大小与 MIME、随机文件名、存于 Web 根之外、永不执行；解析失败只记录不崩溃 |
| XSS | 前端 `rehype-sanitize` + CSP；后端不返回 HTML 片段 |
| 资源耗尽 | 请求体上限、并发 Run 上限、单用户 token 配额、SSE 背压、SQLite `busy_timeout` |

密钥管理：LLM key、MCP OAuth token 用 `libsodium` secretbox 加密后存库，主密钥来自环境变量或内核 keyring；配置文件里不出现明文密钥。

---

## 8. 可观测性

- **日志**：spdlog 异步 + JSON 格式，字段固定 `ts, level, request_id, run_id, tenant, event, latency_ms`；按天轮转，保留 7 天。
- **指标**：手写 Prometheus 文本端点（约 100 行，避免引 opentelemetry-cpp）：
  - `chatvv_http_requests_total{route,status}`
  - `chatvv_llm_ttft_seconds`、`chatvv_llm_tokens_total{kind}`
  - `chatvv_embed_batch_seconds`、`chatvv_embed_queue_depth`
  - `chatvv_rag_search_seconds`、`chatvv_rag_hits`
  - `chatvv_tool_calls_total{tool,status}`
  - `chatvv_redis_up`、`chatvv_sqlite_size_bytes`
- **健康检查**：`/healthz`（进程存活）、`/readyz`（SQLite 可写、Redis 可连、嵌入模型已加载；未加载时 RAG 降级但聊天可用）。
- **审计**：`audit_log` 记录每次工具调用、文档删除、配置变更、登录。
- **追踪**（可选）：MCP `_meta` 支持 `traceparent`，未来接 OTLP 时不用改协议层。

---

## 9. 部署形态

### 9.1 目录布局

```
/opt/chatvv/
├── bin/chatvvd
├── config.toml
└── data/                 # 可用 --data-dir 覆盖
    ├── chatvv.db
    ├── uploads/
    ├── models/bge-small-zh-v1.5.gguf
    ├── skills/
    └── artifacts/
```

### 9.2 systemd（要点）

```ini
[Service]
ExecStart=/opt/chatvv/bin/chatvvd --config /opt/chatvv/config.toml
User=chatvv
NoNewPrivileges=yes
ProtectSystem=strict
ProtectHome=yes
ReadWritePaths=/opt/chatvv/data
PrivateTmp=yes
MemoryMax=2G
Restart=on-failure
```

### 9.3 Redis

- 推荐 **Redis 8**（Query Engine 内置），监听 **Unix socket**，`--save ""`（向量可重建，不需要 RDB）。
- 提供 `redis.managed = true` 时由 `chatvvd` 启动并守护子进程（appliance 体验），默认 `false`（交给 systemd）。
- 注意：Arch 的 `redis` 包现在是 **valkey 9.1.2 且不带 search 模块**，本机开发必须用 Docker `redis:8` 或 `valkey-bundle`。

### 9.4 TLS

优先用 Caddy 反代（自动证书、HTTP/2、SSE 友好）：

```
chat.example.com {
  reverse_proxy 127.0.0.1:8080 {
    flush_interval -1
  }
}
```

`flush_interval -1` 是 SSE 的关键，否则会攒包。

---

## 10. 关键技术决策（ADR 摘要）

| # | 决策 | 备选 | 理由 |
|---|---|---|---|
| 1 | Asio + Beast | cpp-httplib / Drogon / uWebSockets | 长连接、可取消、单一事件循环；样板代码是可接受的一次性成本 |
| 2 | SQLite 事实源 + Redis 派生 | 全 Redis / Postgres | 单文件备份、事务、离线可用；Redis 只做它擅长的事 |
| 3 | 本地 llama.cpp 嵌入 | ONNX Runtime / 远程 embedding API | 无网可用、一个运行时兼顾 rerank 与本地 LLM；ORT 留作性能备选 |
| 4 | Run 模型 + SSE 事件流 | 直接挂长连接 | 断线恢复、多端观察、取消传播；OpenAI 兼容层另做 |
| 5 | 应用层 RRF 混合检索 | Redis 8.4 `FT.HYBRID` | 不绑定 8.4；Valkey 无全文索引，应用层方案两边都能跑 |
| 6 | Skills 用 SKILL.md 标准 | 自定义 JSON 配置 | 生态兼容（MCP 已有 Skills 扩展）、人类可读、渐进式披露 |
| 7 | MCP 以 2026-07-28 为目标、兼容 2025-11-25 | 只做旧版 | 新规范无状态、更简单；但现有服务器多是旧版 |
| 8 | 单二进制 + 静态核心库 | 微服务 | 边缘部署运维成本决定 |

### 10.1 明确否决的方案

- **Qdrant / Milvus**：为了 10 万条向量再起一个服务，不划算；Redis 已经因为缓存/限流必须在。
- **Postgres + pgvector**：能力没问题，但边缘设备上内存与运维成本高于 SQLite+Redis。
- **纯 SQLite + sqlite-vec**：其实很有吸引力（零守护进程）。如果实测 Redis 内存不可接受，这是首选退路；因此 `vector/` 必须只有 `search/upsert/remove` 三个语义接口，不做 Redis 特有泄漏。
- **自己实现 HTTP/2**：单用户场景 HTTP/1.1 + SSE 足够；HTTP/2 交给 Caddy。
- **在 C++ 里实现 BPE 分词给 LLM 数 token**：先用启发式估算（中文 ≈ 1 token/字，英文 ≈ 1 token/4 字符），真实用量以 provider 返回为准；本地模型才用 llama tokenizer。

---

## 11. 已知风险

| 风险 | 影响 | 缓解 |
|---|---|---|
| C++ 开发速度 | 里程碑延期 | M0 先做最小闭环；HTTP 层一次写对；用 sanitizer + 集成测试兜底 |
| 中文检索效果差 | RAG 不可用 | 建 30–50 条评测集；向量 + jieba BM25 + RRF；必要时上 rerank |
| Redis 内存占用 | 边缘 OOM | f32→int8 量化、减少 `M`、只索引必要字段；保留 sqlite-vec 退路 |
| MCP 规范继续变 | 客户端返工 | 传输/协议分层；版本探测集中在 `mcp/version.cpp` |
| 工具执行安全 | 设备被控制 | 默认只读、审批、沙箱、审计；默认不开放网络监听 |
| SSE 被代理缓冲 | 前端“不流式” | 文档写明 `X-Accel-Buffering: no` 与 Caddy 配置；`/readyz` 自检 |
| 模型许可 | 分发受限 | bge 系列 MIT；分发前核对每个模型 LICENSE |

---

## 12. 下一步

1. 拍板 [待确认的 5 个问题](build-roadmap.md#7-需要你拍板的问题)。
2. 按 [M0 清单](build-roadmap.md#6-里程碑) 搭骨架：CMake + vcpkg + Beast SSE + SQLite + OpenAI 兼容 Provider。
3. 用真实文档跑一遍 [RAG 评测集](rag-agent-mcp-skills.md#7-评估不要跳过)，再决定是否引入 rerank。

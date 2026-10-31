# chatvv API 契约

> 状态：API 目标草案。M0 已实现单对话 / SSE / 历史 / 取消 / 注入等子集；Flutter 客户端尚未接入。
> 以实际 `/v1/*` 行为为准；Auth / OpenAPI / 文档库等为后续目标。
> 基址：`https://<host>/v1`　协议：HTTPS + JSON + SSE　规范：OpenAPI 3.1（`/openapi.json`）

---

## 1. 通用约定

### 1.1 版本与兼容

- 路径版本：`/v1`。破坏性变更升 `/v2`，旧版至少保留 6 个月。
- 响应只增字段不删字段；客户端必须忽略未知字段。
- ID 统一 **ULID**（26 位，字典序即时间序），不用 UUID（避免 Redis TAG 转义）。
- 时间统一 UNIX 毫秒（`created_at`），展示交给前端。

### 1.2 鉴权

```
Authorization: Bearer cv_live_7f3a9c...
```

- Key 由服务端 CLI 生成：`chatvvd key create --name "laptop" --scopes chat,documents`。
- 作用域：`chat`、`documents`、`admin`、`read`。缺省 `chat`。
- 浏览器不便保存 Bearer，改用会话 Cookie：

```
POST /v1/auth/session     { "api_key": "cv_live_..." }
→ 204 + Set-Cookie: chatvv_session=<opaque>; HttpOnly; SameSite=Strict; Path=/; Max-Age=...
```

之后同源请求自动带 Cookie；`DELETE /v1/auth/session` 注销。Cookie 里的令牌是服务端生成的随机会话 ID，不是 API Key 本身。

### 1.3 错误模型（RFC 9457）

```json
{
  "type": "https://chatvv.dev/errors/rate_limited",
  "title": "Rate limit exceeded",
  "status": 429,
  "code": "rate_limited",
  "detail": "最多 30 次/分钟，请 12 秒后重试",
  "request_id": "01JB8Z3K4M5N6P7Q8R9S0T1V2W",
  "retry_after": 12
}
```

`Content-Type: application/problem+json`。`code` 是稳定的机器可读值，前端据此做分支；`detail` 可变。

| HTTP | code 示例 | 场景 |
|---|---|---|
| 400 | `invalid_request` | JSON 结构错误、缺必填字段 |
| 401 | `invalid_api_key` | Key 缺失/过期/吊销 |
| 403 | `insufficient_scope` / `approval_denied` | 作用域不足、用户拒绝工具审批 |
| 404 | `not_found` | 资源不存在或不属于当前租户 |
| 409 | `run_in_progress` / `conversation_busy` | 同一会话已有活跃 Run |
| 413 | `payload_too_large` | 上传/请求体超限 |
| 422 | `tool_arguments_invalid` | 模型给出的工具参数不合 schema |
| 429 | `rate_limited` / `quota_exceeded` | 限流、token 配额 |
| 502 | `upstream_error` | LLM/MCP 上游失败 |
| 503 | `not_ready` | 依赖未就绪（模型加载中、Redis 断连） |

### 1.4 分页、幂等、限流

- 分页统一游标：`?limit=50&cursor=<opaque>` → `{ "data": [...], "next_cursor": null }`。禁用 offset。
- 写操作支持 `Idempotency-Key: <uuid>`（TTL 24h），重复请求返回首次结果。
- 限流响应头：`X-RateLimit-Limit`、`X-RateLimit-Remaining`、`X-RateLimit-Reset`。
- 所有响应带 `X-Request-Id`；客户端可传 `X-Request-Id` 以便串联日志。

### 1.5 CORS

仅允许配置中的 `cors.allowed_origins`；预检缓存 600s；允许 `Authorization, Content-Type, Idempotency-Key, Last-Event-ID`。

---

## 2. 端点总览

### 会话与对话

| 方法 | 路径 | 说明 |
|---|---|---|
| GET | `/capabilities` | 前端据此决定渲染哪些功能 |
| GET | `/models` | 可用模型与能力（工具/视觉/上下文长度） |
| POST | `/conversations` | 新建会话 |
| GET | `/conversations` | 会话列表（游标） |
| GET | `/conversations/{id}` | 会话详情（含最近消息可选） |
| PATCH | `/conversations/{id}` | 改标题/系统提示/归档 |
| DELETE | `/conversations/{id}` | 删除会话（级联消息与 Run） |
| GET | `/conversations/{id}/messages` | 历史消息（倒序游标 + `before`） |
| POST | `/conversations/{id}/messages` | 发消息，创建 Run |
| GET | `/runs/{run_id}` | Run 状态 |
| GET | `/runs/{run_id}/events` | SSE 事件流（可回放） |
| POST | `/runs/{run_id}/cancel` | 取消 |
| POST | `/runs/{run_id}/approvals/{approval_id}` | 审批工具调用 |
| POST | `/conversations/{id}/regenerate` | 重生成最后一条回答 |

### 知识库

| 方法 | 路径 | 说明 |
|---|---|---|
| GET/POST | `/collections` | 列出/创建集合 |
| DELETE | `/collections/{id}` | 删除集合及其文档 |
| POST | `/collections/{id}/documents` | multipart 上传，202 异步处理 |
| GET | `/documents/{id}` | 文档状态与进度 |
| DELETE | `/documents/{id}` | 删除文档与向量 |
| POST | `/collections/{id}/search` | 调试检索（返回分数与片段） |
| POST | `/collections/{id}/reindex` | 重建索引（从 SQLite 的 embedding 备份） |

### Agent 配置

| 方法 | 路径 | 说明 |
|---|---|---|
| GET | `/tools` | 当前可用工具（内置 + MCP） |
| GET/POST | `/mcp/servers` | MCP 服务器列表/新增 |
| PATCH/DELETE | `/mcp/servers/{id}` | 启停/删除 |
| POST | `/mcp/servers/{id}/reload` | 重连并刷新工具 |
| GET | `/skills` | 已发现 Skills 与校验状态 |
| POST | `/skills/reload` | 重新扫描目录 |
| PATCH | `/skills/{name}` | 启用/禁用 |
| GET | `/skills/{name}/content` | 预览 SKILL.md（不进入上下文） |

### 运维

| 方法 | 路径 | 说明 |
|---|---|---|
| GET | `/usage` | 按天聚合的 token/费用 |
| GET | `/healthz` | 存活探针（不鉴权） |
| GET | `/readyz` | 就绪探针（不鉴权） |
| GET | `/metrics` | Prometheus 文本（可配 token 保护） |
| GET | `/openapi.json` | OpenAPI 3.1 |

### 兼容层

| 方法 | 路径 | 说明 |
|---|---|---|
| POST | `/chat/completions` | OpenAI 兼容（`stream` 支持，含 tool_calls） |
| POST | `/embeddings` | 本地嵌入模型（OpenAI 兼容响应） |
| GET | `/models` | 同时满足 OpenAI 客户端 |

---

## 3. 核心资源

### 3.1 Message（`content_json` 是 parts 数组）

```json
{
  "id": "01JB8Z3K4M5N6P7Q8R9S0T1V2W",
  "conversation_id": "01JB8Y...",
  "run_id": "01JB8Z...",
  "seq": 12,
  "role": "assistant",
  "created_at": 1761300000000,
  "parts": [
    { "type": "text", "text": "根据文档，风险点主要有三处……" },
    { "type": "citation", "index": 1, "chunk_id": "01JB9...", "document_id": "01JB7...", "title": "采购合同.pdf", "page": 3, "score": 0.83 },
    { "type": "tool_call", "call_id": "call_a1", "name": "rag_search", "arguments": { "query": "违约责任" }, "status": "completed" },
    { "type": "tool_result", "call_id": "call_a1", "status": "ok", "preview": "命中 6 段…", "artifact_id": null }
  ]
}
```

parts 类型：`text` | `reasoning`（可选展示）| `citation` | `tool_call` | `tool_result` | `image`（后续）| `skill`（Skill 加载记录，含来源）。

### 3.2 Conversation

```json
{
  "id": "01JB8Y...",
  "title": "采购合同风险",
  "model": "gpt-4.1-mini",
  "system_prompt": null,
  "archived": false,
  "message_count": 18,
  "created_at": 1761290000000,
  "updated_at": 1761300000000
}
```

### 3.3 Run

```json
{
  "id": "01JB8Z...",
  "conversation_id": "01JB8Y...",
  "status": "running",
  "model": "gpt-4.1-mini",
  "usage": { "prompt_tokens": 3120, "completion_tokens": 210, "cached_tokens": 0 },
  "error": null,
  "created_at": 1761300000000,
  "started_at": 1761300000100,
  "finished_at": null
}
```

`status`：`queued` → `running` → (`awaiting_approval`) → `completed` | `failed` | `cancelled`。

---

## 4. 发消息与流式输出

### 4.1 请求

```http
POST /v1/conversations/01JB8Y.../messages
Authorization: Bearer cv_live_...
Content-Type: application/json
Idempotency-Key: 6f1c2b1e-...

{
  "client_message_id": "local-42",
  "content": "帮我总结这份合同的风险点，并对照我们上次的评审意见",
  "model": "gpt-4.1-mini",
  "rag": {
    "enabled": true,
    "collection_ids": ["01JB7..."],
    "top_k": 6,
    "mode": "hybrid"
  },
  "tools": { "mode": "auto", "deny": ["shell_exec"] },
  "skill": "contract-review",
  "max_steps": 8
}
```

字段说明：

| 字段 | 默认 | 说明 |
|---|---|---|
| `content` | 必填 | 纯文本；附件/图片走 `attachments` |
| `model` | 会话默认 | 必须在 `/capabilities.models` 中 |
| `rag.enabled` | 会话设置 | 关闭则完全不做检索 |
| `rag.mode` | `hybrid` | `vector` / `hybrid` / `hybrid_rerank` |
| `rag.collection_ids` | 全部可读集合 | 显式限定范围 |
| `top_k` | 6 | 最终进入上下文的片段数 |
| `tools.mode` | `auto` | `auto` / `none` / `require` |
| `tools.deny` | `[]` | 会话级禁用名单，优先级高于服务端配置 |
| `skill` | 无 | 预加载某个 Skill（仍然走审批策略） |
| `max_steps` | 8 | 上限受服务端 `agent.max_steps` 限制 |
| `client_message_id` | 无 | 前端乐观更新的去重键 |

**响应**：

- 默认 `202 Accepted`：

```json
{ "run_id": "01JB8Z...", "events_url": "/v1/runs/01JB8Z.../events", "status": "queued" }
```

- `?stream=1` 且 `Accept: text/event-stream`：直接 `200` 建立 SSE，首个事件带 `run_id`。

**并发语义**：同一会话同时只允许一个活跃 Run，冲突返回 `409 conversation_busy`。不做服务端排队（边缘设备排队会放大延迟），由前端串行化。

### 4.2 SSE 事件流

```http
GET /v1/runs/01JB8Z.../events?after=0
Accept: text/event-stream
Last-Event-ID: 16          # 二选一，after 优先
```

响应头：

```
Content-Type: text/event-stream
Cache-Control: no-cache, no-transform
Connection: keep-alive
X-Accel-Buffering: no
```

事件格式（`id` = 单调递增 `seq`，从 1 开始）：

```
id: 17
event: message.delta
data: {"run_id":"01JB8Z...","message_id":"01JB8Z9...","delta":"风险点"}

id: 18
event: message.delta
data: {"run_id":"01JB8Z...","message_id":"01JB8Z9...","delta":"主要有"}

```

事件表：

| event | 载荷要点 | 前端处理 |
|---|---|---|
| `run.started` | `run_id, model, started_at` | 建立气泡、显示“思考中” |
| `message.started` | `message_id, role` | 创建消息占位 |
| `message.delta` | `message_id, delta` | 追加文本，节流渲染 |
| `reasoning.delta` | `message_id, delta` | 折叠区展示（可选） |
| `retrieval.completed` | `hits[]（chunk_id,title,score,preview）` | 展示“已引用 N 篇” |
| `tool.call.started` | `call_id, name, arguments, risk_level` | 渲染工具卡片 |
| `tool.call.delta` | `call_id, delta`（流式参数/进度） | 卡片内更新 |
| `tool.call.completed` | `call_id, status, duration_ms, preview` | 卡片完成态 |
| `tool.approval.required` | `approval_id, call_id, name, arguments, risk_level, expires_at` | 弹审批框 |
| `usage.updated` | `prompt_tokens, completion_tokens` | 显示用量 |
| `run.completed` | `message_id, usage, finish_reason` | 收尾、解除忙碌 |
| `run.failed` | `code, detail` | 错误条 + 重试 |
| `run.cancelled` | — | 标记已中断 |
| `ping` | `ts` | 每 15s，防代理断流 |

约定：

- 服务端**先落库再推送**；客户端断线后 `after=最后收到的 id` 可无损续看。
- 客户端超过 3 次重连失败后应调用 `GET /runs/{id}` 判断状态，避免无限重试。
- 事件保留：Run 结束后保留 24 小时，之后只保留消息终态。
- 心跳与业务事件共用连接；`ping` 不写库。

### 4.3 审批

```http
POST /v1/runs/01JB8Z.../approvals/01JBA...
{ "decision": "approve", "scope": "once" }     # once | session | always
```

- `approve` 后 Run 继续；`deny` 则把拒绝结果作为工具输出回给模型（模型可换方案）。
- 审批默认 5 分钟过期，过期视为 `deny` 并结束 Run（`approval_timeout`）。
- 仅 `risk_level >= mutating` 的工具触发；`read_only` 不打断。

### 4.4 取消

```http
POST /v1/runs/01JB8Z.../cancel
→ 202 { "status": "cancelling" }
```

取消信号传播到：LLM HTTP 传输、MCP 请求、子进程（SIGTERM → 3s → SIGKILL）、SSE 写出。终态为 `cancelled`，已生成的部分内容保留。

---

## 5. 知识库接口

### 5.1 上传

```http
POST /v1/collections/01JB7.../documents
Content-Type: multipart/form-data

file=@合同.pdf
title=采购合同
metadata={"source":"2026-Q3"}
```

```json
202 Accepted
{ "document_id": "01JB6...", "status": "pending", "job_id": "01JB6J..." }
```

- 支持 `text/plain`、`text/markdown`、`application/pdf`、`text/html`、`docx`（后续）。
- 单文件上限默认 32 MB；PDF 通过 `pdftotext` 子进程解析（缺失则该格式不可用，`/capabilities` 会体现）。
- 处理流程异步：`pending → parsing → indexing → ready | failed`，进度与错误见 `GET /documents/{id}`。
- 相同 `sha256` 且同集合的文档默认拒绝重复上传（`409 duplicate_document`，可用 `?force=1` 覆盖）。

### 5.2 检索调试

```http
POST /v1/collections/01JB7.../search
{ "query": "违约金上限", "top_k": 10, "mode": "hybrid", "filters": { "doc_ids": [] } }
```

```json
{
  "query": "违约金上限",
  "took_ms": 18,
  "hits": [
    { "chunk_id": "01JB9...", "document_id": "01JB6...", "title": "采购合同.pdf",
      "heading": "第 9 条 违约责任", "text": "……", "score": 0.83,
      "signals": { "vector_rank": 1, "bm25_rank": 4, "rerank_score": null } }
  ]
}
```

`signals` 是调参的关键：能看出是向量召回还是关键词召回起的作用。

---

## 6. 能力协商（前端空壳的关键）

`GET /v1/capabilities`：

```json
{
  "version": "0.1.0",
  "features": {
    "chat": true,
    "streaming": true,
    "rag": true,
    "rerank": false,
    "tools": true,
    "mcp": true,
    "skills": true,
    "local_llm": false,
    "pdf": true
  },
  "embedding": { "model": "bge-small-zh-v1.5", "dim": 512, "max_tokens": 512 },
  "limits": {
    "max_upload_mb": 32,
    "max_context_tokens": 32768,
    "max_steps": 12,
    "max_active_runs": 2,
    "sse_keepalive_seconds": 15
  },
  "models": [
    { "id": "gpt-4.1-mini", "provider": "openai", "tools": true, "vision": false, "context": 1048576 },
    { "id": "qwen2.5-7b-instruct", "provider": "llama.cpp", "tools": true, "vision": false, "context": 32768 }
  ]
}
```

前端据此隐藏按钮、限制上传大小、决定是否显示“引用”。**新增功能不需要改前端代码**（只要字段在 features 里）。

---

## 7. OpenAI 兼容层

目的：让现成客户端（Chatbox、Open WebUI、SDK）能直接接。

- `POST /v1/chat/completions`：支持 `stream`、`tools`、`tool_choice`、`temperature`、`max_tokens`、`stop`；`n>1` 不支持（返回 400）。
- 内部映射：OpenAI `messages` → 本服务 Run；`tools` 直接透传；响应里 `delta.tool_calls` 原样转出。
- 该层**不保留会话**（无 `conversation_id`），每次请求独立；需要持久化用原生 API。
- 限制：不支持 `logprobs`、`response_format` 仅支持 `json_object`；流式结束统一发送 `data: [DONE]`。
- `POST /v1/embeddings`：返回 `{ object:"list", data:[{embedding:[...], index:0}], model, usage }`，方便本地其他程序复用嵌入模型。

---

## 8. Flutter 客户端如何消费

1. **类型**：Flutter 侧手写 DTO 或 `json_serializable`；OpenAPI 生成可选，不强制。
2. **请求**：`dio`（或 `http`）；Full 模式用 FFI，Client 模式用 HTTP/SSE，共用 domain 事件。
3. **流**：`dio` 的 `ResponseType.stream` + 手写 SSE 解析；不用 `EventSource`（无法自定义 Header、无法 POST）。
4. **状态**：`flutter_riverpod` 管数据/连接；页面局部状态用 `ValueNotifier`；不引入重型全局框架。
5. **渲染**：`flutter_markdown`（或自写） + 代码高亮；引用角标点击滚动到 `citation` part；不运行 HTML/JS。
6. **乐观更新**：用 `client_message_id` 去重；收到 `message.started` 时替换临时气泡。
7. **重连**：记录最后 `seq`，`?after=` 续传；App 退后台时断开，回前台恢复；指数退避。
8. **鉴权**：Bearer API Key 存 `flutter_secure_storage`；Client 模式默认 HTTPS；不做 Cookie/refresh token（单人场景无必要）。

### 目录建议

```
app/lib/
├── data/remote/   # HTTP DTO + SSE 解析 + 重连
├── data/embedded/ # FFI（full 模式）
├── features/chat/ # 消息流、输入框、工具卡片、审批弹窗
├── features/memory/
└── features/settings/
```

---

## 9. 未定项（实现时再定，不影响契约稳定性）

- 多模态输入（图片）→ `attachments` 增加 `image` 类型，SSE 不变。
- 语音（TTS/ASR）→ 独立 `/v1/audio/*`，不污染聊天链路。
- 多用户 → 在 `api_keys` 与所有查询上加 `tenant_id` 过滤即可，路径不变。
- 分享链接 → `POST /conversations/{id}/share` 返回只读 token，`GET /shared/{token}`。

# 客户端聊天记录：缓存与同步

> 状态：M0 已实现接口；Flutter 客户端尚未接入。
> 原则：**服务端是唯一事实源，客户端缓存只是只读副本 + 未发送草稿。**

---

## 0. 为什么这样设计

单条对话没有“会话列表”可拉，消息会一直增长。客户端每次全量拉取既慢又浪费，所以：

- 消息带单调递增的 `seq`（服务端分配）。
- 客户端只按 `seq` 合并，**从不自己造 seq**。
- 启动先渲染本地缓存，再拉 `since_seq` 之后的增量；离线也能读。
- 流式生成期间，本地只维护一个“临时气泡”，完成后以服务端记录为准。

---

## 1. 本地存储（IndexedDB）

| Store | 键 | 内容 |
|---|---|---|
| `messages` | `seq` | `{seq, id, role, content, created_at, response_id}` |
| `meta` | key | `last_seq`, `server_id`, `schema_version`, `active_response_id`, `last_event_seq` |

可选索引：`messages.response_id`，用于把一轮的 user/assistant 消息归组。

缓存策略：

- 只存文本，不存 embedding、不存上下文预览。
- 默认保留最近 5,000 条；超出按 `seq` 从旧到新淘汰（淘汰只影响本地，不影响服务端）。
- 切换服务端（`server_id` 变化）或服务端 `server_seq` 小于本地 `last_seq` 时，清空缓存全量重拉。

---

## 2. 启动流程

```text
1. 打开 IndexedDB，读 meta.last_seq
2. 取最近 100 条消息渲染（标记「缓存」）
3. GET /v1/messages/changes?since_seq=last_seq
   ├─ 304 或 data 为空 → 已是最新
   ├─ server_seq < last_seq → 服务端被重置，清缓存，全量拉取
   └─ 有数据 → 按 seq 顺序 upsert，更新 last_seq = server_seq
4. has_more=true 时继续拉，直到追平
5. 标记「已同步」
```

对应接口：

```
GET /v1/messages/changes?since_seq=<n>&limit=200
→ { data: [...], deleted: [], has_more: false, server_seq: 15 }
```

`deleted` 目前恒为空；后续引入删除时，客户端按 id 删除本地记录。

---

## 3. 发送与流式

```text
1. 本地插入一条 pending user 消息（seq = -1，client_id = 本地 ULID）
2. POST /v1/turns  { message, stream: true }
   （或 POST /v1/turns 拿 202，再订阅 GET /v1/responses/{id}/events）
3. 收到 response.created：
   meta.active_response_id = id
   meta.last_event_seq = 0
4. 收到 response.output_text.delta：
   追加到 pending assistant 气泡
5. 收到 response.completed：
   GET /v1/messages/changes?since_seq=last_seq
   用服务端记录替换两条 pending 消息，更新 last_seq
   清空 active_response_id
6. 连接中断：
   GET /v1/responses/{id}/events?after=last_event_seq
   ├─ 正常回放 → 继续
   └─ response.failed / stream_lost → 重新拉 changes，提示「本轮已中断」
```

要点：

- 每个 SSE 事件都有 `id:`（即 `seq`）；客户端把它存进 `meta.last_event_seq`，重连时用 `after` 或 `Last-Event-ID`。
- 不要用 `EventSource`：它不能带 `Authorization` 头，也不能 POST。用 `fetch` + `ReadableStream` 手写解析（约 80 行）。
- 同一时间只允许一个活跃响应；生成期间禁用发送按钮。服务端目前没有强制单活跃 Run，客户端要自律。

---

## 4. ETag 与 304

`GET /v1/messages` 返回：

```
ETag: W/"<server_seq>-<count>"
X-Server-Seq: <server_seq>
Cache-Control: no-cache
```

客户端首屏可以用 `If-None-Match` 做条件请求：

- 304 → 直接用本地缓存，不解析 body。
- 200 → 用返回的 `data` 覆盖本页。

`changes` 也带 ETag，语义相同。**注意：ETag 只用于整页/整批，不是逐条 diff。**

---

## 5. 多标签页与重连

- 用 `BroadcastChannel("chatvv")` 广播 `{type:"last_seq", value}`；其他标签页收到后拉一次 `changes`。
- `visibilitychange` 回到前台时，如果距上次同步超过 30 秒，拉一次 `changes`。
- SSE 断线用指数退避（1s、2s、4s、8s，上限 30s），超过 5 次就停止并显示「重新连接」按钮。
- 服务端每 15 秒发 `: ping` 注释行；客户端解析时忽略以 `:` 开头的行。

---

## 6. 离线

- 离线时只读：渲染 IndexedDB 中的消息，顶部显示「离线，显示本地记录」。
- 禁用发送；草稿保存在 `localStorage`（按 `client_id`）。
- 恢复网络后先拉 `changes`，再允许发送。

---

## 7. 冲突、删除、幂等

- 服务端永远赢。客户端不修改已同步消息。
- 删除：服务端返回 tombstone（`deleted: [id]`），客户端按 id 删除；不要在本地“软删除”后不同步。
- 重发：后续给 `POST /v1/turns` 加 `Idempotency-Key` 或 `client_message_id`；M0 尚未实现，客户端生成 `client_id` 先存在本地，服务端接受后再对齐。

---

## 8. 隐私

- IndexedDB 是明文。自用设备可接受；提供「清空本地缓存」按钮。
- 不要缓存 API key；鉴权走 HttpOnly Cookie 或内存中的 token。
- 不要缓存 `/v1/context/preview` 的结果（可能包含敏感记忆片段）。

---

## 9. M0 已实现的服务端接口

| 方法 | 路径 | 用途 |
|---|---|---|
| GET | `/v1/messages?limit=&before_seq=&after_seq=` | 分页/增量拉取，带 ETag |
| GET | `/v1/messages/changes?since_seq=&limit=` | 客户端同步专用 |
| POST | `/v1/turns` | 发消息，`stream=true` 时直接 SSE |
| GET | `/v1/responses/{id}/events?after=` | 回放/续传 |
| POST | `/v1/responses/{id}/cancel` | 取消 |
| GET | `/v1/responses/{id}` | 响应终态 |

前端接入时优先用 `changes` + `events` 这两个接口，`/v1/messages` 只用于首屏和兜底。

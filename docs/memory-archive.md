# 记忆归档

旧对话归档为长期记忆，避免完整历史无限进入上下文。

## 流程

1. 用户在「设置 → 记忆归档」选择保留最近 N 条消息。
2. 每条「用户输入 + 助理回复」作为一个独立记忆单元写入 `memories`，并写入 `archive_cutoff_seq`。
3. 后续 context 只读取 `seq > archive_cutoff_seq` 的原始消息，同时把最多 12 条
   记忆注入系统提示词。
4. 记忆表记录 `use_count` / `last_used_at`，可用于后续排序和淘汰。

每条记忆限制 2000 字符；RAG 使用每条独立 embedding，避免整段上下文命中率过高。
后续可替换为摘要模型或向量检索。

## 接口

- HTTP：`GET /v1/memories`、`POST /v1/memories/archive`、`DELETE /v1/memories/{id}`
- C ABI：`chatvv_memories`、`chatvv_archive`、`chatvv_delete_memory`
- DB：`archive_messages` / `list_memories` / `delete_memory` / `mark_memory_used`

Full 和 Only client 共用同一套接口和 UI。

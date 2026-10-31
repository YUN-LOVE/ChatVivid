# 本地 RAG

记忆检索使用随应用打包的 GGUF embedding 模型，由 llama.cpp 在本地加载：

- 模型：`bge-small-zh-v1.5-q8_0.gguf`（512 维，MIT）
- 来源：https://huggingface.co/CompendiumLabs/bge-small-zh-v1.5-gguf
- native：`third_party/llama.cpp`（CPU，静态链接）
- 资产：`app/assets/models/bge-small-zh-v1.5-q8_0.gguf`

流程：

1. 归档/存入记忆时，用模型计算 embedding，写入 `memories.embedding`。
2. 新消息进入 context 前，计算 query embedding，按 cosine 相似度取前 8 条记忆。
3. 无 embedding 的旧记忆自动回退到最近记忆，不阻塞对话。

模型缺失时自动降级为无 RAG，不影响普通聊天和上下文清除。

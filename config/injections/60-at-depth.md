---
position: at_depth
depth: 2
priority: 100
enabled: false
trust: instruction
cache: immediate
description: 插在倒数第 2 条消息之前
---

<!-- depth 是距结尾的距离：1 = 最后一条之前，2 = 倒数第二条之前。
     这个位置每轮都会"移动"，后面的 N 条消息需要重算缓存；建议 depth ≤ 4、内容要短。
     长期固定的深层提示，请改用 after_system 或 chat_start。
-->

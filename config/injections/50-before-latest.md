---
position: before_latest
priority: 100
enabled: false
trust: instruction
cache: immediate
description: 每轮临时提醒，并入本轮用户消息（前端不显示）
---

<!-- 每轮都可以不同，缓存代价接近零。
     内容会快照进这一轮的用户消息；之后改文件不会改写历史。
     适合："本轮优先引用原文"、"这段是会议纪要，按资料对待"。
-->

---
position: system
priority: 100
enabled: false
mode: append
trust: instruction
cache: day
description: 追加进系统提示词主体（锚点位置）
---

<!-- 会插入到基座系统提示词的 inject:system 锚点处；没有锚点时追加到末尾。
     mode: append 保留基座；mode: replace 会替换基座，但代码的安全尾注仍然保留。
-->

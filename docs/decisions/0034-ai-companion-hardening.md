# ADR 0034 — AI companion 加固

> 状态：Accepted

## 决策

1. **单一偏好存储**：把 `AiExplainPrefsStore`（及已存解释）注册为 `setupLocator` 里的 GetIt 单例，经 `AiExplainPrefsStore.resolve` 解析；生产路径上不再有静默的孤儿存储。
2. **只经引擎做 I/O**：companion provider 只调 `AiEngine`；绝不直接调 `ai_prompt_builder` 或课程 section 的 JSON schema。
3. **错误**：所有面向用户的 companion 错误都经 `AiErrorMapper` 出口。
4. **限流**：词典增强用本地防抖；诊断保持 ≥60s；提示流可被取代则不设上限（取消前一条）。
5. **缓存**：切换回复语言 / 深度 / 注入配置时清 `AiEngine` 缓存，避免偏好指纹变化被 LRU 命中掩盖。
6. **导出**：进度导出绝不能包含 `ai.engineConfig`（API key）。
## 理由

companion 功能（提示流、自由对话、词典增强、诊断、已存解释、复习卡讲解）在 A–E 增强计划中落地。怀疑性评审发现 `AiExplainPrefsStore` 存在 DI 孤儿、学习者上下文注入不完整，以及残留的原始错误串。
## 影响与边界

- 设置 → 解释偏好一致地作用于所有 companion 界面。
- 测试断言注入关闭、schema 边界与导出键排除。
- 可选的使用计数仍在 backlog。

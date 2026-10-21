# ADR 0056 — 鸿蒙伴生版移除 AI 生成功能（应用商店合规）

> 日期：2026-10-21 ｜ 状态：已接受（实现随同批提交）
>
> 关联：[ADR 0047](./0047-ohos-companion-lite-build.md)（伴生版范围）、
> [ADR 0055](./0055-ai-credential-persistence-ohos.md)（AI 凭据鸿蒙落盘，本决策后鸿蒙侧无消费方）。

## 背景

华为应用市场对鸿蒙包连续两次驳回，三条意见全部指向应用内的 AI 智能练习：

1. AI 功能需配置 API 才能体验，审核方无测试账号可用；
2. 提供合成生成内容服务前未做真实身份信息核验（手机号 / 身份证件）；
3. 缺少《安全评估报告》及其在全国互联网安全服务管理平台的提交凭证。

Turna 的 AI 是 BYOK 模式：无账号体系、无服务端，用户在应用内自填 API key
（`ai_api_config_page.dart`），全部请求直连用户配置的端点。

## 决策

**鸿蒙伴生版不再随包 AI 模块；Android / iOS 行为完全不变。** 走华为驳回意见
自己给出的出口：「若应用内已无相关模块，可在备注栏进行备注说明」。

实现复用伴生版既有的降级机制，不引入新的编译开关：

1. **声明**：`OhosDegradation` 新增 `aiGeneration`（`lib/core/ohos_target.dart`）。
   鸿蒙构建自动全量生效，其他平台自动为空。`test/core/ohos_target_test.dart`
   钉死的集合同步扩容——该测试的存在意义就是让这类范围决策必须在 diff 里显式过审。
2. **数据面**：`AiEngine` 是全应用唯一 LLM 出入口，在 `_callOnceUntraced` 入口
   与 `probeConnection` 对 `isDegraded(aiGeneration)` 短路。任何漏网的调用路径
   最多收到一条错误，不可能真正发请求。
3. **启动**：`app_startup.dart` 跳过 `AiPracticeJobQueue.restoreOnStartup()`，
   避免续跑一个注定失败、只会以「失败任务」形态出现在界面里的生成队列。
   `AiEngineConfigHolder.loadPersisted()` 保留——只读偏好，无副作用。
4. **UI**：入口全部隐藏而非置灰（审核要的是「模块不存在」，一个可见但禁用的
   AI 入口仍会被认定模块存在）：
   - Play Hub「智能练习」磁贴及其长按浮窗（`play_hub_screen.dart`）；
   - 设置 → 高级 → 「AI 连接」入口，及旧版页「实验性能力」整节
     （该节唯一内容是 AI 引擎调参卡，`settings_advanced_section.dart`）；
   - 课时页 AI 提示按钮（`new_lesson_screen.dart` 的 `_aiEligible` 恒 false）；
   - 复习页卡片讲解按钮（`unified_review_page.dart` 传 `onAiExplain: null`）；
   - 词典页 AI 拓展按钮（`dictionary_page.dart`）。

   路由（`AiHubRoute` 等）不单独设守卫：入口全部隐藏后不可达，引擎短路是兜底。

## 备选与否决

- **补测试账号再提审**：只解决问题 1；问题 2（实名核验）与问题 3（安全评估
  报告）依然无解，必然再驳。
- **走合规资质路线**：《安全评估报告》的前置是算法备案等企业级义务，个人
  开发者不可得；问题 2 还要求自建账号 + 短信实名体系，与本地优先、无服务端
  的架构正面冲突。两条都不走。
- **保留模块、置灰入口**：驳回口径是「模块存在即需资质」，置灰不改变定性。

## 影响与边界

- 鸿蒙包里 AI 相关代码仍在二进制中（路由、页面类），但**无任何可达入口、
  无任何出网路径**。若未来要求二进制级剥离，需另立 ADR（tree-shake 或构建
  变体），不在本决策范围。
- ADR 0055 的凭据落盘机制保留：vendored 插件与探针照常工作，只是鸿蒙侧不再
  有功能消费它。Android / iOS 的 AI 功能与凭据行为完全不变。
- 重提审动作（开发者中心，非代码）：「应用审核信息」备注栏说明本版本不含
  AI 生成模块、应用无需账号登录；此前因「无测试账号」被驳的一条随之消解。
- 撤销条件：取得相应资质（企业主体 + 算法备案 + 安全评估报告通过）后，
  从 `OhosDegradation` 移除 `aiGeneration` 并同步还原门禁测试即可，UI 各
  入口的条件包裹无需改动。

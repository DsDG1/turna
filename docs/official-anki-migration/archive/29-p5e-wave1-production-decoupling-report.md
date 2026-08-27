# P5-E Wave 1 生产解耦与架构约束报告

> 文档代号：P5E-WAVE1-REPORT  
> 日期：2026-08-20  
> 前置：[`14`](./14-phase-4-audit-remediation-and-phase-5-execution-plan.md) §8/§10.4、[`15`](./15-p5-legacy-inventory.md)、[`24`](./24-p5-remainder-and-p6-ankiweb-plan.md) §6、[`28`](./28-p5d-remainder-construction-plan.md)  
> 状态：**P5-E Wave 1 HOST CONDITIONAL GO**（断生产引用、隔离 Legacy、无数据删除）

---

## 1. 本次实施内容 (Wave 1)

依据 `14` §8 与 `24` §6 规范，**P5-E Wave 1（断生产引用，不删数据）** 执行了以下工作：

1. **纯字符串与标识符处理下沉**：
   - 在 `lib/application/anki_official/official_anki_ids.dart` 中建立 `LegacyAnkiIdentifiers`，承接 `ankiPrefix`、`importIdFromWordId`、`importIdFromSectionId` 等纯字符串解析逻辑。
   - `AnkiReviewAssembler` 相应静态方法代理至 `LegacyAnkiIdentifiers`，保持兼容性。

2. **生产模块断开对 Legacy Review Assembler 的直接依赖**：
   - `OfficialAnkiHomeDue` (`lib/application/anki_official/engine/official_anki_home_due.dart`) 切至 `LegacyAnkiIdentifiers`，不再 import legacy assembler。
   - `OfficialAnkiProductionRouter` (`lib/application/anki_official/migration/official_anki_production_router.dart`) 切至 `LegacyAnkiIdentifiers`，不再 import legacy assembler。
   - `AnkiOfficialReviewGate` (`lib/views/anki/anki_official_review_gate.dart`) 切至 `LegacyAnkiIdentifiers`，不再 import legacy assembler。
   - `ReviewProgressProvider` (`lib/application/review_progress_provider.dart`) 切至 `LegacyAnkiIdentifiers`，不再 import legacy assembler。

3. **建立 Forbidden Import 架构防护测试（CI 规则）**：
   - 新增 `test/application/anki_official/official_anki_forbidden_imports_test.dart`：
     - 自动化校验 `lib/application/anki_official/`（除必须的 Facade/Adapter/Internal 调试页外）禁止引入任何 `package:turna/application/anki/` 或 `package:turna/views/anki/`。
     - 自动化校验 `lib/` 源码中严禁出现任何 `ankiweb.net`、`AnkiWebSync`、`anki_web_sync` 等已取消的 P6 同步逻辑。
     - 自动化校验核心聚合与路由门禁对 Legacy Review Assembler 的零直接引用。

4. **保持平台策略（方案 B）与数据安全性**：
   - **不删除任何 Legacy 文件**（保持 OHOS 平台 Legacy 回退完整可用）。
   - **不删除任何 SQLite 表或 SharedPreferences 字段**。
   - **不破坏现有单元测试**。

---

## 2. 验证事实与测试指标

```bash
# 1. 架构与禁止导入测试
flutter test --no-pub test/application/anki_official/official_anki_forbidden_imports_test.dart
# 结果: 4/4 passed (0 fail)

# 2. 官方 Core 测试全量回归
flutter test --no-pub test/application/anki_official
# 结果: 265/265 passed (0 fail)

# 3. 遗留 Legacy 模块兼容测试回归
flutter test --no-pub test/anki test/application/anki
# 结果: 151/151 passed (0 fail)
```

---

## 3. 结论与后续波次

* **Wave 1（断生产引用与架构隔离）**：**已收口**。
* **Wave 2 ~ Wave 4（删自研 Scheduler、删 Render/Import 实现、Schema Tombstone）**：**继续保持 HOLD**。必须在 Android 生产版本正式上线且稳定运行一个 Release 周期，并根据 OHOS 平台战略决定后续物理删除计划。

# 36 — 投影课程树顺序与限额修复

> 状态：**已施工（2026-08-28，Host 单测全绿）**。
> 范围：官方 Anki 投影写入课程树的顺序、60/40 限额与重建触发；不改变渲染、调度与 mapping 语义。
> 前置阅读：[30](./30-course-like-card-experience-plan.md) §5（投影与重建）、`docs/content_inventory_current.md`（60/40 设计上限口径）。

## 0. 一句话

修掉三类线上可见的树写入缺陷：Anki 课程与内置课程 sortOrder 撞号导致顺序随机交错（「乱套」）、unit/lesson 按哈希 id 字典序排列等于随机、以及超 60 unit 的 section 写入成功但打开即被 L1 校验拒绝。

## 1. 根因（施工前）

1. `OfficialAnkiCourseProjectionStore.replaceOfficialProjection` 的 section `sort_order` 每个 source 都从 0 起，与内置课程及其它 source 撞号；`sections` 无唯一约束且读取侧只按 `sort_order` 排序,撞号时顺序由 SQLite 扫描序随机决定。
2. `OfficialAnkiProjectionProjector` 按 sectionId/unitId（sha256 前缀）字典序排序，树内 unit 顺序与 Anki 牌组顺序无关；section id `s10` 字典序小于 `s2`。
3. `kMaxUnitsPerSection=60` / `kMaxLessonsPerUnit=40`（course_validator）只在种子/CI 与运行时 L1 打开校验,投影管线写入前零检查。
4. 种子器按内容版本重置时擦投影表但不碰 catalog,`anki_source_projection_state` 的指纹仍让 `projectSource` 走 no-op 短路——投影永久消失且不重建（幽灵消失）。
5. 连带 bug：service 顶层 deck 过滤 `deck.level == 0` 在真实引擎只匹配合成根（真顶层是 level 1），生产 `topDeckIds` 实际为空，section id 全部落到名称哈希兜底。

## 2. 规则（施工后）

### 2.1 树顺序 = 自然名称排序

- 新增 `lib/core/natural_compare.dart`：`naturalCompare` 数字段按数值、字母段大小写不敏感（`Unit 2` < `Unit 10`）,折叠相等回退原始码点保证全序确定。
- projector 排序键:`naturalCompare(sectionName)→sectionId→naturalCompare(unitName)→unitId→naturalCompare(lessonName)→lessonGroup→cardId`。同一 sectionId/unitId 的名称是派生纯函数,聚类保证连续。

### 2.2 60/40 在投影期装箱拆分

- projector 新增 `maxUnitsPerSection`/`maxLessonsPerUnit`（默认取 validator 常量）。
- 顺序：先 `officialAnkiSplitLessons`（JSON 体积拆分会增加 lesson 数）,再 unit 按 40 课拆、后 section 按 60 unit 拆（unit 拆分会增加 unit 数,section 拆分必须在后）。
- 第 2+ 部分实体 id 加 `-xN` 后缀（仍在 `official-anki-<source>-` 命名空间,owned 校验通过）、名称加 ` (Part N)`;未超限实体 id 逐字节不变,placement overrides 不受影响。
- store 写入前防御断言:任一 section unit 数 >60 或 unit lesson 数 >40 抛 `StateError`,事务回滚成 `publish_fault`。

### 2.3 sortOrder 基线与全局紧凑重编号

- 事务开头(删除旧数据前)读本 source 旧 section 的 `MIN(sort_order)` 作基线——重投影保持原位;无旧 section 用 `COALESCE(MAX(sort_order),-1)+1` 追加到最后。
- unit/lesson 计数器改 per-section / per-unit(对齐 `bulkInsertCourseTree` 约定)。
- 事务末尾把全部 sections 按 `(sort_order, id)` 重写为 0..n-1 稠密序列——自愈存量撞号数据。
- `course_repository` 三处读取(`sectionShells`、`section()` 的 units/lessons)全部加 id 决胜键,任何残留撞号下顺序也可复现。

### 2.4 幽灵消失修复

- `_activeFingerprint()` 改为:catalog 指纹存在 **且** course 库 `official_anki_projection_manifest` 有该 source 行才返回,否则视为无先前投影走重建。种子器不动 catalog 是既有设计约束(downgrade 不得伤 catalog),校验放在 service 侧。

### 2.5 存量自愈

- `officialAnkiProjectionAlgorithmVersion` 2→3:进投影指纹但不进树 id,每个存量 source 下次 `projectSource` 必然重投影一次(新顺序+装箱+重编号);洗牌种子同步换版属预期。

## 3. 文件清单

| 文件 | 变更 |
|---|---|
| `lib/core/natural_compare.dart` | 新增,自然排序 |
| `lib/application/anki_official/projection/official_anki_projection_projector.dart` | 语义排序 + 装箱拆分 |
| `lib/application/anki_official/projection/official_anki_projection_store.dart` | 基线 + 重编号 + per-parent 计数 + 限额断言 |
| `lib/application/anki_official/projection/official_anki_projection_service.dart` | manifest 存在性校验 + topDeckIds level 归一 |
| `lib/data/course_repository.dart` | 三处读取 id 决胜键 |
| `lib/application/anki_official/projection/official_anki_projection_paging.dart` | algorithmVersion 3 |
| `test/core/natural_compare_test.dart`、`test/application/anki_official/official_anki_projection_ordering_test.dart` | 新增测试 |

## 4. 验收

- 新增 10 个测试全绿:自然排序、60 拆分(3/3/2)、40 拆分、限额内 id 不变、首发布追加、重投影保位+增长吸收、撞号自愈、超限 publish 回滚、读取决胜键、幽灵重建(断言 section id 用真实 deckId `-s1`)。
- `test/application/anki_official` 全目录 -j1:与干净基线完全一致的 12 个既有环境 flake(临时目录占用/symlink/autoplay),零新增回归;`test/data`、`test/core`、`test/application` 同口径。
- `flutter analyze`:0 新增(仅存量 4 条 unnecessary_const info)。

# Step 3 详细说明：桥补写操作（配置区读写）

> **整个 v2 已失败（2026-09-01）。** 本步当时交付 op 41/42 与契约 1.12，不构成 v2 成功。总结论：[README.md](./README.md)。
> 上游文档：[README.md](./README.md)（六步计划已作废）；前置：[step2.md](./step2.md)。
> Step 3 只做一件事：**给桥补上配置区读写能力（op 41 `GET_CONFIG` / op 42 `SET_CONFIG`），契约升 1.12，契约测试绿**。这是 D2（决策进配置区）的唯一施工前置——Step 4 的映射晋升、课程放置决策全部压在这两个 op 上。
> 原则：只加不改（append-only 纪律继承 doc 39）；不动 v1 任何行为；不加 Step 4 才需要的东西。

---

## 0. 范围围栏（先说清楚不做什么）

| 不做 | 归属 |
|---|---|
| 任何业务调用方改接（映射晋升、课程放置写配置区） | Step 4 |
| usn-diff 只读 op（ADR D2 标「可选」；op 40 现为 stub，K2 receipt 重建的真实需求到 Step 4 强杀测试才能验证，届时若确认不足再占编号） | Step 4+ |
| catalog / course.db schema 任何改动 | Step 5/6 |
| 存量数据迁移 | Step 5 |

Step 3 的产出是：**op 41/42 落码 + 契约 1.12 三处一致（Rust const / Dart const / `contract/VERSION` + golden fixture）+ 桥测试与 Dart 契约完整性测试绿**。

---

## 任务 A：Q1 spike——rslib config API 事实核验（已完成）

回答「配置区长什么样、桥怎么读写它」。以下事实 2026-08-31 按钉住的 rslib 源码（`native/turna_anki_core/anki`，commit `967aa0d5`）核实：

1. **存储形态**：Collection 自带 `config` 表（`key` TEXT 主键、`val` BLOB——恒为 JSON 序列化字节、`mtime`、`usn`），随 collection.anki2 走原生备份/导出——D2「随备份走」零成本成立。
2. **写路径（公开 API，事务性）**：`Collection::set_config_json(key, val, undoable)`——`pub`，内部 `transact()` 单事务（**K10「配置区写 = op 内部单事务，杀进程即回滚」直接由它成立**）；`Collection::remove_config(key)` 同为 `pub` + 单事务。
3. **读路径（无公开 API）**：`get_config_optional` 是 `pub(crate)`，桥不可调。但 `col.storage` 字段是 `pub`，且桥已有四处直接 `col.storage.db()` 跑 SQL 的先例（`query.rs:188/270`、`projection.rs:419/451`、`ops.rs:1098`）——**GET_CONFIG 以只读 SQL 直查 `config` 表**，与既有模式一致。
4. **rslib 读语义先例**：`get_config_optional` 对「missing 或 val 不可解析」一律返回 None（`config/mod.rs:118-119`）——GET_CONFIG 沿用此语义（不可解析按 missing 报，不抛错）。
5. **undoable 取值**：`false`。Turna 决策写不进用户 undo 栈（undo 出来的「半截决策」会把配置区与账本状态打散）；幂等性由「同一写重放结果相同」保证，与 K10 一致。

### op 语义设计（评审已随 ADR 通过）

- **`GET_CONFIG` (41)**：请求 `{ key }`；响应 `{ found, value? }`。key 任意（只读，允许读 Anki 自身 key 供诊断），非空且 ≤128 字节；missing 或不可解析 → `found=false`（无 `value` 字段）。
- **`SET_CONFIG` (42)**：请求 `{ key, value }`；响应 `{ ok, removed }`。
  - **写保护**：key 必须以 `turna.` 前缀开头，否则 `INVALID_ARGUMENT`——Anki 自身配置（`schedVer`、`curDeck` 等）绝不可经 Turna 桥误写，这是 K10 之外的另一道安全门；
  - `value` 为 JSON **object**（决策都是结构化的）且序列化后 ≤256 KiB；缺省或显式 `null` = **删除该 key**（走 `remove_config`），响应 `removed=true`（key 不存在时同样成功，幂等）；
  - 写入走 `set_config_json(key, value, false)`（单事务、不进 undo 栈）；
  - 写/删后 `after_mutation(content=true)`：配置区变化影响投影输入（D3 视图的输入含配置区决策），content generation 必须前进，否则旧投影快照会被误判仍新鲜。

## 任务 B：Rust 落码

- `engine.rs`：`OP_GET_CONFIG = 41`、`OP_SET_CONFIG = 42`（append-only，编号永不复用）。
- `contract.rs`：`CONTRACT_MINOR` 11→12；`OP_TABLE` 尾部追加两行（capabilities 顺序敏感，golden fixture 同步）。
- `ops.rs`：请求结构 + 两个 handler + dispatch 臂；测试覆盖——
  - missing key 读取 → `found=false`；
  - set→get 往返（对象值）；
  - 非 `turna.` 前缀 set → `INVALID_ARGUMENT`（写保护门）；
  - `value=null` 删除 → get 回 `found=false`，再删幂等；
  - Created 态引擎调 SET → `INVALID_STATE`（与 Step 1 的状态机门测试同款）；
  - 关库重开（close→open）后 get 仍能读到——证明写入真的落在 Collection 事务里而非内存；
  - set 后 content generation 前进（投影失效钩子）。
- `contract/fixtures/response_engine_info.json`：capabilities 追加两行、`contractMinor` 改 12（Rust 侧 `capabilities_match_golden_fixture_exactly` 钉死一致性）。

## 任务 C：Dart 契约注册与调用面

- `official_anki_contract.dart`：`kOfficialAnkiContractMinor` 12；`getConfig`/`setConfig` 名称、id 41/42、`productionNames`。
- 调用面按既有 op 全链路模式落：`official_anki_engine.dart`（抽象）→ `official_anki_engine_ffi.dart`（真实现）→ `official_anki_engine_fake.dart`（假引擎，Step 4 严格测试的地基）→ `official_anki_worker.dart` / `official_anki_session_engine.dart`（包装层）。
- 结果模型进 lifecycle models：`OfficialAnkiConfigValue { found, value }`、`OfficialAnkiConfigWriteResult { ok, removed }`。

## 任务 D：契约文档与验收

- `contract/operations.md`：表加 41/42 两行 + 「v1.12 additions」节（语义、`turna.` 前缀纪律、null=删除、rslib 读语义先例）。
- `contract/VERSION` → `1.12`。
- Dart 契约完整性测试（`official_anki_contract_integrity_test.dart`）：ids↔operations.md 对齐、productionNames ⊆ golden caps、caps 数量 39→41、三处版本一致——全部应绿。

---

## 执行顺序

```
A spike（已完成，见收据）
 └→ B Rust 落码 + 测试
      └→ C Dart 契约注册 + 调用面
           └→ D 文档/golden/验收 → 契约测试绿 → Step 3 关闭，进 Step 4
```

## 验收清单

- [x] op 41/42 在 `operations.md`、Rust `OP_TABLE`、Dart `ids` 三处一致（append-only，编号不复用）
- [x] GET_CONFIG：missing/不可解析 → `found=false`（rslib 读语义先例）
- [x] SET_CONFIG：单事务（K10）、`turna.` 前缀写保护、`null`=删除且幂等、重放幂等
- [x] 配置区写后 content generation 前进（D3 投影失效钩子）
- [x] 契约版本四处一致 1.12：Rust `CONTRACT_MINOR` / Dart `kOfficialAnkiContractMinor` / `contract/VERSION` / golden fixture
- [x] `cargo test`（bridge）：新增用例全过，宿主环境存量失败集合不扩大
- [x] `flutter test` 契约完整性套件绿；全套无新增失败

## 工作量估计

| 任务 | 估计 |
|---|---|
| A spike | 0.5 天（已完成） |
| B Rust 落码 + 测试 | 1~2 天 |
| C Dart 调用面 | 0.5~1 天 |
| D 文档与验收 | 0.5 天 |
| **合计** | **2.5~4 天** |

---

## 收据（施工后回填）

| 日期 | 事项 | 结果 | 证据（commit / 测试输出） |
|---|---|---|---|
| 2026-08-31 | 任务 A：Q1 spike | 完成 | 本文件 §任务 A 五条事实 + op 语义设计；源码位置：rslib `config/mod.rs`（set_config_json:85 / remove_config:102 / get_config_optional:109 / 读语义先例:118）、`collection/mod.rs:144`（`pub storage`）；桥内 SQL 先例 `ops.rs:1098` 等。**spike 补充发现**：公开 `remove_config` 硬编码 `Op::UpdateConfig`（undoable），与「决策不进用户 undo 栈」冲突 → 删除改走 `prune_empty_metadata` 同款单语句原子 SQL（`config/undo.rs:40-47`：删缺失 key 本就是无害 no-op，幂等成立） |
| 2026-08-31 | 任务 B：Rust 落码 | 完成 | `engine.rs`（OP 41/42 常量）、`contract.rs`（minor 12 + OP_TABLE 两行）、`ops.rs`（handler + dispatch + 4 个新测试：missing/not-found、roundtrip+前缀门+null 删除幂等、Created 态 INVALID_STATE + close→open 重开可读、content generation 前进）；`ops.rs` 绊线 39/11→41/12。`cargo test -p turna_anki_bridge --lib contract::tests` 11/11 过（含黄金件一致性）；config 用例 4/4 过。全套 72 过/11 失败，其中 2 个（`invalid_and_missing_packages`、`answer_ahead_skips`）经 git stash 干净树复跑证实为宿主存量失败，其余 9 个（import/backup/projection/query/abi）为 Step 1 收据已记录的同批存量。**零新增失败** |
| 2026-08-31 | 任务 C：Dart 调用面 | 完成 | 契约表（names/ids 41/42/productionNames）+ 全链路五处（`official_anki_engine.dart` 抽象、`_ffi`/`_fake`/`_worker`/`_session_engine` 实现）+ `official_anki_session.dart`（`_schedulerWriteOps` 加 `setConfig`、dispatch switch 两个 case）+ models 两个结果类。`flutter analyze`（改动文件）零 issue |
| 2026-08-31 | 任务 D：契约文档与验收 | 完成 | `operations.md`（41/42 行 + v1.12 节）、`contract/VERSION`→1.12、请求/响应黄金件 minor→12 + capabilities 41 项。Dart integrity 测试：caps 39→41、id pin 41/42。契约套件 12/12 绿。`test/application/anki_official/` 全目录：带改动 369 过/14 失败，干净树基线 17 失败 = 同 14 存量 + 3 个「Dart 旧常量 11 vs native 新契约 12」的版本绊线假阳性（stash 只回退 Dart 时绊线立即红，恰好证明一致性守护在工作）——**零新增失败** |

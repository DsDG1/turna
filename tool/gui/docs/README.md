# tool/gui 文档索引

本目录的设计文档与契约。`ai_refactor_contract.md` 是**门禁契约** ——
`make guard-gui` 与两个 CI workflow 的每一条规则和每一个基线数字都在那里有出处，
改代码前先读它。

> 索引手工维护（每篇的一句话用途是编辑性内容，生成器会冲掉它）。
> 增删文档后运行 `python3 tool/gui/tool/check_docs_index.py` 校验没有孤儿文档
> （该脚本已接入 `make guard-gui` 与两个 CI workflow）。
> 同一脚本还校验**指针存活**：正文里反引号包着的 `.md` 文件名与 Markdown 链接
> 都必须能解析到真实文件（基准：提及所在文件 / GUI 工程根 / 仓库根），
> 否则读者会被送到一个打不开的文档。

## 契约（改动前必读）

| 文档 | 作用 | 状态 |
|---|---|---|
| [`ai_refactor_contract.md`](./ai_refactor_contract.md) | AI 层的分层契约 + 门禁指标与基线；`check_ai_boundaries.py` 的全部规则出处 | 在役 |

## 在役设计文档

| 文档 | 作用 | 状态 |
|---|---|---|
| [`experienceai.md`](./experienceai.md) | **Experience AI 上游规范**：感知/决策/执行/解释/记忆五层。下面 4 篇的下游设计都引用它 | 在役（原在 `docs/archive/`，因被持续引用于 2026-09-27 移回） |
| [`a3-companion-ambient-design.md`](./a3-companion-ambient-design.md) | A3 companion 环境感知设计 | 在役 |
| [`e4-m01-attachments-context-design.md`](./e4-m01-attachments-context-design.md) | E4-M01 附件与上下文设计 | 在役 |
| [`e4-m0345-multimodal-design.md`](./e4-m0345-multimodal-design.md) | E4-M03/45 多模态设计 | 在役 |
| [`k08-spiral-vocab-design.md`](./k08-spiral-vocab-design.md) | K08 螺旋词汇设计 | 在役 |
| [`long_term_backlog.md`](./long_term_backlog.md) | 长期改进台账（2026-09-28 修复计划 §4.16 记账：七项有意延后的事项） | 在役 |

## 相关入口

- 模块目录树：[`../README.md`](../README.md) 的「模块目录映射」（由 `gen_module_tree.py` 生成）
- 测试分档与基线：[`../tests/BASELINE.md`](../tests/BASELINE.md)
- 分档运行器：[`../run_gui_tests.py`](../run_gui_tests.py)
- 门禁脚本：[`../tool/check_ai_boundaries.py`](../tool/check_ai_boundaries.py)

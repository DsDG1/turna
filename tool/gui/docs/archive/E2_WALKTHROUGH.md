# E2 退出人工走查清单（Experience OS）

| 字段 | 值 |
|------|-----|
| **配套** | [`experienceai.md`](./experienceai.md) §10.3 / §13 |
| **用途** | 真人勾选；**不**因本文件存在而宣称 E2 ✅ |
| **自动化** | 代码门禁见 `experience_e1_gate_smoke.py`（含 G9–G12） |
| **结果** | ✅ **已通过（2026-07-22）** — H1–H13 人工关闸；`experienceai.md` §2.1 E2 已标 ✅ |

## 环境

- [x] 打开真实 Turkish 课或含空课/校验错的 fixture 课
- [x] 已配置 AI（部分项需要）与一份无 Key 环境（H10）

## 场景

| # | 场景 | 期望 | 勾选 |
|---|------|------|------|
| H1 | 打开半空/有错课 | ≤3s local 仪表；Ambient ≤1（未静音） | ☑ |
| H2 | Ambient 静音今日 → 重启 GUI | 无 Ambient | ☑ |
| H3 | 教师芯片改题 | ≤2 主点击；PreviewHost Enter；Ctrl+Z | ☑ |
| H4 | 空课「AI 填充」T-03 | Diff 确认；Undo 回空壳 | ☑ |
| H5 | 清待补 / 听力 / balance | Diff；无静默写树 | ☑ |
| H6 | Soft 默认关；开后保存可 Undo；Observer 三零 | 符合 | ☑ |
| H7 | 多选课时「批量设置课型」T-04 | 一 Undo 全回 | ☑ |
| H8 | 设置每日 AI 上限=1，连点两次 AI 写 | 第二次 statusBar 拦；手编可保存 | ☑ |
| H9 | JobTray multi + flyout 定位；关课清空 | 符合 | ☑ |
| H10 | 无 API Key 完整手编并保存 | 可 | ☑ |
| H11 | 主观：微观 ≥80% 不进工坊 | 笔记：人工通过 2026-07-22 | ☑ |
| H12 | Dock/Ambient 有重复词时「查重」建议 | 打开资源，**不**自动删 | ☑ |
| H13 | 校验质量 issue 右键「仅修此项」 | 可跑通（需 API） | ☑ |

## 通过标准

全部 H1–H11 勾选后，在 `experienceai.md` §2.1 将 **E2** 标 ✅，并写走查日期。

**状态**：✅ 已满足（2026-07-22）。后续回归可重跑本清单，不必改门禁日期除非失败。

## 不通过时

只改代码缺陷；**不要**为赶进度默认开启 Goal / Soft / dangerous。

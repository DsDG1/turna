# 侵入度阶梯 — 人工走查清单（F6）

| 字段 | 值 |
|------|-----|
| **版本** | 2026-07-25（P0-a/b · P1-a/b/c 后） |
| **前置** | GUI 可启动；可选配置 AI API（外部配置文件见设置 → AI 配置） |
| **相关** | `docs/intrusiveness-no-effect-root-cause-and-fix.md` |

### 已知限制（避免假失败）

- **H3**：课内须有**空课**或 Soft 可修项；AI job 进行中心跳不计时。  
- **副光标**：默认关；不作为侵入感验收项。  

完成后在下方 `[ ]` 打勾。失败请记档位 / 步骤 / 现象。

---

## H3 — Immersive 静默驱动（F3）

1. 体验模式 → **Immersive**（可勾全权 auto / opaque）。  
2. 打开含**空课**或触发 Soft 卫生的课程。  
3. 保持主窗活跃，等待 Ambient 心跳（约 8s）或触发上下文刷新。  

| 期望 | 通过 |
|------|------|
| 无需点 Ambient banner 即可执行白名单 skill（填空课 / Soft） | `[ ]` |
| opaque 时 banner 可空，status 偶发 `…` 或 audit | `[ ]` |
| Ctrl+Z 可撤销自动改动 | `[ ]` |
| 同一建议不会每 8s 狂刷（会话节流）；换课可再跑 | `[ ]` |

---

## H5 — 降档与安全阀

1. Immersive/Sovereign 下 Ctrl+Shift+D → Copilot。  
2. Sovereign 进入后立即降档（观察 300s 冷却是否提示）。  

| 期望 | 通过 |
|------|------|
| 降档后 auto token / 静默驱动停止 | `[ ]` |
| 副光标关闭 | `[ ]` |
| 出站 publish / git.push 永不静默 | `[ ]` |

---

## 自动化对照

```bash
# 在 tool/gui 下
python -m unittest tests.test_presence_drive tests.test_direct_commit_and_regret tests.test_immersive_p3p6 -q
```

---

*走查完成日期：________  执行人：________*

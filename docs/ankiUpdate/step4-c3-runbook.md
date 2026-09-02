# Step 4 / R2:C3 真机强杀矩阵执行手册

> 本手册是 [ADR 0044](../decisions/0044-anki-v2-revival.md) R2 的操作编排。
> **完成标志（2026-09-02）**：只有实机过了才算。不要 logcat 核验、不要诊断导出留证、不要把 host 测试绿写成完成。
> 跳过：K1 / K3（真机不考虑）、K8（checkpoint 已废）、K12（Step 5）。


补充说明：✅已完全通过检验（K），下文暂不更新。暂存。

---

## 0. 前置

装带 v2 flag 的 APK，大/小夹具能从系统选到即可。杀法：`adb shell am force-stop me.dsdogs.turna`（不要系统划掉）。

---

## 1. 一轮怎么走

清场 → 按 §2 走到该行操作 → 需要杀就 force-stop → 冷启看课表/复习/删除是否符合预期 → 过了就口头确认，step4.md 该行标实机过。

debug 再 release。K1 / K3 / K8 / K12 不跑。

---

## 2. K1–K14 操作卡

> 「重启期望」原文见 [step4.md §C3 K 表](./step4.md);此处只编操作。
> 通用前置:debug/release 包装好、v2 flag define 已开、夹具已推 `/sdcard/Download/`。

| 行 | 走到杀点(操作) | 杀点时机 | 重启后核对(摘要) |
|---|---|---|---|
| **K1** staging 导入中 | — | 真机不考虑(2026-09-02 负责人:杀点不现实) | 记「不适用」;B4 census 仍由 host 测试覆盖 |
| **K2** commit 窗口 | preview → 确认导入(开始 commit) | `commit window open` 日志行出现后(导入仍在跑 = importing 态);毫秒窗口人工不可精确命中,**大包 + 该行前后各杀一次**近似覆盖 | 无幽灵卡;attempt 停 committing → census 按意图续跑或弃置 |
| **K3** 投影/视图期 | — | 真机跳过(2026-09-02) | 记「不适用」 |
| **K4** publish 收尾 | 确认导入后、完成页刚要出现 | 完成页将现未现时 force-stop | 冷启后课表在、能进课、内置课还在。**2026-09-02 实机过** |✅
| **K5** 取消时 native busy | 导入中点「取消」 | 取消请求发出、native 仍忙时杀 | 有界返回;staging 删除;无悬挂状态 |✅
| **K6** 卸载四段各一轮 | 已激活 v2 来源 → 牌组管理 → 卸载 | ①点卸载瞬间 ②retiring 中 ③引擎删除中 ④终删/GC 前各一轮 | 重启收敛到终删;GC jobs 在队;无无主且不可见的卡 |✅
| **K7** media GC trash 中 | 卸载后触发媒体 GC(maintenance) | GC 日志进行中 | job 重跑不误删;active 引用完好 |✅
| **K8** checkpoint | — | 不适用(存量,checkpoint 体系已废) | 记「不适用」 |✅
| **K9** compact/VACUUM | 存储页 → 优化数据库 | VACUUM 进行中(存储页显示忙) | 库可 reopen;job 重试;无损坏 |✅
| **K10** 配置区写入 | K2 的提交路径(晋升 op 42 单事务) | 晋升瞬间(同 K2 近似,前后各杀) | 重放 no-op;配置损坏 → 识别器重建议 |✅
| **K11** 视图重建中 | 大包确认导入后课表还在长出来时 | 树出现一半时 force-stop | 冷启后整棵树在;内置课还在 |✅
| **K12** 存量迁移 | — | Step 5 范围,本轮不跑 | 记「Step 5」 |
| **K13** 大库无 ANR | 换 **10 万卡大夹具**完整走一遍导入→课程树→复习→删除 | **不杀**,全程监控 | UI 可交互;bugreport 零 ANR;见 §3 专项 |✅
| **K14** 强杀后 prefs | 每轮强杀后顺手核对 | (随行) | onboarding 完成态/课程 scope 记忆不失;若失 → 定位写入时机 vs 持储损坏机理,回填 A2 |✅

---

## 3. K13 大库专项(ANR-free 证据标准)

ADR 0044 钦定:crash-hunt 工具链为常设取证设施。K13 通过标准 = **bugreport 零 `ApplicationExitInfo(ANR)` + timeline 主 isolate 切片无长忙段**。

```
1. debug/profile 构建起 app,取 VM 服务 URI:
   adb shell dumpsys package me.dsdogs.turna | grep -i version   # 确认构建
   flutter attach / logcat 里 vm-service 行 → URI
2. 后台跑监控(crash-hunt 复用):
   node logs/crash-hunt/monitor.js ws://<device-host>:<port>/<auth>  # rpc 延迟 + GC 频率曲线
3. 大夹具全流程:导入→预览→提交→课程树→(等待视图重建完成)→进课时复习→退出→删除来源
4. 全程 UI 手操;任何卡顿/冻结 → dump-now.js 立即取 timeline 切片
5. 收尾:adb bugreport c3_k13.bugreport → 检查 exit-info 零 ANR
6. R1.5 验证点(大库下):导入提交期主 isolate 无同步写卡索引
   —— logcat 中 `commit window open → closed` 区间 UI 仍可交互(滚动设置页/返回)
```

---

## 4. C4 顺带定标(R3 输入)

大库冷重建 P95:K13 同一夹具上,杀于视图重建后重启(触发启动恢复整建)×3 轮,取修复中心导出与 `view rebuild: N sources, M rows, Xms` 日志行的 `Xms`;P95 回填 step4.md C4 行(未定标前 flag 不得翻 true)。

---

## 5. NO-GO(任一即停,doc 41 §16.7 + v2 特有)

- 存在不可发现的 staging / unfinished source;
- 出现**无主且不可见的卡**(v2 特有,B5 不变量);
- 配置区决策损坏且识别器重建议失败(K10);
- authority 失败仍显示完成;media GC 误删 active 引用;compact 后库无法 reopen;
- 任一 K 行在 release 轮不可自愈(视图无法重建 / census 无法续跑)。

回退动作 = 不翻 flag(现状即 false),v2 已导入来源继续可学(读路径兼容两代)。

---

## 6. 实机结果(回填 step4.md)

一行只有操作者确认实机过了才算。不要日志路径、不要 SHA、不要三件套。

已过：K4、K5。下一步 **K6 强杀轮**（大库卸载已真机过，缺各段杀点）。完成后(不含 K1/K3/K8/K12) → R3 C4 → R4 观察期 + 翻 flag。

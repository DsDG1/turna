# Step 4 / R2:C3 真机强杀矩阵执行手册

> 本手册是 [ADR 0044](../decisions/0044-anki-v2-revival.md) R2 的**操作编排**;权威内容以
> [step4.md §C3](./step4.md)(K1–K14 映射表)与
> [doc 41 §16.6/§16.7](../official-anki-migration/41-official-anki-lifecycle-and-storage-remediation-plan.md)(双跑纪律 / NO-GO)
> 为准,冲突时以它们为最终依据。**release 轮结果才计生产门禁**(§16.6)。
> 收据逐行写回 step4.md;缺证据不得推进 R3/R4(ADR 0044 纪律)。

---

## 0. 前置装备(开工前逐项打勾)

| # | 装备 | 状态(2026-09-02) | 校验方式 |
|---|---|---|---|
| P1 | arm64 `.so` 含 op 41/42(契约 1.12) | ✅ 已落 jniLibs(R1 收据) | `verify_symbols.sh` pass;SHA `90f2a1f5…54472e` |
| P2 | v2 flag 投喂面 | ✅ `--dart-define=TURNA_OFFICIAL_ANKI_V2_IMPORT_CHAIN=true` | 无 define 构建恒 false(生产安全);双态测试绿 |
| P3 | debug + release 双 APK(带 P1/P2) | ⚠️ 8-31 双 APK 已过时——F4/F6/F3 修复落码后需重建(命令不变,`--dart-define=TURNA_OFFICIAL_ANKI_V2_IMPORT_CHAIN=true`) | 重建后 APK 内 .so 剥离 SHA 应仍为 `7ec00e26…0ba7cc`(桥未动);Dart 面以新构建为准 |
| P4 | 小夹具(常规包)+ 大夹具(10 万卡级) | ✅ 大件 `test/fixtures/anki_official_c3/generated/10-large-generated-100000.apkg`(notes=100000,SHA `f7c01ed5…e0579`,**三级牌组树 S::U::L = 10 section × 10 unit × 10 课时 × 100 卡**,真机 F3 修复后再生,消灭单课时 10 万卡的 UI 过载假象;可由 gen_fixtures 命令再生——每次再生官方导出分配新 card id,SHA 随之变);小件 = 仓库契约夹具 `test/fixtures/anki_official/packages/` | 推 `/sdcard/Download/`;向导可选中;期望课程树 = 10 section/每 section 10 unit/每 unit 10 课时 |
| P5 | 真机 + USB 调试授权 | ⏳ 用户侧 | `adb devices` 见 serial(不限 vivo,以实际 serial 记录) |
| P6 | 取证工具 | ✅ `logs/crash-hunt/`(monitor.js / stackloop.js / prepare-timeline.js / dump-now.js) | K13 专项用;需 debug/profile 构建 + VM 服务 |

**杀法约定**:统一 `adb shell am force-stop me.dsdogs.turna`(release 亦可用;杀的语义 = 进程即刻消失,未落盘状态全部丢失)。不要用系统 swipe-away(走完整生命周期,不构成强杀)。

**证据三件套(每行都要)**:
1. `adb logcat -d -s flutter OfficialAnkiV2 OfficialAnki > logs/c3/K<n>-<serial>-<build>.log`(杀前起录);
2. 重启核对后 `adb shell dumpsys activity exit-info me.dsdogs.turna` —— **零 `ApplicationExitInfo(reason=ANR)`**(除 K13 观察项);
3. 修复中心「导出诊断」(含文件日志尾 120 条 + storage audit 快照)。

---

## 1. 通用轮次流程(每行 K 的标准回合)

```
① 清场:卸载重装(或设置内清空 v2 来源)→ 冷启 → 确认课程树基线
② 起录:logcat 落文件(见证据三件套)
③ 走 UI 到该行杀点(见 §2 操作卡)
④ 杀:adb shell am force-stop me.dsdogs.turna
⑤ 重启 app,等待启动恢复跑完(修复中心无进行中 job)
⑥ 核对该行「重启期望」(step4.md K 表第三列)
⑦ 取证三件套归档 logs/c3/
⑧ 收据:step4.md 该行标 ✅/❌ + 证据文件名 + serial + 构建
失败(NOGO 征兆)→ 立即停轮,保留现场,回 step4.md 记 ❌ 与现象
```

debug 全表一轮 → release 全表一轮(K8 存量/K12 Step5 两行跳过,记「不适用」)。

---

## 2. K1–K14 操作卡

> 「重启期望」原文见 [step4.md §C3 K 表](./step4.md);此处只编操作。
> 通用前置:debug/release 包装好、v2 flag define 已开、夹具已推 `/sdcard/Download/`。

| 行 | 走到杀点(操作) | 杀点时机 | 重启后核对(摘要) |
|---|---|---|---|
| **K1** staging 导入中 | 向导 → 选小包 → 进入导入(staging) | 导入进度显示中(native 忙) | 修复中心见「待完成导入」;目录完整→preview;损坏→重建 staging |
| **K2** commit 窗口 | preview → 确认导入(开始 commit) | `commit window open` 日志行出现后(导入仍在跑 = importing 态);毫秒窗口人工不可精确命中,**大包 + 该行前后各杀一次**近似覆盖 | 无幽灵卡;attempt 停 committing → census 按意图续跑或弃置 |
| **K3** 投影/视图期 | 同 K2 走到提交完成前 | `commit window open` 后、`view rebuild` 日志前杀 | 启动恢复入队 `v2_view_rebuild`;视图整建、课程树回归 |
| **K4** publish 收尾 | 提交完成瞬间(向导完成页将现未现) | `view rebuild` 日志行后、`commit window closed` 前后 | job/重入收敛;课程树出现;source active |
| **K5** 取消时 native busy | 导入中点「取消」 | 取消请求发出、native 仍忙时杀 | 有界返回;staging 删除;无悬挂状态 |
| **K6** 卸载四段各一轮 | 已激活 v2 来源 → 牌组管理 → 卸载 | ①点卸载瞬间 ②retiring 中 ③引擎删除中 ④终删/GC 前各一轮 | 重启收敛到终删;GC jobs 在队;无无主且不可见的卡 |
| **K7** media GC trash 中 | 卸载后触发媒体 GC(maintenance) | GC 日志进行中 | job 重跑不误删;active 引用完好 |
| **K8** checkpoint | — | 不适用(存量,checkpoint 体系已废) | 记「不适用」 |
| **K9** compact/VACUUM | 存储页 → 优化数据库 | VACUUM 进行中(存储页显示忙) | 库可 reopen;job 重试;无损坏 |
| **K10** 配置区写入 | K2 的提交路径(晋升 op 42 单事务) | 晋升瞬间(同 K2 近似,前后各杀) | 重放 no-op;配置损坏 → 识别器重建议 |
| **K11** 视图重建中 | 修复中心/重启后触发视图重建 | `view rebuild` 日志进行中 | 旧视图完整(原子换页);重启整建;内置 Turkish 课程不受影响 |
| **K12** 存量迁移 | — | Step 5 范围,本轮不跑 | 记「Step 5」 |
| **K13** 大库无 ANR | 换 **10 万卡大夹具**完整走一遍导入→课程树→复习→删除 | **不杀**,全程监控 | UI 可交互;bugreport 零 ANR;见 §3 专项 |
| **K14** 强杀后 prefs | 每轮强杀后顺手核对 | (随行) | onboarding 完成态/课程 scope 记忆不失;若失 → 定位写入时机 vs 持储损坏机理,回填 A2 |

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

## 6. 收据表(逐行回填 step4.md §C3)

| 行 | 构建 | serial | 结果 | 证据(logs/c3/…) |
|---|---|---|---|---|
| K1 | debug / release | | | |
| … | | | | |

完成后:step4.md 验收清单「K1–K14 真机矩阵映射表全绿」打勾 → R3 C4 定标收口 → R4 观察期 + 翻 flag。

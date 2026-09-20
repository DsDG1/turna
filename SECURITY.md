# 安全策略

## 支持版本

| 分支 | 支持状态 |
|------|----------|
| master | ✅ |

## 报告漏洞

**请不要通过公开 issue 报告安全漏洞**，请使用私有渠道：

- GitHub：仓库 Settings → Security → Report a vulnerability（私有漏洞报告，推荐）；
- 或通过 gitee / GitHub 私信联系仓库所有者。

报告中请尽量包含：受影响的版本或 commit、复现步骤、影响面评估。收到后会在 7 天内回应。

## 范围

- Flutter App 本体（`lib/`）、官方 Anki FFI 层（`native/turna_anki_core/`）、课程编辑器 GUI（`tool/gui/`）、构建与 CI 脚本（`tool/*.py`、`.github/workflows/`）。
- 第三方依赖自身的漏洞请同时报告上游，我们这边会跟进升级。

## 本地优先安全姿态（背景）

Turna 没有云端后端，也没有账号体系，学习数据全部落在本机 SQLite。AI 功能的配置（含 API key）只保存在本机设备上，仅在与你自己配置的 LLM 供应商通信时使用。报告时附带的日志 / 截图请先脱敏（API key、本地路径中的个人信息）。

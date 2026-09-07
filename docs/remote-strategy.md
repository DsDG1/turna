# 远端仓库策略：以 GitHub 为主要目标与参考

## 结论

本项目以 **GitHub** 上的仓库作为主要目标（primary remote）与参考基准（reference upstream）。
当前本地配置的 `origin` 指向 Gitee（`gitee.com:dhwdwf3/Varnamalaplus`），仅作为镜像/备用远端使用。

## 约定

1. **基准分支**：`master`。所有对比、同步与 PR 均以 GitHub 上的 `master` 为准。
2. **同步方向**：GitHub `master` → 本地 `master` →（可选）推送至 Gitee。不要以 Gitee 为源头合并代码。
3. **提交校验**：核对某个提交哈希（例如 `46fe543d`）时，应先在 GitHub 远端上 `fetch` 并查询；
   若 Gitee 上不存在该提交，不代表它不存在——先查 GitHub。
4. **发布与协作**：Issue、PR、Release、CI 均以 GitHub 仓库为准；Gitee 仅作为国内访问的镜像。

## 操作备忘

```bash
# 添加 GitHub 远端（如果尚未添加，URL 以实际仓库地址为准）
git remote add github git@github.com:<owner>/Varnamalaplus.git

# 日常从 GitHub 拉取最新
git fetch github
git merge --ff-only github/master

# 推送时同步两边
git push github master
git push origin master   # Gitee 镜像
```

## 当前状态备注（2026-09-07）

- 本地 `origin` → Gitee，`github` → https://github.com/DsDG1/turna.git。
- 2026-09-07 已从 GitHub fast-forward 至 `46fe543d`（数据库医生诊断修复中心 + P0-P2 测试治理）。
- 子模块 `native/turna_anki_core/anki` 存在本地未提交改动，同步前需先处理。

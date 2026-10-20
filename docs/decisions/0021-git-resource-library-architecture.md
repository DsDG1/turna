# ADR 0021 — Git Resource Library Architecture

> 状态：Accepted ｜ 日期：2026-07-20
## 决策

1. **Saved remotes catalog**（`git_remote_catalog.py`）：轻量 `SavedRemote` dataclass（name, url, local_dir, lang, last_synced_at），以 JSON 存在 QSettings。CRUD：`add_remote`、`remove_remote`、`update_remote`、`find_by_url`、`mark_synced`。与 `Settings.recent_repos` 区分——后者记录打开过的课程目录，不是 git remote 定义。
2. **Settings integration**（`settings.py`）：新增字段 `git_clone_root`、`git_bin`、`default_lang_code`、`lan_default_port`、`lan_bind_address`、`lan_token`、`git_timeout`、`assets_repo_root`，全部持久化在 QSettings 的 `git/*` 键下并带钳制（端口 1-65535，超时 5-600s）。
3. **Settings dialog「Git 库」tab**（`settings_dialog.py`）：第 7 个 tab，含基础配置（clone root、git bin、默认语言、超时、assets root）、LAN 默认值（端口、bind address、token）、SSH key 路径、已存 remote 表（CRUD）与 HTTPS 凭据管理。
4. **GitLibrary 配置注入**（`git_library.py`）：`GitLibrary.__init__` 现在接受 `git_bin`、`timeout`、`token`、`ssh_key_path`；HTTPS 经 `http.extraheader=Authorization: Bearer <token>` 注入鉴权，SSH 经 `GIT_SSH_COMMAND` 环境变量。
5. **Dialog 自动填充**：`GitLibraryDialog` 接受 `settings` 参数，从 Settings 自动填入 URL / 目录 / 语言码，连接成功后回写已存 remotes。
## 理由

`tool/gui` 编辑器原有 `GitLibraryDialog` 一次只支持一个 git remote，没有持久化设置、没有 saved remote 目录、也没有 git 二进制路径 / clone root / 超时的配置项；URL、本地目录与语言码每次会话都得重填，「资源库」因此只是一个单连接工具，而不是一套具名 remote 的真正资源库。

另外，`docs/decisions/` 当时还不存在——尽管 `CLAUDE.md`（已删）已经引用 ADR 0001–0020。本 ADR 既确立该目录，也记录 git 资源库的架构。
## 影响与边界

- 用户不必每次会话重填 remote URL；「资源库」下拉可以列出 saved remotes 供一键访问。
- git 二进制路径与超时可配置，支持非标准 git 安装。
- `assets_repo_root` 可配置，与原先写死的 `parents[4]` 解析解耦。
- `docs/decisions/` 目录就此确立，供后续 ADR 使用。

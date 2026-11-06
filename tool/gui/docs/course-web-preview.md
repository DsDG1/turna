# 课程网页预览、目录与反馈修订

本文是作者侧网页预览的操作与部署契约。决策理由见根目录 `docs/decisions/0069-course-draft-web-preview.md`。

## 1. 作者工作流

### 已有课程与生成后的整门发布 hook

课程目录包含 `index.json` 及其引用的 section JSON 时，可直接发布，不需要先导入 App：

```bash
python tool/course_preview.py publish-course assets/courses/nouveau-turkish
```

命令默认用课程目录名作为稳定 course id，从同级 `manifest.json` 读取显示标题；其他课程可用 `--course-id` 和 `--title` 覆盖。输出 JSON 包含课程 `url`、每节地址及发布状态。生成或人工保存课程文件后可重复调用同一命令；它不会自动导入课程，也不会在模型生成完成时静默上传。

加载器会把课程级 `vocab.json` 补入 section 预览副本，保证 `showWord` 能显示词条。`units: []` 的章节在课程目录中显示「待施工」，不创建空页面，也不阻断其他章节。非空坏数据、重复章节 id、id 不一致和越出课程目录的文件引用会在任何远端写入前报错。

课程地址为 `https://turnalangua.xyz/course-preview/c/<course_id>/`。网站根目录 `/course-preview/` 只列出明确发布的整门课程，不列出零散私密草稿。再次发布会复用各节随机链接；内容不变的章节不增加修订。从索引移除章节只会把它从课程目录撤下，旧预览与反馈仍保留。

### 工坊单节草稿

1. 在工坊生成或恢复草稿，进入「导入」阶段的结构大纲。
2. 点「网页预览 / 反馈」→「发布 / 更新预览」。SSH 默认使用本机别名 `turna`。
3. 「打开」或「复制」链接，交给审阅者。目录页看课时，课时页看题干、选项、折叠答案，并提交整节或逐题留言。
4. 点「拉取反馈」，勾选留言 →「AI 根据反馈修订并重新发布」。
5. 在预览窗口检查留言选择并补充指令，再于现有 diff 页确认。确认后先保存草稿，再更新同一 URL；发布成功的留言才会从未处理列表结案。

发布或修订不会触发「导入到课程」。需要正式入库时仍走原导入、校验和合并预览。

### 整门课程规划中的单节草稿

「整门课程规划」选中已有草稿的章节，点「网页预览 / 反馈」。预览 id、当前发布修订和反馈处理状态保存在该章节的 `progress.web_preview`；工坊对应状态保存在项目 `design.web_preview`。重开项目后继续使用同一链接。

当前草稿与已发布 hash 不同会显示“有未发布修改”。反馈绑定修订与题目快照；旧修订留言不会自动丢弃。若要把已导入并保存的整门课程一起发布，再执行上面的 `publish-course` hook。

## 2. 命令行

在仓库根目录执行：

```bash
# 整门课程：新建或按 course id 更新，重复执行保持链接稳定
python tool/course_preview.py publish-course path/to/course-directory

# 单份 section JSON：新建预览；输出中的 preview_id 和 url 要保留
python tool/course_preview.py publish path/to/section.json

# 更新同一个单节链接
python tool/course_preview.py publish path/to/section.json --preview-id <preview_id>

# 拉取某节全部留言；可加 --output feedback.json
python tool/course_preview.py feedback --preview-id <preview_id>

# 非默认 SSH 别名；publish-course 同样支持
python tool/course_preview.py publish path/to/section.json --ssh-target <alias>
```

客户端用 SSH stdin 传输 JSON；整门课程只需一次 SSH 调用。服务器以 `turna-preview` 用户执行存储命令。网页没有公开上传、改课或 AI 接口。

本机调试服务：

```bash
python tool/course_preview.py serve --root tool/var/course_preview --port 8765
```

此时用服务端 CLI 或测试直接写本地存储；正式作者流仍推荐 VPS。

## 3. 页面与安全边界

- 整门课程 URL 形如 `/course-preview/c/<course_id>/`，章节仍为 `/course-preview/p/<随机 id>/`。课程目录不是身份认证；只发布可公开审阅的非敏感课程。
- 只有 `publish-course` 明确发布的课程会进入网站目录。单节 `publish` 的随机链接仍不可从目录枚举；知道链接即可看题和留言。
- 页面是静态粗预览，不做 App 判分、音频/图片资源上传或原卡 JS 执行。未知题型和坏答案以占位显示，草稿 HTML 只转义展示。
- 可读草稿即使有课程校验警告也可发布；AI 修订和正式导入仍分别经过现有校验。
- 反馈最长 4000 字、可选称呼最长 80 字；有请求大小、频率与蜜罐限制。页面禁缓存、禁嵌入、禁索引，CSP 禁止脚本。
- VPS 不保存 AI key、SSH 私钥、教材源文件或学习者数据库。

## 4. 部署与升级

前置：本机 `ssh turna` 可用，远端现有 Caddy 托管 `turnalangua.xyz`。执行：

```bash
python tool/gui/tool/deploy_course_preview.py
```

脚本只打包 `src.backend.course_preview` 及空包初始化文件，经纯 SSH stdin 编码传输，无 scp/rsync/Docker/Python 第三方依赖，也避免 Windows 本地路径被 scp 误解析。重复执行会产生新释放目录并原子切换 `current`。

远端位置：

| 位置 | 用途 |
|---|---|
| `/opt/turna-course-preview/releases/` | 版本化代码，root 只读 |
| `/opt/turna-course-preview/current` | 当前释放目录软链 |
| `/var/lib/turna-course-preview/<preview_id>/` | 单节 `meta.json`、`revisions/`、`feedback.jsonl` |
| `/var/lib/turna-course-preview/courses/<course_id>.json` | 课程目录及稳定的章节预览映射 |
| `/etc/systemd/system/turna-course-preview.service` | 仅监听 `127.0.0.1:8765` 的 systemd 服务 |
| `/etc/caddy/backups/turna-course-preview/` | 每次部署的 Caddyfile 与旧 unit 备份 |

Caddy 使用 `handle_path /course-preview/*` 反代；现有静态首页由兜底 `handle` 保留。候选配置先经 `caddy fmt` / `caddy validate`，随后检查本机服务、公网健康端点和原首页；任一步失败恢复配置与旧服务。

日常检查：

```bash
ssh turna systemctl status turna-course-preview.service --no-pager
ssh turna journalctl -u turna-course-preview.service -n 100 --no-pager
ssh turna curl -fsS http://127.0.0.1:8765/healthz
curl -fsS https://turnalangua.xyz/course-preview/healthz
```

需要回退时，从 `/etc/caddy/backups/turna-course-preview/<release>/` 恢复对应 Caddyfile 和 unit，`systemctl daemon-reload` 后重启预览服务并 reload Caddy；代码软链切回上一释放目录。恢复操作会影响当前预览，执行前确认所选备份代次。

## 5. 数据与恢复语义

- `revisions/<n>.json` 不可变，当前指针在 `meta.json`；相同 section hash 重复发布不递增。
- 发布先写完整修订，再原子更新指针；反馈以 JSONL 追加并 flush/fsync。
- 课程清单原子写入，保存章节顺序、显示元数据、预览 id 与当前修订。全部章节先通过可读性预检；若远端发生磁盘等 I/O 失败，重跑 hook 即可恢复。
- `feedback.jsonl` 的每条记录带随机 id、修订、题目路径和快照。新版不删除旧反馈，本地 `handled_feedback_ids` 决定哪些已结案。
- 本地修订已保存但发布失败时，反馈进入待发布状态，不会被误标完成；修复 SSH/服务后再次发布即可。
- 备份整个 `/var/lib/turna-course-preview/` 即可保留课程清单、全部预览和留言。代码可重新部署，不能代替数据备份。

# `.turnapack` 格式契约

外部课程进入 Turna 的唯一运行时格式。LibreLingo YAML 等源格式只在离线工具
（`tool/librelingo_import.py`）里转换；app 只解析本文规定的 JSON（v2 时放在 zip 的 `pack.json` 里）。

施工细节与守卫见仓库外的施工计划（开发工作区 `docs/course-pack-import-plan.md`，不在本仓库内；若与本文冲突，以本文 + 代码为准）。

## v1：纯 JSON

单文件 UTF-8 JSON，扩展名 `.turnapack`（手改包可用 `.json`）。体积 ≤ 20 MB。不含媒体；听力题 `audioAsset` 填 wordId，运行时走 TTS。

```jsonc
{
  "format": "turnapack/1",
  "packVersion": 1,
  "language": {
    "code": "es",
    "displayName": "Spanish",
    "ttsLocale": "es-ES",
    "nativeLabel": "Aprende español",
    "signatureChars": "ñÑáéíóúüÜ¿¡"
  },
  "license": {
    "name": "CC BY-SA 4.0",
    "attribution": "LibreLingo community",
    "link": "https://creativecommons.org/licenses/by-sa/4.0/"
  },
  "files": {
    "index.json": {},
    "vocab.json": {},
    "expressions.json": {},
    "grammar_points.json": {},
    "sections/ll-es-s-1.json": {}
  }
}
```

## v2：zip + `media/`

扩展名仍是 `.turnapack`。压缩体积 ≤ 80 MB，解压后合计 ≤ 200 MB，单文件 ≤ 15 MB。

布局：

```
pack.json          # 与 v1 相同的 JSON 对象，format 为 turnapack/2
media/dog1.jpg
media/hola.mp3
```

课程 JSON 里媒体字段写包内相对路径（`media/dog1.jpg`）。导入时：

1. 校验 zip-slip（`..`、绝对路径、冒号）后解压到 `imported_courses/<code>/media/`。
2. 把已知字段（`audioAsset` / `imageAsset` / `audioAssets` / `imageAssets`）改写成 `turnapack://<code>/dog1.jpg`。
3. 播放与图片走本地文件；卸载只删解压出的 `media/`，保留 `<code>.turnapack` 供恢复时再解压。

允许的扩展名：`.jpg` `.jpeg` `.png` `.webp` `.gif` `.mp3` `.ogg` `.wav` `.m4a` `.aac` `.opus`。

`media/` 只收平铺文件名，不允许嵌套子目录（`media/media/x.jpg`、`media/sub/x.jpg` 一律拒绝）——`turnapack://` 解析按单层剥前缀处理，嵌套路径落盘后永远无法解析。

## 硬规则

- `format` 精确白名单 `turnapack/1` 与 `turnapack/2`；未知值拒绝。
- `language.code` 匹配 `^[a-z]{2,3}$`，不得占用内置 manifest code，不得为 `anki`。
- `files` 键是相对课程根的路径，内容与 `assets/courses/<dir>/` 同构（见 [course-layout.md](./course-layout.md)）。
- `index.json` 的 `language` 必须等于 `language.code`；`vocab.json` 必填。
- 所有 section / unit / lesson / word / expression / grammar id 必须以 `ll-<code>-` 开头。
- 引用了 `media/` 但不是带 `media/` 树的 zip → 拒绝。

## 离线转换

```bash
python tool/librelingo_import.py \
  --course-dir test/fixtures/librelingo/test-1 \
  --code es --display-name Spanish --tts-locale es-ES \
  --out test/fixtures/mini.turnapack --validate
```

有图片/音频时自动写成 v2 zip。额外目录用重复的 `--media-dir`；课程根下的 `images/`、`media/`、`audio/` 默认会扫描。LibreLingo `Images:` 列表按文件名 stem 匹配；同 stem 的音频进 `vocab.audioAsset` 与听力题。无文件时行为与 v1 相同（TTS）。

`--code` 一律来自 CLI，不读取 LibreLingo `IETF BCP 47`（`test-1` 不合正则）。

`Modules` / `Skills` / `New words` 等内容块嵌在头块（`Course:` / `Module:` / `Skill:`）内或与其平级均可——test-1 fixture 用嵌套形态，真实仓库（`LibreLingo-ES-from-EN`，module 名带尾斜杠）用平级形态，两者都支持。真实课程需单独浅克隆到仓库旁并在转换后跑 `course_cli.py validate`（when-present 测试 `test_real_es_course_converts_and_validates_when_present`）。

转换器的几条生成规则（防碰撞 / 达标）：

- 词条/表达 id 由 `slugify(term)` 派生；折叠后丢信息的词（带重音、非拉丁文字）自动加 `-<sha256 前 6 位>` 后缀保证唯一，同词重复转换结果稳定。
- 一个模块内 lesson 数按 30 切成多个 unit（`ll-<code>-u-<m>-<k>`）——运行时校验单 unit 上限 40 课。
- lesson id 取 skill `Id`，撞名时追加序号后缀。
- 选择题选项做确定性乱序，`correctIndex` 不再恒为 0；干扰项排除题干文本本身。
- Mini-dictionary 按 `Language.Name` / `For speakers of.Name` 选目标语桶，多义项逗号合并。
- `Special characters` 自动映射到 `signatureChars`（`--signature-chars` 可覆盖）。

# ADR 0045 — 编辑器把课程交给 App

- 状态：**已接受**（2026-09-29）
- 关联：[ADR 0032](./0032-about-page-tool-gui-content.md)；[ADR 0043](./0043-turnapack-external-courses.md)

## 背景

`tool/gui` 编出来的课停在 JSON 目录里。App 只从两处读课：`assets/courses/manifest.json` 登记的内置目录，以及用户导入的 `.turnapack`。编辑器没有写这两处的入口，所以新课到不了学员侧。

外部包还有一条硬规则：section / unit / lesson / word / expression / grammar 的 id 必须以 `ll-<code>-` 开头，语言代码不得占用内置码，也不得是 `anki`。编辑器里的课时 id 是作者起的短名，直接拿去导入会被拒绝。

导入器还要求包顶层有 `license`，且名称和署名都非空。只放一个空对象过不了导入。

## 决策

1. 发布对话框增加「交给 App」，按课程目录分两扇门。两扇门不改写对方的 id。
2. **仓库内置课。** 目录正好是检出仓库的 `assets/courses/<dir>/` 时，把该语言 upsert 进 `manifest.json`，并在 `pubspec.yaml` 的 `flutter.assets` 里补上尚不存在的三行（课程目录、`sections/`、`media/`）。已有语言只更新描述符字段，不改 `dir`。编辑器正在保存的课时 id 保持原样。写完后提示需要重新构建 App。
3. **外部课 `.turnapack`。** 目录不在该仓库里，或用户指定了导出文件。语言代码不得是 manifest 里的内置码，也不得是 `tr` / `fr` / `anki`。没有 `media/` 且正文不引用 `media/` 时写 v1 JSON；否则写 v2 zip（`pack.json` + `media/`）。包内副本的 id 收成稳定前缀 `ll-<code>-`：已经带这个前缀的不再加第二层；空 id 跳过；两个不同原 id 收成同一个前缀 id 时整包失败。引用字段一起改（`wordId`、`expressionId`、`grammarPointId` 以及先修、关联、例句 id 列表）。`sourceNoteId` 不改。`sections/*.json` 这种文件路径不改，但 index 壳上的 id 和章节正文里的 id 一起改，保证导入时两者仍相等。
4. 课程 index 上与 `displayName` 并列补 `ttsLocale`、`nativeLabel`、`signatureChars` 和 `license`。缺省许可名称是 “All rights reserved”，署名和链接可空。打成外部包时，若署名为空，包顶层用课程显示名占位，因为导入器拒绝空署名。编辑器里的 JSON 仍可保持空署名。App 内置课仍只认 manifest，播种器不读这些新键。
5. ADR 0043 的「不编辑已导入的包」不变。本决策不引入课程树硬锁，也不增加第二套 Anki 导入。

## 后果

- 作者在编辑器里点一次「交给 App」，新课就能进内置清单或变成可导入的包。内置登记之后必须重新构建，已安装的 App 不会自己长出新资产。
- 外部包的 id 与编辑器目录里的 id 不同。同一门课不要一边当内置课、一边再导入成外部包。
- 许可署名为空时，包内署名是显示名，不是法律意见。作者要署真实名字，就在 index 的 `license.attribution` 里填写。

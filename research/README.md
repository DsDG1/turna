# 参考资料（本地归档）

> 这里放课程设计的外部参考资料。**PDF 只存本地、不进 git**（版权与体积原因），
> 本清单进 git——换机器时按下面的命令重新下载即可。
> 用法：新会话想知道课程设计的依据时，先看本页，再决定要不要翻 PDF 原文。

## 清单

| 文件 | 是什么 | 状态 |
|---|---|---|
| `duolingo-path-proficiency-drr-24-04.pdf` | Duolingo 研究报告 DRR-24-04《Duolingo Path Meets Expectations for Proficiency Outcomes》（Jiang, Hopman, Reuveni & Kittredge, 2024-04-26，17 页）。2022 年线性 path 改版后，学完 A2 内容的学习者四项能力（读/听/写/说）标准化测评 + 学习行为与成绩的相关性分析。**课程结构设计的主要参照。** | 已读，要点见下 |
| `turkce-ogretimi-programi-2baski.pdf` | 土耳其 Maarif 基金会《Türkçenin Yabancı Dil Olarak Öğretimi Programı（作为外语的土耳其语教学大纲）》第 2 版，405 页。土方官方对外土耳其语课程框架（含成人课程框架）。 | 暂缓，等课程扩容到需要官方大纲对表时再读 |

## 重新下载

```bash
# Duolingo DRR-24-04（S3 直链）
curl -sL -o research/duolingo-path-proficiency-drr-24-04.pdf \
  "https://duolingo-papers.s3.amazonaws.com/reports/Duolingo_whitepaper_language_read_listen_write_speak_2024.pdf"

# 土耳其教学大纲第 2 版（Maarif 原站 kutuphane.turkiyemaarif.org 在部分网络下
# 直连超时；İstanbul Ticaret Üniversitesi 镜像为同一书完整 405 页版）
curl -sL -A "Mozilla/5.0" -o research/turkce-ogretimi-programi-2baski.pdf \
  "https://ticaret.edu.tr/wp-content/uploads/2025/09/Turkcenin-Yabanci-Dil-Olarak-Ogretimi-Programi.pdf_compressed-1.pdf"
```

## Duolingo 论文里对我们有用的结论（速记）

- **path 三大内容变化**（都和我们已拍板的方向对得上）：
  1. 短叙事（stories）从可选变必修——对应我们的「微型故事」课型；
  2. 专门的复习课进主线保证间隔重复——对应「混合提取练习」+ 复习课算法化；
  3. 三档难度全必修：低难度=新内容+**识别型**题，高难度=同材料+**回忆型产出**题——
     印证「新知识引入（认）→ 混合练习（产出）」的两段式单元结构。
- **交错（interleaving）组织**放大间隔重复——「词间穿插」原则在单元层面的放大版。
- 接受性技能（读/听）始终强于产出性技能（写/说），**说最弱**；约 20% 学习者永久
  关掉说/听练习——「主动表达」课要么做成不可绕过的主线，要么给足激励，别做成可关的。
- 到 A2 末平均约 2900 个 session / 200 小时；**时长与成绩负相关，session 正确率与
  成绩正相关**——练得准比练得多重要：优先把题目质量和通过门槛做高，不追求刷量。
- 正字法透明度直接影响初学者的读/听（西班牙语显著优于法语）——土耳其语正字法
  相当透明，这对我们有利，也支持「拼写题早开」的选择。
- 线性 path 比旧自由树**慢但效果好**——线性必修 + 明确单元目标的设计被验证有效。

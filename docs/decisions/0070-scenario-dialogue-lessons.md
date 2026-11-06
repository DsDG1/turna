# ADR 0070 — 情景对话：场景轮次与既有题型组合

> 状态：已接受 ｜ 日期：2026-11-07
>
> 真源：`lib/domain/course/dialogue_scene.dart`、`lib/views/lesson/components/dialogue_scene_header.dart`、`lib/courses/course_validator.dart`

## 背景

Phase Two 需要「点单、询问、回应」类真实社交任务。若把整段对话写成一个大型 Interaction，会绕过现有逐题进度、判分、错题、撤销和 FSRS 接线；若只把普通选择题换成情景文案，又没有真正的对话推进和角色感。

## 决策

1. 新增 `LessonType.dialogue` 与 `LessonTemplate.dialogue`。`LessonContent.dialogueScene` 保存角色与轮次，`content.stages` 继续保存学习者回应题。
2. 角色轮次写 `text`；学习者轮次写 `interactionId`，二者必须二选一。学习者轮次不另存答案，提交后从 Interaction 的规范正确答案恢复台词。
3. 对话按当前 Interaction 推进。当前学习者答案和未轮到的后续内容都不可见，完整对话弹层也只展示已经进行的轮次。
4. 回应复用选择填空、拼句、翻译、跟读等现有 renderer，不新增判分通道。角色头像、名字和当前说话人同时呈现，状态不只靠颜色。
5. 普通情景对话使用逐句系统 TTS，不引入预生成整段音频；MiniMax / 真人长对话仍属于听力课媒体管线。
6. Dart 与 Python validator 同时检查角色、轮次、引用唯一性、题目顺序和可作答性。首课手工编写；AI 生成不在本决策内。

## 理由

场景和作答分离后，课程作者只需描述「谁说、哪句需要学习者回应」，不需要为对话复制一套练习引擎。答案单一来源也避免了场景文本和题目答案长期漂移。

## 边界

- 当前对话课使用平铺 Stage，不与子课或听力阶段混合。
- 本轮不接入 AI 对话生成，不新增云端语音或音素级评分。
- 角色媒体沿用课程包 / 内置课程既有图片路径，不引入新的运行时图片框架。

/// Ready-to-use scenario presets for the in-app custom course designer.
///
/// Mirrors `tool/gui/src/backend/lesson_presets.py` in spirit: one tap fills
/// recommended template, unit/lesson counts, item density, preferred
/// interaction types, and a concise pedagogical design brief, while leaving
/// every field editable by the learner.
class AiCoursePreset {
  const AiCoursePreset({
    required this.id,
    required this.label,
    required this.subtitle,
    required this.template,
    required this.unitCount,
    required this.lessonsPerUnit,
    required this.itemsPerLesson,
    required this.preferredInteractionTypes,
    required this.designBrief,
  });

  final String id;
  final String label;
  final String subtitle;
  final String template;
  final int unitCount;
  final int lessonsPerUnit;
  final int itemsPerLesson;
  final List<String> preferredInteractionTypes;
  final String designBrief;
}

abstract final class AiCoursePresets {
  static const List<AiCoursePreset> all = [
    AiCoursePreset(
      id: 'starter-scene',
      label: '零基础速成',
      subtitle: '新词导入 + 句型巩固 + 综合测验',
      template: 'mixed',
      unitCount: 2,
      lessonsPerUnit: 3,
      itemsPerLesson: 8,
      preferredInteractionTypes: [
        'showWord',
        'fillBlank',
        'reorderSentence',
        'translateSentence',
      ],
      designBrief: '按「认识新词(intro) → 语境巩固(practice) → 综合测验(mastery)」梯度编排；'
          '生词展示后立刻放入高频日常短句中练习，避免孤立词义单选。',
    ),
    AiCoursePreset(
      id: 'dialogue-immersion',
      label: '情景对话',
      subtitle: '双人对话轮次 + 真实交际回应',
      template: 'dialogue',
      unitCount: 2,
      lessonsPerUnit: 2,
      itemsPerLesson: 8,
      preferredInteractionTypes: [
        'multipleChoice',
        'fillBlank',
        'translateSentence',
      ],
      designBrief: '围绕真实生活场景设计自然双人对话，每课 1 个核心场景，学习者以恰当的'
          '礼貌回应完成交际任务。',
    ),
    AiCoursePreset(
      id: 'reading-intensive',
      label: '短文精读',
      subtitle: '分级短文 + 选择 / 判断 / 简答',
      template: 'reading',
      unitCount: 2,
      lessonsPerUnit: 2,
      itemsPerLesson: 6,
      preferredInteractionTypes: [
        'readingMcq',
        'readingTrueFalse',
        'readingShortAnswer',
      ],
      designBrief: '每课编写一篇情节连贯的分级短文（2–4 段），生词可结合上下文推测，'
          '理解题兼顾细节定位与主旨推断。',
    ),
    AiCoursePreset(
      id: 'grammar-drill',
      label: '语法专项',
      subtitle: '知识导览讲解 + 变格/句式精练',
      template: 'mixed',
      unitCount: 2,
      lessonsPerUnit: 3,
      itemsPerLesson: 10,
      preferredInteractionTypes: [
        'fillBlank',
        'reorderSentence',
        'translateSentence',
        'multiSelect',
      ],
      designBrief: '每单元第 1 课使用 guide 导览清晰拆解语法规则与易混点，后 2 课用 '
          'practice / mastery 做对比辨析与句子产出训练。',
    ),
    AiCoursePreset(
      id: 'exam-sprint',
      label: '强化刷题',
      subtitle: '高密度综合产出与易错辨析',
      template: 'mastery',
      unitCount: 3,
      lessonsPerUnit: 3,
      itemsPerLesson: 15,
      preferredInteractionTypes: [
        'multipleChoice',
        'multiSelect',
        'fillBlank',
        'translateSentence',
        'reorderSentence',
      ],
      designBrief: '高密度综合测验，强化干扰项区分度，覆盖核心词汇、搭配与典型易错句型。',
    ),
  ];

  static AiCoursePreset? byId(String? id) {
    if (id == null || id.isEmpty) return null;
    for (final preset in all) {
      if (preset.id == id) return preset;
    }
    return null;
  }
}

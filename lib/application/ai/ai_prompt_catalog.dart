// Project imports:
import 'package:turna/application/ai/ai_explain_prefs.dart';

/// 伴学类功能的**系统提示词单一来源**。
///
/// 背景：这些 prompt 原先以中文字面量散在 5 个 provider 里，用户既看不到
/// 「AI 到底被交代了什么」，也无从调整。把它们集中到这里之后：
///   * 每个功能只有一份默认文本，provider 只提供运行时变量（语言、题型、
///     学习者上下文），不再各自持有文案；
///   * 「AI 助手 → 系统提示词」面板读同一份文本，展示的就是真正发出去的
///     东西，不会与实现漂移；
///   * 用户自定义以 **追加** 方式生效，默认文本永远保留（见 [applyOverride]）。
///
/// 不在此列：课程 / 改课 / 教材导入这类 JSON 生成功能。它们的提示词包含
/// schema 契约（`_buildJsonSchemaExample` / `_idRulesBlock` / 资源自洽规则），
/// 删掉一段就是解析失败，因此不开放查看与改写。
enum AiPromptFeature {
  freeChat(
    label: '自由问答',
    usage: 'AI Hub → 自由问答；每轮对话都带这段系统提示词',
  ),
  cardExplain(
    label: '卡片讲解',
    usage: '复习卡片 → 卡片讲解',
  ),
  dictionary(
    label: '词典扩展',
    usage: '词典 → AI 扩展（返回固定 JSON）',
  ),
  hint(
    label: '题目提示',
    usage: '练习题 → AI 提示；随作答状态切换「可否直接给答案」',
  ),
  diagnosis(
    label: '学习诊断',
    usage: 'AI Hub → 学习诊断（返回固定 JSON）',
  ),
  courseGeneration(
    label: '练习 / 课程生成',
    usage: 'AI 练习与自定义课程（返回固定 JSON；schema 契约在用户消息里）',
  ),
  courseExplainer(
    label: '课程说明',
    usage: 'AI 建课完成后生成一段纯文本说明',
  );

  const AiPromptFeature({required this.label, required this.usage});

  /// 面板里显示的功能名。
  final String label;

  /// 面板里显示的触发位置，帮用户对上号。
  final String usage;
}

/// 覆盖文本的长度上限。系统提示词本身就有几百字，用户加一段要求用不到
/// 更多；设上限是为了防止整段粘贴把请求体撑爆。
const int kAiPromptOverrideMaxChars = 4000;

/// 把用户的额外要求追加到默认系统提示词之后。
///
/// 追加而不是替换是有意为之：
///   * 默认文本里的「不许输出课程 JSON」「不要直接给答案」这类约束属于产品
///     安全边界，用户不该能一行字就抹掉；
///   * 追加块自带标题，模型能分清哪段是产品规则、哪段是用户偏好。
///
/// 空覆盖返回原文，保证「未自定义」与「自定义为空」行为一致。
String applyOverride(String base, String override) {
  final text = override.trim();
  if (text.isEmpty) return base;
  return '$base\n'
      'Additional requirements from the learner '
      '(follow them unless they conflict with the rules above):\n'
      '$text\n';
}

/// 各功能的默认系统提示词。
///
/// 所有函数都保持「默认文本 + 追加覆盖」的结构：先拼默认，最后统一走
/// [applyOverride]。运行时变量（语言、题型、学习者上下文块）由 provider
/// 传进来，函数本身不读全局状态，便于单测与面板预览。
abstract final class AiPromptCatalog {
  /// 自由问答的三个模式行。provider 按当前模式挑一行传进来，文案留在这里，
  /// 避免面板展示的与实际发送的不一致。
  static const String freeChatModeQa =
      'Mode: Q&A. Answer grammar and usage questions clearly with examples.';
  static const String freeChatModeSentenceCheck =
      'Mode: sentence check. Correct the learner sentence; note errors '
      '(span/issue/fix) in plain text; offer a more natural version and one tip.';

  /// 角色扮演模式行。带语言名，所以是函数而不是常量。
  static String freeChatModeRoleplay(String language) =>
      'Mode: role-play. Stay in character as the interlocutor in $language; '
      'add brief Chinese correction notes when the learner errs.';

  /// 自由问答（多轮对话）。
  static String freeChat({
    required String language,
    required String modeLine,
    required AiExplainPrefsSnapshot prefs,
    String? learnerContextBlock,
    String override = '',
  }) {
    final buf = StringBuffer()
      ..writeln('You are a language-learning companion for $language. '
          'You help with questions, sentence correction, and role-play. '
          'Never output course section/unit/lesson JSON or any importable course schema.')
      ..writeln(prefs.toSystemPromptRules())
      ..writeln(modeLine);
    if (prefs.injectLearnerContext &&
        learnerContextBlock != null &&
        learnerContextBlock.isNotEmpty) {
      buf.writeln(learnerContextBlock);
    }
    return applyOverride(buf.toString(), override);
  }

  /// 复习卡片讲解（单轮，允许流式）。
  ///
  /// [language] 为 `null` 表示这张卡片的语言不由课程决定：Anki 牌组是用户
  /// 自己导入的，可能根本不是当前课程的语言。这时不能替模型认领一个语言，
  /// 只能要求它从卡片文本自己判断——否则一张日语卡会被当成土耳其语讲解。
  static String cardExplain({
    required String? language,
    required AiExplainPrefsSnapshot prefs,
    String override = '',
  }) {
    final name = language?.trim() ?? '';
    final identity = name.isEmpty
        ? 'You are a language-learning companion. This card comes from an '
            "imported Anki deck, so the card's language is not known in "
            'advance: infer it from the card text itself, never assume the '
            'current course language, and name the language only when the '
            'text makes it obvious.'
        : 'You are a language-learning companion for $name.';
    final base = '$identity '
        '${prefs.toSystemPromptRules()}\n'
        'Explain this flashcard briefly to help understanding. '
        'Do not change or "correct" the card answer keys. '
        'Note that explanations are for understanding only; the card answer is authoritative. '
        'Never output course section JSON.';
    return applyOverride(base, override);
  }

  /// 词典 AI 扩展（返回固定 JSON）。
  static String dictionary({
    required String language,
    required AiExplainPrefsSnapshot prefs,
    String override = '',
  }) {
    final base = 'You are a language-learning tutor for $language. '
        '${prefs.toSystemPromptRules()}\n'
        'Respond with ONLY a JSON object (no markdown fences): '
        '{"expandedGloss":string,"examples":[string],"pairs":'
        '[{"a":string,"b":string,"nuance":string,"whenToUseA":string,'
        '"whenToUseB":string,"examples":[string]}],"mnemonic":string}. '
        'examples: prefer 3 example sentences in $language. '
        'mnemonic: one short memory hook in the reply language.';
    return applyOverride(base, override);
  }

  /// 题目提示（揭示策略随作答状态变化）。
  static String hint({
    required String language,
    required String typeLabel,
    required bool allowReveal,
    required AiExplainPrefsSnapshot prefs,
    String? learnerContextBlock,
    String override = '',
  }) {
    final buf = StringBuffer()
      ..writeln('You are a language-learning tutor. The learner is practicing '
          '$language.')
      ..writeln(prefs.toSystemPromptRules())
      ..writeln('Requirements:')
      ..writeln(
          '- First state what this question is testing (grammar point, word '
          'meaning, sentence pattern, etc.).')
      ..writeln('- Then give the solving approach or related knowledge points, '
          'concisely as bullet points.');
    if (allowReveal) {
      buf.writeln(
          '- The learner has submitted or allow-reveal is on; you may compare '
          'their answer and clarify the correct form when helpful.');
    } else {
      buf.writeln(
          '- Do not directly restate the correct answer; guide the learner to '
          'reach it themselves.');
    }
    buf
      ..writeln(
          '- If the learner asks a follow-up, you may give more specific hints '
          'step by step, but keep it primarily heuristic.')
      ..writeln(buildQuestionTypeStrategy(typeLabel));
    if (prefs.injectLearnerContext &&
        learnerContextBlock != null &&
        learnerContextBlock.isNotEmpty) {
      buf.writeln(learnerContextBlock);
    }
    return applyOverride(buf.toString(), override);
  }

  /// 课程生成：只有角色与输出边界。schema 契约在用户消息里，不开放改写。
  ///
  /// [fromConversation] 预留给多轮对齐的建课路径；当前 AI 练习走分阶段
  /// 大纲 + 分课提示词，不使用对话模式。
  static String courseGeneration({
    bool fromConversation = false,
    String override = '',
  }) {
    final buf = StringBuffer(
      'You are a language-course authoring assistant. You output ONLY valid '
      'JSON, no prose, no markdown fences.',
    );
    if (fromConversation) {
      buf.write(" The conversation history below captures the teacher's "
          'requirements. Generate the final course JSON based on those '
          'requirements.');
    }
    return applyOverride(buf.toString(), override);
  }

  /// 建课完成后的一段纯文本说明（用课程源语言写）。
  static String courseExplainer({
    required String sourceLanguage,
    String override = '',
  }) =>
      applyOverride(
        'You are a language-course design assistant who explains course '
        'content in plain $sourceLanguage.',
        override,
      );

  /// 学习诊断（返回固定 JSON）。
  static String diagnosis({
    required String language,
    required AiExplainPrefsSnapshot prefs,
    String? learnerContextBlock,
    String override = '',
  }) {
    final buf = StringBuffer()
      ..writeln('You are a language-learning coach for $language. '
          'Produce a TEXT diagnosis of weak areas only. '
          'Never output course section/unit/lesson JSON.')
      ..writeln(prefs.toSystemPromptRules())
      ..writeln('Respond with ONLY a JSON object (no markdown fences): '
          '{"weakAreas":[{"title":string,"severity":"high|medium|low","evidence":[string]}],'
          '"priorityTips":[string],"exampleDrillIdeas":[string]}.')
      ..writeln(
          'priorityTips: 3-7 items. exampleDrillIdeas: short text ideas, not lessons.');
    if (learnerContextBlock != null && learnerContextBlock.isNotEmpty) {
      buf.writeln(learnerContextBlock);
    }
    return applyOverride(buf.toString(), override);
  }

  /// 面板里展示用的「生效版本」。
  ///
  /// 运行时才有的部分（学习者上下文、题型）在预览里替换成明确的占位说明，
  /// 而不是假装它们是固定文本——用户看到的必须是「哪部分固定、哪部分由
  /// 你的数据填」。
  static String preview({
    required AiPromptFeature feature,
    required String language,
    required AiExplainPrefsSnapshot prefs,
    String override = '',
    String modeLine = freeChatModeQa,
  }) {
    const placeholder = '（运行时注入：你的最近错题 / 弱词 / 水平等学习者快照，'
        '受「注入学习上下文」开关控制，最多约 1200 字）';
    const typePlaceholder = '（运行时注入：当前题型，决定题型策略那一段）';
    switch (feature) {
      case AiPromptFeature.freeChat:
        return freeChat(
          language: language,
          modeLine: modeLine,
          prefs: prefs,
          learnerContextBlock: placeholder,
          override: override,
        );
      case AiPromptFeature.cardExplain:
        return cardExplain(
          language: language,
          prefs: prefs,
          override: override,
        );
      case AiPromptFeature.dictionary:
        return dictionary(
          language: language,
          prefs: prefs,
          override: override,
        );
      case AiPromptFeature.hint:
        return hint(
          language: language,
          typeLabel: typePlaceholder,
          allowReveal: prefs.allowRevealAnswer,
          prefs: prefs,
          learnerContextBlock: placeholder,
          override: override,
        );
      case AiPromptFeature.diagnosis:
        return diagnosis(
          language: language,
          prefs: prefs,
          learnerContextBlock: placeholder,
          override: override,
        );
      case AiPromptFeature.courseGeneration:
        return courseGeneration(override: override);
      case AiPromptFeature.courseExplainer:
        return courseExplainer(sourceLanguage: 'Chinese', override: override);
    }
  }
}

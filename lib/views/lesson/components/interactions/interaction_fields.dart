// Flutter imports:
import 'package:flutter/material.dart';
import 'package:flutter/widget_previews.dart';

// Project imports:
import 'package:turna/core/theme.dart';
import 'package:turna/l10n/app_strings.dart';

/// 作答书写区、提示 chip 与反馈区 —— 题型模板的共享题面件（§7.1 输入族 /
/// §7.2 骨架第 3–4 段）。
///
/// 为什么单独成文件: 这些件被 5 个输入型 renderer 和选择族共用, 放进
/// [interaction_renderer.dart] 会让「分发器 + 基类」文件继续膨胀。

/// 判分三态: 未提交 / 答对 / 答错。
enum InteractionVerdict { pending, correct, wrong }

/// 判分态 → 表面色。五个文本题型曾各自手写同一份
/// 「success 0.10 / error 0.08 / inputFillColor」三元式, alpha 已经漂移过
/// 一次; 收进一处后书写区与句中内联空共用同一口径。
extension InteractionVerdictColors on InteractionVerdict {
  /// 书写区填充色。
  Color fillColor(BuildContext context) => switch (this) {
        InteractionVerdict.pending => TurnaTheme.inputFillColor(context),
        InteractionVerdict.correct =>
          TurnaTheme.success.withValues(alpha: 0.10),
        InteractionVerdict.wrong => TurnaTheme.error.withValues(alpha: 0.08),
      };

  /// 判分后的书写区描边; 未提交时 `null`（交给主题默认）。
  Color? outlineColor() => switch (this) {
        InteractionVerdict.pending => null,
        InteractionVerdict.correct => TurnaTheme.success,
        InteractionVerdict.wrong => TurnaTheme.error,
      };
}

/// 提交态 + 判分结果 → 三态枚举。renderer 里的 `state.submitted` /
/// `state.correct` 直接传进来, 不再各自手写三元式。
InteractionVerdict interactionVerdictOf({
  required bool submitted,
  bool? correct,
}) =>
    !submitted
        ? InteractionVerdict.pending
        : (correct == true
            ? InteractionVerdict.correct
            : InteractionVerdict.wrong);

/// 作答书写区（§7.1「填空 / 翻译 / 拼写 / 听写 / 简答」）。
///
/// 常态是纸面填充 + 聚焦 teal 描边（主题默认）; 提交后整域按判分结果变色
/// 加描边。内部包**真 [TextField]** —— renderer 测试用
/// `find.byType(TextField)` 定位输入框, 换成自绘控件会全部失明。
class InteractionTextField extends StatelessWidget {
  const InteractionTextField({
    super.key,
    required this.controller,
    required this.verdict,
    this.enabled = true,
    this.autofocus = false,
    this.hintText,
    this.onSubmitted,
    this.maxLines = 1,
    this.minLines,
    this.textAlign = TextAlign.start,
    this.largeStyle = false,
  });

  final TextEditingController controller;
  final InteractionVerdict verdict;
  final bool enabled;
  final bool autofocus;
  final String? hintText;
  final ValueChanged<String>? onSubmitted;
  final int? maxLines;
  final int? minLines;
  final TextAlign textAlign;

  /// 拼写 / 听写的大字号档（24/700/0.5 字距）; 默认 18 正文档。
  final bool largeStyle;

  @override
  Widget build(BuildContext context) {
    // 未提交时全部交给主题 inputDecorationTheme（填充 + 聚焦描边）,
    // 只有判分态需要覆写描边 —— 提交后控件禁用, disabledBorder 接住它。
    final outline = verdict.outlineColor();
    InputBorder? judgedBorder;
    if (outline != null) {
      judgedBorder = OutlineInputBorder(
        borderRadius: BorderRadius.circular(TurnaTheme.radiusMedium),
        borderSide: BorderSide(color: outline, width: 1.5),
      );
    }

    return TextField(
      controller: controller,
      enabled: enabled,
      autofocus: autofocus,
      maxLines: maxLines,
      minLines: minLines,
      textAlign: textAlign,
      style: largeStyle ? _heroStyle(context) : _bodyStyle(context),
      decoration: InputDecoration(
        hintText: hintText,
        filled: true,
        fillColor: verdict.fillColor(context),
        border: judgedBorder,
        enabledBorder: judgedBorder,
        disabledBorder: judgedBorder,
      ),
      onSubmitted: onSubmitted,
    );
  }

  TextStyle _heroStyle(BuildContext context) => TextStyle(
        fontSize: 24,
        fontWeight: FontWeight.w700,
        letterSpacing: 0.5,
        color: TurnaTheme.textPrimaryColor(context),
      );

  TextStyle _bodyStyle(BuildContext context) => TextStyle(
        fontSize: 18,
        color: TurnaTheme.textPrimaryColor(context),
      );
}

/// 统一提示 chip: warning 淡底 + 灯泡 + captionSm 文字。
///
/// 收编两份同视觉不同 alpha 的手写实现（fill_blank 的 `_HintChip` 与
/// anki_card 的内联 hint 容器）。[onTap] 非空时是可点档; 水平对齐由调用方
/// 决定（包 `Center` 或放进 `Wrap`）。
class InteractionHintChip extends StatelessWidget {
  const InteractionHintChip({super.key, required this.label, this.onTap});

  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(TurnaTheme.radiusRound);
    final body = Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(
            Icons.lightbulb_outline,
            size: 16,
            color: TurnaTheme.warning,
          ),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              label,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w500,
                color: TurnaTheme.textSecondaryColor(context),
              ),
            ),
          ),
        ],
      ),
    );

    if (onTap == null) {
      return Container(
        decoration: BoxDecoration(
          color: TurnaTheme.warning.withValues(alpha: 0.12),
          borderRadius: radius,
        ),
        child: body,
      );
    }
    return Material(
      color: TurnaTheme.warning.withValues(alpha: 0.12),
      shape: RoundedRectangleBorder(borderRadius: radius),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        borderRadius: radius,
        child: body,
      ),
    );
  }
}

/// 统一作答反馈区（§7.2 骨架第 4 段: 结果、正确表达、简短解释）。
///
/// P0 清点的问题: 反馈只有「选项染色 + 答错横幅」两件套 —— 答对没有文案
/// 层, 横幅插在滚动内容尾部。本组件紧跟作答区出现: 答对一行轻结果, 答错
/// 给「你的答案 → 正确表达」分区对照, 解释段落可选。
///
/// 替换 [LessonCorrectAnswerBanner] 的调用点（后者随迁移批次删除）。
class InteractionFeedbackPanel extends StatelessWidget {
  const InteractionFeedbackPanel({
    super.key,
    required this.correct,
    required this.correctAnswer,
    this.correctAnswerLabel,
    this.userAnswer,
    this.explanation,
  });

  /// 判分结果。`true` 渲染轻量结果行, `false` 渲染醒目对照面板。
  final bool correct;

  /// 学习者提交的答案原文; 输入族与选择族都给（选项文本）。
  final String? userAnswer;

  /// 正确表达。
  final String correctAnswer;

  /// 正确表达的标签; 默认「正确答案」, 翻译题给「正确译文」。
  final String? correctAnswerLabel;

  /// 可选解释段落（语法点说明等）。
  final String? explanation;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      container: true,
      liveRegion: true,
      label: correct
          ? AppStrings.lessonResultCorrect
          : '${AppStrings.lessonResultWrong}，'
              '${AppStrings.lessonYourAnswer} ${userAnswer ?? ''}，'
              '${correctAnswerLabel ?? AppStrings.lessonCorrectAnswer} '
              '$correctAnswer',
      child: correct
          ? Center(child: _buildCorrectRow(context))
          : _buildWrongPanel(context),
    );
  }

  /// 答对: 一行轻结果 —— 黄雀色对钩 + 主文字色短句, 不抢下一题的节奏。
  Widget _buildCorrectRow(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Icon(Icons.check_circle, size: 18, color: TurnaTheme.successDark),
        const SizedBox(width: 8),
        Text(
          AppStrings.lessonResultCorrect,
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: TurnaTheme.textPrimaryColor(context),
          ),
        ),
      ],
    );
  }

  /// 答错: 醒目面板 —— 结果行 + 你的答案 / 正确表达分区。
  Widget _buildWrongPanel(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: TurnaTheme.error.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(TurnaTheme.radiusMedium),
        border: Border.all(color: TurnaTheme.error.withValues(alpha: 0.4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.cancel, size: 18, color: TurnaTheme.error),
              const SizedBox(width: 8),
              Text(
                AppStrings.lessonResultWrong,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: TurnaTheme.textPrimaryColor(context),
                ),
              ),
            ],
          ),
          if (userAnswer != null && userAnswer!.isNotEmpty) ...[
            const SizedBox(height: 8),
            _AnswerZone(
              label: AppStrings.lessonYourAnswer,
              value: userAnswer!,
              emphasized: false,
            ),
          ],
          const SizedBox(height: 8),
          _AnswerZone(
            label: correctAnswerLabel ?? AppStrings.lessonCorrectAnswer,
            value: correctAnswer,
            emphasized: true,
          ),
          if (explanation != null && explanation!.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              explanation!,
              style: TextStyle(
                fontSize: 14,
                height: 1.5,
                color: TurnaTheme.textSecondaryColor(context),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// 反馈面板里的「标签 + 答案」两行区。
class _AnswerZone extends StatelessWidget {
  const _AnswerZone({
    required this.label,
    required this.value,
    required this.emphasized,
  });

  final String label;
  final String value;
  final bool emphasized;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.8,
            color: TurnaTheme.textHintColor(context),
          ),
        ),
        const SizedBox(height: 2),
        Text(
          value,
          style: TextStyle(
            fontSize: emphasized ? 16 : 15,
            fontWeight: emphasized ? FontWeight.w700 : FontWeight.w500,
            height: 1.4,
            color: emphasized
                ? TurnaTheme.textPrimaryColor(context)
                : TurnaTheme.textSecondaryColor(context),
          ),
        ),
      ],
    );
  }
}

// ── Preview ──────────────────────────────────────────────────────────────

@Preview(name: 'Interaction fields · light', group: 'Wetland mist')
@Preview(
    name: 'Interaction fields · dark',
    group: 'Wetland mist',
    brightness: Brightness.dark)
Widget interactionFieldsPreview() => const _InteractionFieldsPreview();

class _InteractionFieldsPreview extends StatelessWidget {
  const _InteractionFieldsPreview();

  @override
  Widget build(BuildContext context) {
    final controllerPending = TextEditingController(text: 'kahv');
    final controllerLocked = TextEditingController(text: 'çay');
    return Scaffold(
      backgroundColor: TurnaTheme.lessonCanvasBg(context),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            InteractionTextField(
              controller: controllerPending,
              verdict: InteractionVerdict.pending,
              hintText: AppStrings.lessonTypeHere,
            ),
            const SizedBox(height: 12),
            InteractionTextField(
              controller: controllerLocked,
              verdict: InteractionVerdict.wrong,
              enabled: false,
              largeStyle: true,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            const InteractionHintChip(label: 'istiyorum = 我要'),
            const SizedBox(height: 16),
            InteractionFeedbackPanel(
              correct: false,
              userAnswer: 'çay istiyorum bir',
              correctAnswer: 'bir çay istiyorum',
            ),
            const SizedBox(height: 12),
            const InteractionFeedbackPanel(
              correct: true,
              correctAnswer: 'bir çay istiyorum',
            ),
          ],
        ),
      ),
    );
  }
}

// Dart imports:
import 'dart:async';

// Flutter imports:
import 'package:flutter/material.dart';

// Project imports:
import 'package:turna/application/audio_controller.dart';
import 'package:turna/core/spacing.dart';
import 'package:turna/core/text_styles.dart';
import 'package:turna/core/theme.dart';
import 'package:turna/core/turna_icon_id.dart';
import 'package:turna/di/injection.dart';
import 'package:turna/domain/course/guide_page.dart';
import 'package:turna/l10n/app_strings.dart';
import 'package:turna/views/widgets/tts_feedback.dart';
import 'package:turna/views/widgets/turna_icon.dart';

class GuideBlockView extends StatelessWidget {
  const GuideBlockView({super.key, required this.block});

  final GuideBlock block;

  @override
  Widget build(BuildContext context) {
    final child = switch (block) {
      GuideTextBlock() => _GuideText(block: block as GuideTextBlock),
      GuideTermsBlock() => _GuideTerms(block: block as GuideTermsBlock),
      GuideClassificationBlock() => _GuideClassification(
        key: ValueKey(block.id),
        block: block as GuideClassificationBlock,
      ),
      GuideSuffixBuilderBlock() => _GuideSuffixBuilder(
        key: ValueKey(block.id),
        block: block as GuideSuffixBuilderBlock,
      ),
      GuideWordOrderBlock() => _GuideWordOrder(
        key: ValueKey(block.id),
        block: block as GuideWordOrderBlock,
      ),
    };
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.lg),
      child: child,
    );
  }
}

Future<void> _speak(BuildContext context, String text) async {
  if (text.trim().isEmpty) return;
  final result = await getIt<AudioController>().speakWithResult(text);
  if (context.mounted) showTtsFailureFeedback(context, result);
}

class _GuideText extends StatelessWidget {
  const _GuideText({required this.block});

  final GuideTextBlock block;

  @override
  Widget build(BuildContext context) {
    return _GuidePanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (block.title case final title?) _GuideBlockTitle(title),
          Text(
            block.body,
            style: AppTextStyles.bodyText(context).copyWith(height: 1.65),
          ),
        ],
      ),
    );
  }
}

class _GuideTerms extends StatelessWidget {
  const _GuideTerms({required this.block});

  final GuideTermsBlock block;

  @override
  Widget build(BuildContext context) {
    return _GuidePanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (block.title case final title?) ...[
            _GuideBlockTitle(title),
            Text(
              AppStrings.guideTapToListen,
              style: AppTextStyles.captionSm(context),
            ),
            const SizedBox(height: AppSpacing.md),
          ],
          if (block.compact)
            Wrap(
              spacing: AppSpacing.sm,
              runSpacing: AppSpacing.sm,
              children: [
                for (final term in block.items)
                  SizedBox(width: 142, child: _GuideTermCard(term: term)),
              ],
            )
          else
            Column(
              children: [
                for (var i = 0; i < block.items.length; i++) ...[
                  if (i > 0) const SizedBox(height: AppSpacing.sm),
                  _GuideTermCard(term: block.items[i]),
                ],
              ],
            ),
        ],
      ),
    );
  }
}

class _GuideTermCard extends StatelessWidget {
  const _GuideTermCard({required this.term});

  final GuideTerm term;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: TurnaTheme.lessonCanvasBg(context),
      shape: RoundedRectangleBorder(
        borderRadius: TurnaTheme.borderRadius,
        side: BorderSide(color: TurnaTheme.dividerBg(context)),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => unawaited(_speak(context, term.speechText ?? term.text)),
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.md),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      term.text,
                      style: AppTextStyles.promptMd(context)
                          .copyWith(color: TurnaTheme.brandTealDark),
                    ),
                  ),
                  TurnaIcon(
                    TurnaIconId.speaker,
                    size: 20,
                    color: TurnaTheme.textSecondaryColor(context),
                  ),
                ],
              ),
              if (term.translation.isNotEmpty) ...[
                const SizedBox(height: AppSpacing.xs),
                Text(term.translation, style: AppTextStyles.bodyText(context)),
              ],
              if (term.note.isNotEmpty) ...[
                const SizedBox(height: AppSpacing.xs),
                Text(term.note, style: AppTextStyles.captionSm(context)),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _GuideClassification extends StatefulWidget {
  const _GuideClassification({super.key, required this.block});

  final GuideClassificationBlock block;

  @override
  State<_GuideClassification> createState() => _GuideClassificationState();
}

class _GuideClassificationState extends State<_GuideClassification> {
  final Map<String, String> _placements = {};
  String? _selectedCardId;
  String? _feedback;
  String? _hintCardId;

  GuideClassificationBlock get block => widget.block;

  void _place(GuideClassificationCard card, String categoryId) {
    setState(() {
      _selectedCardId = null;
      if (card.categoryId == categoryId) {
        _placements[card.id] = categoryId;
        _feedback = null;
        _hintCardId = null;
      } else {
        _feedback = card.hint;
        _hintCardId = card.id;
      }
    });
  }

  void _select(GuideClassificationCard card) {
    setState(() {
      _selectedCardId = _selectedCardId == card.id ? null : card.id;
      _feedback = null;
      _hintCardId = null;
    });
    unawaited(_speak(context, card.text));
  }

  @override
  Widget build(BuildContext context) {
    final unplaced = [
      for (final card in block.cards)
        if (!_placements.containsKey(card.id)) card,
    ];
    final done = unplaced.isEmpty && block.cards.isNotEmpty;
    return _GuidePanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _GuideBlockTitle(block.title),
          if (block.instruction.isNotEmpty)
            Text(block.instruction, style: AppTextStyles.bodyText(context)),
          const SizedBox(height: AppSpacing.xs),
          Text(
            AppStrings.guideClassificationHint,
            style: AppTextStyles.captionSm(context),
          ),
          const SizedBox(height: AppSpacing.md),
          if (unplaced.isNotEmpty)
            Wrap(
              spacing: AppSpacing.sm,
              runSpacing: AppSpacing.sm,
              children: [
                for (final card in unplaced)
                  LongPressDraggable<GuideClassificationCard>(
                    data: card,
                    feedback: Material(
                      color: Colors.transparent,
                      child: SizedBox(
                        width: 150,
                        child: _ClassificationWord(
                          card: card,
                          highlighted: card.id == _hintCardId,
                        ),
                      ),
                    ),
                    childWhenDragging: Opacity(
                      opacity: 0.35,
                      child: _ClassificationWord(card: card),
                    ),
                    child: SizedBox(
                      width: 142,
                      child: _ClassificationWord(
                        card: card,
                        selected: card.id == _selectedCardId,
                        highlighted: card.id == _hintCardId,
                        onTap: () => _select(card),
                      ),
                    ),
                  ),
              ],
            ),
          const SizedBox(height: AppSpacing.md),
          Column(
            children: [
              for (var i = 0; i < block.categories.length; i++) ...[
                if (i > 0) const SizedBox(height: AppSpacing.sm),
                _ClassificationTarget(
                  category: block.categories[i],
                  cards: [
                    for (final card in block.cards)
                      if (_placements[card.id] == block.categories[i].id) card,
                  ],
                  onAccept: (card) => _place(card, block.categories[i].id),
                  onTap: _selectedCardId == null
                      ? null
                      : () {
                          final card = block.cards.firstWhere(
                            (item) => item.id == _selectedCardId,
                          );
                          _place(card, block.categories[i].id);
                        },
                ),
              ],
            ],
          ),
          if (_feedback case final feedback?) ...[
            const SizedBox(height: AppSpacing.md),
            _GuideHint(text: feedback),
          ],
          if (done) ...[
            const SizedBox(height: AppSpacing.md),
            _GuideHint(
              icon: TurnaIconId.checkCircle,
              text: block.completionNote.isEmpty
                  ? AppStrings.guideClassificationDone
                  : '${block.completionNote}\n${AppStrings.guideClassificationDone}',
            ),
          ],
          Align(
            alignment: Alignment.centerRight,
            child: TextButton.icon(
              onPressed: () => setState(() {
                _placements.clear();
                _selectedCardId = null;
                _feedback = null;
                _hintCardId = null;
              }),
              icon: const TurnaIcon(TurnaIconId.restart, size: 18),
              label: Text(AppStrings.guideReset),
            ),
          ),
        ],
      ),
    );
  }
}

class _ClassificationTarget extends StatelessWidget {
  const _ClassificationTarget({
    required this.category,
    required this.cards,
    required this.onAccept,
    this.onTap,
  });

  final GuideClassificationCategory category;
  final List<GuideClassificationCard> cards;
  final ValueChanged<GuideClassificationCard> onAccept;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return DragTarget<GuideClassificationCard>(
      onAcceptWithDetails: (details) => onAccept(details.data),
      builder: (context, candidateData, rejectedData) {
        final highlighted = candidateData.isNotEmpty || onTap != null;
        return Material(
          color: highlighted
              ? TurnaTheme.brandTeal.withValues(alpha: 0.08)
              : TurnaTheme.lessonCanvasBg(context),
          shape: RoundedRectangleBorder(
            borderRadius: TurnaTheme.borderRadius,
            side: BorderSide(
              color: highlighted
                  ? TurnaTheme.brandTeal
                  : TurnaTheme.dividerBg(context),
              width: highlighted ? 1.5 : 1,
            ),
          ),
          child: InkWell(
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.md),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(category.label, style: AppTextStyles.cardTitle(context)),
                  if (category.description.isNotEmpty)
                    Text(
                      category.description,
                      style: AppTextStyles.captionSm(context),
                    ),
                  if (cards.isNotEmpty) ...[
                    const SizedBox(height: AppSpacing.sm),
                    Wrap(
                      spacing: AppSpacing.sm,
                      runSpacing: AppSpacing.sm,
                      children: [
                        for (final card in cards)
                          SizedBox(
                            width: 126,
                            child: _ClassificationWord(
                              card: card,
                              onTap: () =>
                                  unawaited(_speak(context, card.text)),
                            ),
                          ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _ClassificationWord extends StatelessWidget {
  const _ClassificationWord({
    required this.card,
    this.selected = false,
    this.highlighted = false,
    this.onTap,
  });

  final GuideClassificationCard card;
  final bool selected;
  final bool highlighted;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final borderColor = selected || highlighted
        ? TurnaTheme.brandTeal
        : TurnaTheme.dividerBg(context);
    return Material(
      color: TurnaTheme.cardBg(context),
      shape: RoundedRectangleBorder(
        borderRadius: TurnaTheme.borderRadius,
        side: BorderSide(color: borderColor, width: selected ? 2 : 1),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.md,
            vertical: AppSpacing.sm,
          ),
          child: Center(
            child: _HighlightedWord(text: card.text, highlight: card.highlight),
          ),
        ),
      ),
    );
  }
}

class _HighlightedWord extends StatelessWidget {
  const _HighlightedWord({required this.text, required this.highlight});

  final String text;
  final String highlight;

  @override
  Widget build(BuildContext context) {
    final style = AppTextStyles.promptMd(context);
    final index = highlight.isEmpty ? -1 : text.lastIndexOf(highlight);
    if (index < 0) return Text(text, style: style);
    return Text.rich(
      TextSpan(
        children: [
          TextSpan(text: text.substring(0, index)),
          TextSpan(
            text: highlight,
            style: const TextStyle(
              color: TurnaTheme.anatolianClay,
              fontWeight: FontWeight.w800,
            ),
          ),
          TextSpan(text: text.substring(index + highlight.length)),
        ],
      ),
      style: style,
    );
  }
}

class _GuideSuffixBuilder extends StatefulWidget {
  const _GuideSuffixBuilder({super.key, required this.block});

  final GuideSuffixBuilderBlock block;

  @override
  State<_GuideSuffixBuilder> createState() => _GuideSuffixBuilderState();
}

class _GuideSuffixBuilderState extends State<_GuideSuffixBuilder> {
  int _exampleIndex = 0;
  int _stepIndex = 0;

  @override
  Widget build(BuildContext context) {
    if (widget.block.examples.isEmpty) return const SizedBox.shrink();
    final example = widget.block.examples[_exampleIndex];
    final safeStep = _stepIndex.clamp(0, example.steps.length);
    final result = safeStep == 0
        ? example.root
        : example.steps[safeStep - 1].result;
    final meaning = safeStep == 0
        ? example.rootMeaning
        : example.steps[safeStep - 1].meaning;
    return _GuidePanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _GuideBlockTitle(widget.block.title),
          if (widget.block.instruction.isNotEmpty)
            Text(
              widget.block.instruction,
              style: AppTextStyles.bodyText(context),
            ),
          if (widget.block.examples.length > 1) ...[
            const SizedBox(height: AppSpacing.md),
            Wrap(
              spacing: AppSpacing.sm,
              children: [
                for (var i = 0; i < widget.block.examples.length; i++)
                  ChoiceChip(
                    label: Text(
                      widget.block.examples[i].label.isEmpty
                          ? widget.block.examples[i].root
                          : widget.block.examples[i].label,
                    ),
                    selected: i == _exampleIndex,
                    onSelected: (_) => setState(() {
                      _exampleIndex = i;
                      _stepIndex = 0;
                    }),
                  ),
              ],
            ),
          ],
          const SizedBox(height: AppSpacing.lg),
          Wrap(
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: AppSpacing.sm,
            runSpacing: AppSpacing.sm,
            children: [
              _SuffixCarriage(
                label: example.root,
                meaning: example.rootMeaning,
                selected: safeStep == 0,
                onTap: () => setState(() => _stepIndex = 0),
              ),
              for (var i = 0; i < example.steps.length; i++) ...[
                TurnaIcon(
                  TurnaIconId.add,
                  size: 20,
                  color: TurnaTheme.textSecondaryColor(context),
                ),
                _SuffixCarriage(
                  label: example.steps[i].suffix,
                  meaning: example.steps[i].meaning,
                  selected: safeStep == i + 1,
                  onTap: () => setState(() => _stepIndex = i + 1),
                ),
              ],
            ],
          ),
          const SizedBox(height: AppSpacing.lg),
          Material(
            color: TurnaTheme.brandTeal.withValues(alpha: 0.08),
            borderRadius: TurnaTheme.borderRadius,
            child: InkWell(
              onTap: () => unawaited(_speak(context, result)),
              borderRadius: TurnaTheme.borderRadius,
              child: Padding(
                padding: const EdgeInsets.all(AppSpacing.lg),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(result, style: AppTextStyles.pageTitle(context)),
                          const SizedBox(height: AppSpacing.xs),
                          Text(meaning, style: AppTextStyles.bodyText(context)),
                        ],
                      ),
                    ),
                    IconButton(
                      tooltip: AppStrings.guideSuffixListen,
                      onPressed: () => unawaited(_speak(context, result)),
                      icon: const TurnaIcon(TurnaIconId.speaker, size: 22),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SuffixCarriage extends StatelessWidget {
  const _SuffixCarriage({
    required this.label,
    required this.meaning,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final String meaning;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected
          ? TurnaTheme.brandTeal
          : TurnaTheme.lessonCanvasBg(context),
      shape: RoundedRectangleBorder(
        borderRadius: TurnaTheme.borderRadius,
        side: BorderSide(
          color: selected
              ? TurnaTheme.brandTeal
              : TurnaTheme.dividerBg(context),
        ),
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: TurnaTheme.borderRadius,
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.md),
          child: Column(
            children: [
              Text(
                label,
                style: AppTextStyles.promptLg(context).copyWith(
                  color: selected
                      ? TurnaTheme.textOnPrimary
                      : TurnaTheme.textPrimaryColor(context),
                ),
              ),
              Text(
                meaning,
                textAlign: TextAlign.center,
                style: AppTextStyles.captionSm(context).copyWith(
                  color: selected
                      ? TurnaTheme.textOnPrimary
                      : TurnaTheme.textSecondaryColor(context),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _GuideWordOrder extends StatefulWidget {
  const _GuideWordOrder({super.key, required this.block});

  final GuideWordOrderBlock block;

  @override
  State<_GuideWordOrder> createState() => _GuideWordOrderState();
}

class _GuideWordOrderState extends State<_GuideWordOrder> {
  String? _selectedTokenId;
  bool _omitOptional = false;

  @override
  Widget build(BuildContext context) {
    final visibleTokens = [
      for (final token in widget.block.tokens)
        if (!_omitOptional || !token.optional) token,
    ];
    final sentence = visibleTokens.map((token) => token.text).join(' ');
    final selected = widget.block.tokens
        .where((token) => token.id == _selectedTokenId)
        .firstOrNull;
    return _GuidePanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _GuideBlockTitle(widget.block.title),
          if (widget.block.translation.isNotEmpty)
            Text(
              widget.block.translation,
              style: AppTextStyles.bodyText(context),
            ),
          const SizedBox(height: AppSpacing.md),
          Material(
            color: TurnaTheme.brandTeal.withValues(alpha: 0.08),
            borderRadius: TurnaTheme.borderRadius,
            child: InkWell(
              onTap: () => unawaited(_speak(context, sentence)),
              borderRadius: TurnaTheme.borderRadius,
              child: Padding(
                padding: const EdgeInsets.all(AppSpacing.lg),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        sentence,
                        style: AppTextStyles.promptLg(context),
                      ),
                    ),
                    IconButton(
                      tooltip: AppStrings.guideSentenceListen,
                      onPressed: () => unawaited(_speak(context, sentence)),
                      icon: const TurnaIcon(TurnaIconId.speaker, size: 22),
                    ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          Wrap(
            spacing: AppSpacing.sm,
            runSpacing: AppSpacing.sm,
            children: [
              for (final token in visibleTokens)
                ChoiceChip(
                  label: Text(token.text),
                  selected: token.id == _selectedTokenId,
                  onSelected: (_) => setState(() {
                    _selectedTokenId = token.id;
                  }),
                ),
            ],
          ),
          if (selected != null) ...[
            const SizedBox(height: AppSpacing.sm),
            _GuideHint(
              icon: TurnaIconId.tag,
              text: '${selected.role} · ${selected.meaning}',
            ),
          ],
          if (widget.block.tokens.any((token) => token.optional) &&
              widget.block.optionalToggleLabel.isNotEmpty)
            Material(
              color: Colors.transparent,
              child: SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(
                  widget.block.optionalToggleLabel,
                  style: AppTextStyles.bodyText(context),
                ),
                value: _omitOptional,
                onChanged: (value) => setState(() {
                  _omitOptional = value;
                  _selectedTokenId = null;
                }),
              ),
            ),
          if (widget.block.note.isNotEmpty)
            Text(widget.block.note, style: AppTextStyles.captionSm(context)),
        ],
      ),
    );
  }
}

class _GuidePanel extends StatelessWidget {
  const _GuidePanel({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: TurnaTheme.flatPaperDecoration(
        context,
        borderRadius: TurnaTheme.borderRadius,
      ),
      child: child,
    );
  }
}

class _GuideBlockTitle extends StatelessWidget {
  const _GuideBlockTitle(this.title);

  final String title;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: Text(title, style: AppTextStyles.sectionTitle(context)),
    );
  }
}

class _GuideHint extends StatelessWidget {
  const _GuideHint({required this.text, this.icon = TurnaIconId.lightbulb});

  final String text;
  final TurnaIconId icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: TurnaTheme.brandSky.withValues(alpha: 0.09),
        borderRadius: TurnaTheme.borderRadius,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TurnaIcon(icon, size: 20, color: TurnaTheme.brandTeal),
          const SizedBox(width: AppSpacing.sm),
          Expanded(child: Text(text, style: AppTextStyles.bodyText(context))),
        ],
      ),
    );
  }
}

// Flutter imports:
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

// Package imports:
import 'package:provider/provider.dart';

// Project imports:
import 'package:turna/application/ai/ai_error_mapper.dart';
import 'package:turna/application/ai/ai_hint_provider.dart';
import 'package:turna/application/ai/engine/ai_cancel_token.dart';
import 'package:turna/application/ai/engine/ai_engine_config_holder.dart';
import 'package:turna/application/ai/hint_genres.dart';
import 'package:turna/l10n/app_strings.dart';
import 'package:turna/views/ai/components/ai_not_configured_panel.dart';
import 'package:turna/views/ai/components/ai_sheet_widgets.dart';
import 'package:turna/views/theme.dart';

/// The four depth-learning genres offered by the tutor sheet.
enum DepthGenre { grammar, synonyms, decompose, whyWrong }

/// Bottom sheet attached to the in-lesson AI button. Offers four "deep"
/// explanations of the current question - grammar point, synonym nuance,
/// sentence decomposition, and why-was-it-wrong - each a one-shot JSON call
/// through [AiHintProvider] rendered as a structured card.
///
/// Reads the current question from [AiHintProvider.context] and the LLM config
/// from [AiEngineConfigHolder], so it needs no constructor arguments.
class AiDepthTutorSheet extends StatefulWidget {
  const AiDepthTutorSheet({Key? key}) : super(key: key);

  @override
  State<AiDepthTutorSheet> createState() => _AiDepthTutorSheetState();
}

class _AiDepthTutorSheetState extends State<AiDepthTutorSheet> {
  DepthGenre _genre = DepthGenre.decompose;
  final _grammarCtrl = TextEditingController();
  final _synonymCtrl = TextEditingController();
  bool _loading = false;
  String? _error;
  Widget? _result;
  String? _resultCopyText;
  AiCancelToken? _cancelToken;

  AiQuestionContext? get _qctx => context.read<AiHintProvider>().context;

  bool get _needsInput =>
      _genre == DepthGenre.grammar || _genre == DepthGenre.synonyms;

  @override
  void initState() {
    super.initState();
    // Prefill from current question when available (Phase B5).
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final ctx = _qctx;
      if (ctx == null || !mounted) return;
      if (_grammarCtrl.text.isEmpty) {
        _grammarCtrl.text = ''; // AI infers when empty
      }
      if (_synonymCtrl.text.isEmpty &&
          ctx.optionsLabel != null &&
          ctx.optionsLabel!.isNotEmpty) {
        final opts = ctx.optionsLabel!
            .split(RegExp(r'[/|,，]'))
            .map((s) => s.trim())
            .where((s) => s.isNotEmpty)
            .take(4)
            .join(', ');
        if (opts.isNotEmpty) _synonymCtrl.text = opts;
      }
    });
  }

  @override
  void dispose() {
    _cancelToken?.cancel();
    _grammarCtrl.dispose();
    _synonymCtrl.dispose();
    super.dispose();
  }

  void _select(DepthGenre g) {
    if (_genre == g) return;
    _cancelToken?.cancel();
    setState(() {
      _genre = g;
      _error = null;
      _result = null;
      _resultCopyText = null;
      _loading = false;
    });
  }

  Future<void> _generate() async {
    final config = context.read<AiEngineConfigHolder>().config;
    if (!config.isComplete) {
      setState(() {
        _error = AppStrings.aiErrorNotConfigured;
        _result = null;
      });
      return;
    }
    final provider = context.read<AiHintProvider>();
    final ctx = _qctx;
    if (ctx == null) return;

    if (_genre == DepthGenre.whyWrong) {
      final answered = ctx.userAnswer != null && ctx.userAnswer!.isNotEmpty;
      final hasCorrect =
          ctx.correctLabel != null && ctx.correctLabel!.isNotEmpty;
      if (!answered || !hasCorrect) {
        setState(() {
          _error = AppStrings.aiDepthNeedAnswer;
          _result = null;
        });
        return;
      }
    }

    _cancelToken?.cancel();
    final token = AiCancelToken();
    _cancelToken = token;
    setState(() {
      _loading = true;
      _error = null;
      _result = null;
      _resultCopyText = null;
    });

    try {
      switch (_genre) {
        case DepthGenre.grammar:
          final r = await provider.explainGrammarPoint(
            config: config,
            language: ctx.language,
            sentence: ctx.promptLabel,
            grammarPoint: _grammarCtrl.text.trim().isEmpty
                ? ctx.promptLabel
                : _grammarCtrl.text.trim(),
            cancelToken: token,
          );
          _result = _grammarWidget(r);
          _resultCopyText = r.toPlainText();
          break;
        case DepthGenre.synonyms:
          final words = _synonymCtrl.text
              .split(RegExp(r'[,，]'))
              .map((w) => w.trim())
              .where((w) => w.isNotEmpty)
              .toList();
          final r = await provider.compareSynonyms(
            config: config,
            language: ctx.language,
            words: words,
            cancelToken: token,
          );
          _result = _synonymsWidget(r);
          _resultCopyText = r.toPlainText();
          break;
        case DepthGenre.decompose:
          final r = await provider.decomposeSentence(
            config: config,
            language: ctx.language,
            sentence: ctx.promptLabel,
            cancelToken: token,
          );
          _result = _decomposeWidget(r);
          _resultCopyText = r.toPlainText();
          break;
        case DepthGenre.whyWrong:
          final r = await provider.explainWhyWrong(
            config: config,
            language: ctx.language,
            userAnswer: ctx.userAnswer!,
            correctAnswer: ctx.correctLabel!,
            questionContext: ctx.promptLabel,
            cancelToken: token,
          );
          _result = _whyWrongWidget(r);
          _resultCopyText = r.toPlainText();
          break;
      }
    } on AiCancelled {
      // User cancelled - leave the previous state, no error.
      return;
    } catch (e) {
      _error = AiErrorMapper.map(e).message;
    } finally {
      if (identical(_cancelToken, token)) _cancelToken = null;
      if (mounted) setState(() => _loading = false);
    }
  }

  void _copy() {
    if (_resultCopyText == null) return;
    Clipboard.setData(ClipboardData(text: _resultCopyText!));
    ScaffoldMessenger.maybeOf(context)?.showSnackBar(
      SnackBar(content: Text(AppStrings.aiDepthCopied)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final configured =
        context.watch<AiEngineConfigHolder>().config.isComplete;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _header(context),
            const SizedBox(height: 6),
            Text(AppStrings.aiDepthTutorSubtitle,
                style: Theme.of(context).textTheme.bodySmall),
            const SizedBox(height: 12),
            if (!configured)
              const AiNotConfiguredPanel(compact: true)
            else ...[
              AiSurfaceCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _genreGrid(context),
                    if (_needsInput) ...[
                      const SizedBox(height: 12),
                      _inputField(context),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 12),
              _generateButton(context),
              const SizedBox(height: 12),
              Flexible(
                fit: FlexFit.loose,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: 320),
                  child: _resultArea(context),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _header(BuildContext context) {
    return Row(
      children: [
        const Icon(Icons.auto_awesome_rounded,
            color: TurnaTheme.brandTeal, size: 22),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            AppStrings.aiDepthTutorTitle,
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
          ),
        ),
        IconButton(
          tooltip: AppStrings.commonClose,
          icon: const Icon(Icons.close, size: 22),
          onPressed: () => Navigator.of(context).maybePop(),
        ),
      ],
    );
  }

  Widget _genreGrid(BuildContext context) {
    final tiles = <(DepthGenre, String, IconData)>[
      (DepthGenre.grammar, AppStrings.aiDepthGrammar, Icons.menu_book_outlined),
      (
        DepthGenre.synonyms,
        AppStrings.aiDepthSynonyms,
        Icons.compare_arrows_rounded
      ),
      (
        DepthGenre.decompose,
        AppStrings.aiDepthDecompose,
        Icons.account_tree_outlined
      ),
      (
        DepthGenre.whyWrong,
        AppStrings.aiDepthWhyWrong,
        Icons.help_outline_rounded
      ),
    ];
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final t in tiles)
          ChoiceChip(
            label: Text(t.$2),
            avatar: Icon(t.$3, size: 18),
            selected: _genre == t.$1,
            onSelected: (_) => _select(t.$1),
          ),
      ],
    );
  }

  Widget _inputField(BuildContext context) {
    return TextField(
      controller: _genre == DepthGenre.grammar ? _grammarCtrl : _synonymCtrl,
      decoration: aiSheetInputDecoration(
        context,
        label: _genre == DepthGenre.grammar
            ? AppStrings.aiDepthGrammarPointLabel
            : AppStrings.aiDepthSynonymWordsLabel,
      ),
    );
  }

  Widget _generateButton(BuildContext context) {
    return FilledButton.icon(
      style: aiSheetPrimaryButtonStyle(),
      onPressed: _loading ? null : _generate,
      icon: _loading
          ? const SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: Colors.white,
              ),
            )
          : const Icon(Icons.bolt_rounded),
      label: Text(AppStrings.aiDepthGenerate),
    );
  }

  Widget _resultArea(BuildContext context) {
    if (_loading) {
      return const Center(
        child: CircularProgressIndicator(
          color: TurnaTheme.brandTeal,
          strokeWidth: 3,
        ),
      );
    }
    if (_error != null) {
      return AiSurfaceCard(
        accent: TurnaTheme.error,
        child: Text(
          _error!,
          style: const TextStyle(color: TurnaTheme.error),
        ),
      );
    }
    if (_result == null) return const SizedBox.shrink();
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Align(
            alignment: Alignment.centerRight,
            child: TextButton.icon(
              onPressed: _copy,
              icon: const Icon(Icons.copy_outlined, size: 18),
              label: Text(AppStrings.aiDepthCopy),
            ),
          ),
          _result!,
        ],
      ),
    );
  }

  // ─── Result renderers ────────────────────────────────────────────────

  Widget _grammarWidget(GrammarExplanation r) => _card([
        SelectableText(r.explanation,
            style: Theme.of(context).textTheme.bodyMedium),
        if (r.relatedExamples.isNotEmpty) ...[
          const SizedBox(height: 8),
          _sectionLabel(AppStrings.aiDepthRelatedExamples),
          for (final e in r.relatedExamples) _bullet(e),
        ],
        if (r.contrastWith.isNotEmpty) ...[
          const SizedBox(height: 8),
          _sectionLabel(AppStrings.aiDepthContrastWith),
          for (final e in r.contrastWith) _bullet(e),
        ],
      ]);

  Widget _synonymsWidget(SynonymComparison r) => _card([
        for (final p in r.pairs) ...[
          _pairHeader(p.a, p.b),
          const SizedBox(height: 4),
          _labeled(AppStrings.aiDepthNuance, p.nuance),
          _labeled(AppStrings.aiDepthWhenToUseA, p.whenToUseA),
          _labeled(AppStrings.aiDepthWhenToUseB, p.whenToUseB),
          if (p.examples.isNotEmpty)
            for (final e in p.examples) _bullet(e),
          const Divider(height: 24),
        ],
      ]);

  Widget _decomposeWidget(SentenceBreakdown r) => _card([
        for (final t in r.tokens)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 2),
            child: SelectableText(
              '${t.surface}'
              '${t.lemma == null || t.lemma!.isEmpty ? '' : ' (${t.lemma})'}'
              '  —  ${t.gloss}  [${t.role}]',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ),
        const SizedBox(height: 8),
        _labeled(AppStrings.aiDepthStructure, r.structure),
      ]);

  Widget _whyWrongWidget(WhyWrongExplanation r) => _card([
        _labeled(AppStrings.aiDepthWhyWrongLabel, r.whyWrong),
        _labeled(AppStrings.aiDepthProbablyThought, r.whatYouProbablyThought),
        _labeled(AppStrings.aiDepthHowToRemember, r.howToRemember),
      ]);

  Widget _card(List<Widget> children) => AiSurfaceCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: children,
        ),
      );

  Widget _sectionLabel(String text) => Padding(
        padding: const EdgeInsets.only(top: 4, bottom: 2),
        child: Text(
          text,
          style: Theme.of(context).textTheme.labelMedium?.copyWith(
                color: TurnaTheme.brandTeal,
                fontWeight: FontWeight.w600,
              ),
        ),
      );

  Widget _bullet(String text) => Padding(
        padding: const EdgeInsets.only(left: 12, top: 2),
        child: SelectableText('• $text',
            style: Theme.of(context).textTheme.bodyMedium),
      );

  Widget _labeled(String label, String value) => Padding(
        padding: const EdgeInsets.only(top: 4),
        child: RichText(
          text: TextSpan(
            style: Theme.of(context).textTheme.bodyMedium,
            children: [
              TextSpan(
                text: '$label：',
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
              TextSpan(text: value),
            ],
          ),
        ),
      );

  Widget _pairHeader(String a, String b) => Text(
        '$a  vs  $b',
        style: Theme.of(context).textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w700,
              color: TurnaTheme.brandTeal,
            ),
      );

}


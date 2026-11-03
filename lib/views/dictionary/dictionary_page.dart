// Flutter imports:
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

// Package imports:
import 'package:auto_route/annotations.dart';
import 'package:provider/provider.dart';

// Project imports:
import 'package:turna/application/ai/ai_explain_prefs.dart';
import 'package:turna/application/ai/ai_saved_explanations.dart';
import 'package:turna/application/ai/dictionary_ai_provider.dart';
import 'package:turna/application/ai/engine/ai_engine_config_holder.dart';
import 'package:turna/application/ai/hint_genres.dart';
import 'package:turna/application/audio_controller.dart';
import 'package:turna/application/dictionary_search.dart';
import 'package:turna/application/language_provider.dart';
import 'package:turna/application/lesson_link_store.dart';
import 'package:turna/application/smart_speech.dart';
import 'package:turna/core/ohos_target.dart';
import 'package:turna/core/spacing.dart';
import 'package:turna/core/text_styles.dart';
import 'package:turna/core/theme.dart';
import 'package:turna/di/injection.dart';
import 'package:turna/l10n/app_strings.dart';
import 'package:turna/views/ai/components/ai_error_banner.dart';
import 'package:turna/views/ai/components/ai_not_configured_panel.dart';
import 'package:turna/views/widgets/directory_rows.dart';
import 'package:turna/views/widgets/practice_empty_state.dart';
import 'package:turna/views/widgets/search_field.dart';
import 'package:turna/views/widgets/tts_feedback.dart';
import 'package:turna/views/widgets/turna_page_content.dart';
import 'package:turna/views/widgets/turna_snack_bar.dart';

/// 词典 ——「湿地雾光」词条阅读目录（R11）。
///
/// 首屏起点是搜索（[TurnaSearchField]，250ms 防抖内建，页内不再手写
/// Timer）；搜索下方紧跟结果目录：无搜索时展示全部词条目录（与搜索同一
/// 份内存索引，无独立数据源），有搜索时是命中列表。结果行是
/// [DirectoryEntryRow]——「行不是卡」，发丝线分隔；点击进词条正文：
/// 窄屏单栏切换，宽屏（≥ [AppSpacing.formColumnMaxWidth]）结果索引与
/// 词条正文并排两栏。
@RoutePage()
class DictionaryPage extends StatefulWidget {
  const DictionaryPage({super.key});

  @override
  State<DictionaryPage> createState() => _DictionaryPageState();
}

class _DictionaryPageState extends State<DictionaryPage> {
  String _query = '';
  bool _searching = false;
  List<DictionaryHit> _hits = const [];
  DictionaryHit? _selected;

  @override
  void initState() {
    super.initState();
    _hits = listDictionaryEntries();
  }

  /// 每次按键：搜索框尾部转 spinner（「输入中」态由 [TurnaSearchField]
  /// 承担），终值由防抖通道回调。
  void _onSearchTyping(String value) {
    if (!_searching) setState(() => _searching = true);
  }

  void _onSearchCommitted(String value) {
    if (!mounted) return;
    setState(() {
      _query = value;
      _searching = false;
      // 键入即回目录：正在阅读的词条让位给新一轮结果。
      _selected = null;
      _hits = value.trim().isEmpty
          ? listDictionaryEntries()
          : searchDictionary(value);
    });
  }

  Future<void> _speak(DictionaryHit hit) async {
    final audio = getIt<AudioController>();
    final wordId = hit.speakAsWordId;
    final TtsSpeakResult result;
    if (wordId != null && wordId.isNotEmpty) {
      result = await audio.speakWordWithResult(wordId);
    } else {
      final text = hit.speakText ?? hit.title;
      if (text.isEmpty) return;
      // Auto-detect the language so translations are read in their own voice.
      result = await audio.speakWithResult(
        text,
        languageCode: detectSpeakLanguage(text),
      );
    }
    if (mounted) showTtsFailureFeedback(context, result);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: TurnaTheme.scaffoldBg(context),
      appBar: AppBar(
        backgroundColor: TurnaTheme.surfaceColor(context),
        elevation: 0,
        title: Text(
          AppStrings.dictionaryTitle,
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w700,
            color: TurnaTheme.textPrimaryColor(context),
          ),
        ),
        centerTitle: true,
      ),
      body: TurnaPageContent(
        maxWidth: AppSpacing.formColumnMaxWidth,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.pageMargin,
                AppSpacing.sm,
                AppSpacing.pageMargin,
                AppSpacing.md,
              ),
              child: TurnaSearchField(
                hint: AppStrings.dictionarySearchHint,
                searching: _searching,
                onChanged: _onSearchTyping,
                onDebouncedChanged: _onSearchCommitted,
              ),
            ),
            Expanded(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final wide =
                      constraints.maxWidth >= AppSpacing.formColumnMaxWidth;
                  final directory = _EntryDirectory(
                    hits: _hits,
                    browsing: _query.trim().isEmpty,
                    onTap: (hit) => setState(() => _selected = hit),
                  );
                  if (!wide) {
                    final selected = _selected;
                    if (selected != null) {
                      return DictionaryEntryDetail(
                        hit: selected,
                        onSpeak: () => _speak(selected),
                        onBack: () => setState(() => _selected = null),
                      );
                    }
                    return directory;
                  }
                  final selected = _selected;
                  return Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Expanded(flex: 5, child: directory),
                      VerticalDivider(
                        width: 1,
                        thickness: 1,
                        color: TurnaTheme.dividerBg(context),
                      ),
                      Expanded(
                        flex: 6,
                        child: selected == null
                            ? PracticeEmptyState(
                                icon: Icons.menu_book_rounded,
                                accentColor: TurnaTheme.brandSky,
                                title: AppStrings.dictionaryPickPrompt,
                              )
                            : DictionaryEntryDetail(
                                hit: selected,
                                onSpeak: () => _speak(selected),
                              ),
                      ),
                    ],
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 结果目录：词条阅读目录行 + 发丝线分隔；无搜索时带「全部词条」节头。
class _EntryDirectory extends StatelessWidget {
  const _EntryDirectory({
    required this.hits,
    required this.browsing,
    required this.onTap,
  });

  final List<DictionaryHit> hits;

  /// 无搜索时的浏览态：展示全部词条目录并带节头；搜索态直接是命中列表。
  final bool browsing;

  final ValueChanged<DictionaryHit> onTap;

  @override
  Widget build(BuildContext context) {
    if (hits.isEmpty) {
      return PracticeEmptyState(
        icon: browsing ? Icons.menu_book_rounded : Icons.search_off_rounded,
        accentColor: TurnaTheme.brandSky,
        title: browsing
            ? AppStrings.dictionarySearchEmpty
            : AppStrings.dictionaryNoMatches,
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.pageMargin,
        0,
        AppSpacing.pageMargin,
        AppSpacing.xl,
      ),
      itemCount: hits.length + (browsing ? 1 : 0),
      itemBuilder: (context, itemIndex) {
        if (browsing && itemIndex == 0) {
          return Padding(
            padding: const EdgeInsets.only(
              top: AppSpacing.xs,
              bottom: AppSpacing.sm,
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Expanded(
                  child: Text(
                    AppStrings.dictionaryAllEntriesTitle,
                    style: AppTextStyles.sectionTitle(context),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.only(bottom: 2),
                  child: Text(
                    AppStrings.dictionaryAllEntriesCount(hits.length),
                    style: AppTextStyles.captionSm(context),
                  ),
                ),
              ],
            ),
          );
        }
        final index = browsing ? itemIndex - 1 : itemIndex;
        final hit = hits[index];
        return DictionaryHitRow(
          hit: hit,
          onTap: () => onTap(hit),
          showDivider: index < hits.length - 1,
        );
      },
    );
  }
}

/// 阅读目录结果行：词头 + 词性与释义 + 来源/已学元信息，发丝线分隔。
///
/// Public so widget tests can pump the real shipped row.
class DictionaryHitRow extends StatelessWidget {
  const DictionaryHitRow({
    super.key,
    required this.hit,
    this.onTap,
    this.showDivider = true,
  });

  final DictionaryHit hit;

  /// 点击进词条正文（窄屏切换、宽屏右栏更新）。
  final VoidCallback? onTap;
  final bool showDivider;

  String _subtitle() {
    final pos = hit.posLabel;
    return pos == null || pos.isEmpty ? hit.subtitle : '$pos · ${hit.subtitle}';
  }

  /// 元信息 = 类型 · 首见课时 · 已学。课时链接是可选依赖（轻量 widget
  /// 测试可能不注册），缺省时只显示类型。
  String _metaLabel() {
    final parts = <String>[
      switch (hit.kind) {
        DictionaryHitKind.vocab => AppStrings.dictionaryKindWord,
        DictionaryHitKind.expression => AppStrings.dictionaryKindPhrase,
        DictionaryHitKind.grammar => AppStrings.dictionaryKindGrammar,
      },
    ];
    if (getIt.isRegistered<LessonLinkStore>()) {
      final link = getIt<LessonLinkStore>().linkFor(hit.id);
      if (link != null) {
        parts
          ..add(link.lessonName)
          ..add(AppStrings.dictionaryLearnedMeta);
      }
    }
    return parts.join(' · ');
  }

  @override
  Widget build(BuildContext context) {
    return DirectoryEntryRow(
      title: hit.title,
      subtitle: _subtitle(),
      meta: _metaLabel(),
      onTap: onTap,
      showDivider: showDivider,
      // 鸿蒙伴生版不随包 AI 模块（华为审核合规，ADR 0056）。
      trailing: isDegraded(OhosDegradation.aiGeneration)
          ? null
          : IconButton(
              tooltip: AppStrings.aiDictEnrich,
              visualDensity: VisualDensity.compact,
              onPressed: () => _openAiEnrich(context, hit),
              icon: const Icon(
                Icons.auto_awesome_rounded,
                color: TurnaTheme.amethystLeague,
              ),
            ),
    );
  }

  void _openAiEnrich(BuildContext context, DictionaryHit hit) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: TurnaTheme.cardBg(context),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(TurnaTheme.radiusXLarge),
        ),
      ),
      builder: (sheetCtx) {
        AiExplainPrefsStore? prefs;
        try {
          prefs = context.read<AiExplainPrefsStore>();
        } catch (_) {
          // Optional dependency: AI explain sheet runs without saved prefs.
        }
        return ChangeNotifierProvider(
          create: (_) => DictionaryAiProvider(prefs: prefs),
          child: _DictionaryAiSheet(hit: hit),
        );
      },
    );
  }
}

/// 词条正文：主词（大字）+ 发音 + 点读键（44 圆形 teal 描边）居上，
/// 释义与例句连续分段阅读（bodyText 16 / 行高 1.5）。
class DictionaryEntryDetail extends StatelessWidget {
  const DictionaryEntryDetail({
    super.key,
    required this.hit,
    required this.onSpeak,
    this.onBack,
  });

  final DictionaryHit hit;
  final VoidCallback onSpeak;

  /// 窄屏单栏的返回目录键；宽屏并排布局没有返回语义，不传。
  final VoidCallback? onBack;

  @override
  Widget build(BuildContext context) {
    final pronunciation = hit.pronunciation;
    final pos = hit.posLabel;
    final paragraphs = hit.subtitle
        .split('\n')
        .map((line) => line.trim())
        .where((line) => line.isNotEmpty)
        .toList();
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.pageMargin,
        AppSpacing.md,
        AppSpacing.pageMargin,
        AppSpacing.xxxl,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (onBack != null)
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: onBack,
                icon: const Icon(Icons.arrow_back_rounded, size: 18),
                label: Text(AppStrings.dictionaryBackToList),
              ),
            ),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(hit.title, style: AppTextStyles.pageTitle(context)),
                    if (pronunciation != null && pronunciation.isNotEmpty) ...[
                      const SizedBox(height: AppSpacing.xs),
                      Text(
                        pronunciation,
                        style: AppTextStyles.captionSm(context).copyWith(
                          fontSize: 14,
                          fontStyle: FontStyle.italic,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              IconButton(
                tooltip: AppStrings.dictionaryPlayPronunciation,
                onPressed: onSpeak,
                style: IconButton.styleFrom(
                  fixedSize: const Size(44, 44),
                  side: const BorderSide(color: TurnaTheme.brandTeal, width: 1.5),
                  shape: const CircleBorder(),
                ),
                icon: const Icon(
                  Icons.volume_up_rounded,
                  color: TurnaTheme.brandTeal,
                ),
              ),
            ],
          ),
          if (pos != null && pos.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.sm),
            Container(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.sm + 2,
                vertical: 3,
              ),
              decoration: BoxDecoration(
                color: TurnaTheme.softTint(context, TurnaTheme.brandTeal,
                    alpha: 0.12),
                borderRadius: BorderRadius.circular(TurnaTheme.radiusSmall),
              ),
              child: Text(
                pos,
                style: AppTextStyles.captionSm(context).copyWith(
                  color: TurnaTheme.accentOnCard(context, TurnaTheme.brandTeal),
                ),
              ),
            ),
          ],
          const SizedBox(height: AppSpacing.lg),
          for (final paragraph in paragraphs) ...[
            Text(paragraph, style: AppTextStyles.bodyText(context)),
            const SizedBox(height: AppSpacing.sm),
          ],
          if (hit.examples.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.md),
            Text(
              AppStrings.dictionaryExamplesTitle,
              style: AppTextStyles.cardTitle(context),
            ),
            const SizedBox(height: AppSpacing.sm),
            for (final (term, gloss) in hit.examples) ...[
              Text(
                term,
                style: AppTextStyles.bodyText(context)
                    .copyWith(fontWeight: FontWeight.w500),
              ),
              const SizedBox(height: 2),
              Text(gloss, style: AppTextStyles.captionSm(context)),
              const SizedBox(height: AppSpacing.md),
            ],
          ],
        ],
      ),
    );
  }
}

class _DictionaryAiSheet extends StatefulWidget {
  const _DictionaryAiSheet({required this.hit});
  final DictionaryHit hit;

  @override
  State<_DictionaryAiSheet> createState() => _DictionaryAiSheetState();
}

class _DictionaryAiSheetState extends State<_DictionaryAiSheet> {
  bool _started = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _run());
  }

  Future<void> _run() async {
    if (_started || !mounted) return;
    _started = true;
    final config = context.read<AiEngineConfigHolder>().config;
    if (!config.isComplete) return;
    await context.read<DictionaryAiProvider>().enrich(
          config: config,
          language: context.read<LanguageProvider>().displayName,
          term: widget.hit.title,
          translation: widget.hit.subtitle,
        );
  }

  @override
  Widget build(BuildContext context) {
    final config = context.watch<AiEngineConfigHolder>().config;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              '${AppStrings.aiDictEnrich} · ${widget.hit.title}',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
            ),
            const SizedBox(height: 12),
            if (!config.isComplete)
              const AiNotConfiguredPanel(compact: true)
            else
              Consumer<DictionaryAiProvider>(
                builder: (context, p, _) {
                  if (p.state == DictionaryAiState.loading) {
                    return Padding(
                      padding: const EdgeInsets.all(24),
                      child: Column(
                        children: [
                          const CircularProgressIndicator(
                              color: TurnaTheme.brandTeal),
                          const SizedBox(height: 12),
                          Text(AppStrings.aiDictEnriching),
                          TextButton(
                            onPressed: () => p.cancel(),
                            child: Text(AppStrings.aiStopGenerating),
                          ),
                        ],
                      ),
                    );
                  }
                  if (p.errorMapping != null) {
                    return AiErrorBanner(
                      mapping: p.errorMapping!,
                      onRetry: () {
                        _started = false;
                        _run();
                      },
                    );
                  }
                  final e = p.enrichment;
                  if (e == null) {
                    return Text(AppStrings.aiDictEnriching);
                  }
                  return _enrichmentBody(e);
                },
              ),
          ],
        ),
      ),
    );
  }

  Widget _enrichmentBody(DictionaryEnrichment e) {
    return ConstrainedBox(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.5,
      ),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (e.expandedGloss.isNotEmpty) ...[
              Text(e.expandedGloss),
              const SizedBox(height: 12),
            ],
            if (e.examples.isNotEmpty) ...[
              Text(
                AppStrings.aiDictExamples,
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
              for (final x in e.examples) Text('· $x'),
              const SizedBox(height: 12),
            ],
            if (e.mnemonic.isNotEmpty) ...[
              Text(
                AppStrings.aiDictMnemonic,
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
              Text(e.mnemonic),
            ],
            const SizedBox(height: 8),
            Row(
              children: [
                TextButton.icon(
                  onPressed: () {
                    Clipboard.setData(ClipboardData(
                      text: [
                        e.expandedGloss,
                        ...e.examples,
                        e.mnemonic,
                      ].where((s) => s.isNotEmpty).join('\n'),
                    ));
                    TurnaSnackBar.maybeShow(context, AppStrings.aiDepthCopied);
                  },
                  icon: const Icon(Icons.copy_rounded, size: 18),
                  label: Text(AppStrings.aiDepthCopy),
                ),
                TextButton.icon(
                  onPressed: () async {
                    final store = context.read<AiSavedExplanationsStore>();
                    await store.save(SavedExplanation(
                      id: AiSavedExplanationsStore.newId(),
                      title: widget.hit.title,
                      body: [
                        e.expandedGloss,
                        ...e.examples,
                        e.mnemonic,
                      ].where((s) => s.isNotEmpty).join('\n'),
                      source: 'dictionary',
                      createdAt: DateTime.now(),
                    ));
                    if (!mounted) return;
                    TurnaSnackBar.maybeShow(
                      context,
                      AppStrings.aiExplanationSaved,
                    );
                  },
                  icon: const Icon(Icons.bookmark_add_outlined, size: 18),
                  label: Text(AppStrings.aiSaveExplanation),
                ),
              ],
            ),
            Text(
              AppStrings.aiDisclaimer,
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: TurnaTheme.textHintColor(context),
                  ),
            ),
          ],
        ),
      ),
    );
  }
}

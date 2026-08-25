// Dart imports:
import 'dart:async';
import 'dart:io';

// Flutter imports:
import 'package:flutter/material.dart';

// Package imports:
import 'package:auto_route/auto_route.dart';
import 'package:provider/provider.dart';
import 'package:turna/application/settings_provider.dart';

// Project imports:
import 'package:turna/application/ai/engine/ai_engine.dart';
import 'package:turna/application/ai/engine/ai_engine_config.dart';
import 'package:turna/application/ai/engine/ai_engine_config_holder.dart';
import 'package:turna/application/anki/anki_card_adapter.dart';
import 'package:turna/application/anki/anki_deck_assembler.dart';
import 'package:turna/application/anki/anki_deck_manager.dart';
import 'package:turna/application/anki/anki_importer.dart';
import 'package:turna/application/anki/legacy_anki_import_executor.dart';
import 'package:turna/application/anki_official/contract/official_anki_errors.dart';
import 'package:turna/application/anki_official/import/anki_import_execution_plan.dart';
import 'package:turna/application/anki_official/import/anki_import_facade.dart';
import 'package:turna/application/anki_official/import/official_anki_official_first_service.dart';
import 'package:turna/application/anki_official/official_anki_feature_flags.dart';
import 'package:turna/application/anki_official/contract/official_anki_dto.dart';
import 'package:turna/application/anki_official/projection/official_anki_projection_mapper.dart';
import 'package:turna/application/anki_official/projection/official_anki_projection_service.dart';
import 'package:turna/application/anki_official/projection/official_anki_projection_store.dart';
import 'package:turna/application/anki/anki_models.dart';
import 'package:turna/application/anki/anki_organization_resolver.dart';
import 'package:turna/application/anki/card_recognition_pipeline.dart';
import 'package:turna/application/anki/anki_sample_deck.dart';
import 'package:turna/application/audio_controller.dart';
import 'package:turna/application/course_provider.dart';
import 'package:turna/application/mistake_provider.dart';
import 'package:turna/application/srs_provider.dart';
import 'package:turna/courses/course_loader.dart';
import 'package:turna/data/anki_import_dao.dart' show AnkiImportRecord;
import 'package:turna/data/course_database.dart';
import 'package:turna/data/review_history_dao.dart';
import 'package:turna/di/injection.dart';
import 'package:turna/l10n/app_strings.dart';
import 'package:turna/routing/routing.gr.dart';
import 'package:turna/utils/validated_file_picker.dart';
import 'package:turna/views/theme.dart';

/// File extensions accepted by the Anki import wizard.
/// `.colpkg` is unsupported until an Official backend exists (doc 34 W4-08).
const _ankiExtensions = ['apkg'];

enum _RecognitionAttention { recognized, advisory, blocking, skipped }

/// Anki import wizard screen. Guides the user through:
/// 1. File selection
/// 2. Parsing + preview (deck structure, notetype mapping, collision report)
/// 3. Strategy selection
/// 4. Import execution with progress
///
/// When [startWithSample] is true, the wizard loads the built-in sample deck
/// immediately (skipping the file picker).
@RoutePage()
class AnkiImportPage extends StatefulWidget {
  final bool startWithSample;

  /// Test seam: inject a parser so widget tests can drive the whole wizard
  /// without the parse worker isolate — fake-async cannot receive isolate
  /// port messages. Production always leaves this null.
  @visibleForTesting
  final AnkiImporter? importerForTest;

  const AnkiImportPage({
    super.key,
    this.startWithSample = false,
    this.importerForTest,
  });

  @override
  State<AnkiImportPage> createState() => _AnkiImportPageState();
}

class _AnkiImportPageState extends State<AnkiImportPage> {
  AnkiImporter get _importer => widget.importerForTest ?? _productionImporter;

  // W9-A: production AnkiImportExecutionPlanner fail-closes Legacy new-writes
  // (no allowLegacyOnly). Physical removal of this field is W9-C (HOLD).
  final _productionImporter = AnkiImporter();

  // Wizard state
  int _step = 0; // 0=select, 1=parsing, 2=preview, 3=importing, 4=done
  String? _filePath;
  AnkiCollection? _collection;
  String? _error;
  bool _isSample = false;

  /// Computed once per pick/sample (doc 34 W0-03). Later stages must not
  /// re-read flags and disagree on writer/owner.
  AnkiImportExecutionPlan? _plan;

  // Preview data
  Map<int, NotetypeMapping> _mappings = {};
  int _newCount = 0;
  int _existingCount = 0;
  ImportStrategy _strategy = ImportStrategy.merge;
  bool _smartGrouping = true;

  // Plan 1 Phase 5: Section-Beta toggle. Default off; only affects this new
  // import's tree layout — existing courses are never rewritten.
  bool _sectionBeta = false;
  bool _importLearningProgress = false;
  // Cached unit/lesson organization summary for the content section. Computed
  // once in [_preparePreview] and read on every preview rebuild so the user
  // does not pay the O(notes) cost each time they flip a strategy switch.
  AnkiOrganizationPreview? _organizationPreview;

  // AI notetype identification (optional; runs LLM over all notetypes).
  bool _isAiIdentifying = false;

  // Plan 1 Phase 4: explainable recognition metadata per notetype (source,
  // confidence, warnings) so the preview can show where each mapping came
  // from and flag low-confidence rows.
  Map<int, CardRecognitionResult> _recognitionResults = {};
  bool _showAllRecognition = false;

  // Incremental-update detection (computed at parse time)
  String? _sourceHash;
  AnkiImportRecord? _existingImport;

  // Progress
  String _progressMessage = '';
  double _progress = 0; // 0..1, 0 means indeterminate
  bool _cancelRequested = false;
  AnkiImportSummary? _summary;

  // ─── P5F-2 official-first flow state ─────────────────────────────────
  // Non-null once the official saga committed and the wizard switched to
  // projection-based preview/execution (no Dart apkg parse on this path).
  String? _officialSourceId;
  String? _officialSourceHash;
  int _officialCardCount = 0;
  int _officialNoteCount = 0;
  List<OfficialAnkiDeckNode> _officialDecks = const [];
  List<OfficialAnkiProjectionSchema> _officialSchemas = const [];
  Map<int, OfficialAnkiMappingSuggestion> _officialSuggestions = {};
  Set<int> _officialConfirmedNotetypes = {};
  Set<int> _officialSkippedNotetypes = {};
  OfficialAnkiCourseProjectionService? _officialService;
  bool _officialNeedsMapping = false;
  bool _showAllOfficialRecognition = false;

  // ─── Perf instrumentation ──────────────────────────────────────────
  //
  // Set to false to silence every [debugPrint] the import flow emits. Kept
  // on by default during the perf-investigation phase so we can collect real
  // numbers from a 5K+ card file; flip once we have data.
  static const bool _kEnableTimingLogs = true;

  /// Compact, parseable log line for a single timed phase. Format is
  /// `[AnkiImport] <label>: <ms>ms (<key>=<value> ...)` so the lines can be
  /// grepped or piped into a quick spreadsheet without parsing JSON.
  void _logTiming(String label, Stopwatch sw, [Map<String, Object?>? extras]) {
    if (!_kEnableTimingLogs) return;
    final buf =
        StringBuffer('[AnkiImport] $label: ${sw.elapsedMilliseconds}ms');
    if (extras != null && extras.isNotEmpty) {
      buf.write(' (');
      var first = true;
      extras.forEach((k, v) {
        if (!first) buf.write(' ');
        buf.write('$k=$v');
        first = false;
      });
      buf.write(')');
    }
    debugPrint(buf.toString());
  }

  @override
  void dispose() {
    // A successful parse keeps its extraction directory alive until media is
    // copied. If the wizard is abandoned at preview, release it here.
    final mediaDir = _collection?.mediaDir;
    if (mediaDir != null && mediaDir.isNotEmpty) {
      AnkiImporter.cleanupExtractedDir(mediaDir);
    }
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    if (widget.startWithSample) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) unawaited(_loadSampleDeck());
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          _isSample
              ? '${AppStrings.ankiImportTitle} · ${AppStrings.ankiSampleBadge}'
              : AppStrings.ankiImportTitle,
          // Long sample-mode title (导入 Anki 牌组 · 示例) overflows the
          // AppBar on narrow phones; constrain it so the trailing back
          // button stays reachable.
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.router.maybePop(),
        ),
        // While parsing/importing (steps 1 and 3) the cancel action lives in
        // the body for a clearer visual focus; suppress the trailing slot so
        // the AppBar stays simple.
      ),
      body: Column(
        children: [
          _WizardStepper(currentStep: _step),
          Expanded(child: _buildBody()),
        ],
      ),
    );
  }

  Widget _buildBody() {
    switch (_step) {
      case 0:
        return _buildSelectStep();
      case 1:
        return _buildParsingStep();
      case 2:
        // P5F-2: the official-first flow has its own projection-based preview.
        return _officialSourceId != null
            ? _buildOfficialPreviewStep()
            : _buildPreviewStep();
      case 3:
        return _buildImportingStep();
      case 4:
        return _buildDoneStep();
      default:
        return const SizedBox.shrink();
    }
  }

  // ─── Step 0: File Selection ─────────────────────────────────────────

  Widget _buildSelectStep() {
    // Wrap in SafeArea + a constrained scroll view so the column stays
    // vertically centered when there is enough room, and becomes scrollable
    // when a small viewport reduces the available height.
    //
    // We use Center (not stretch) around the Column so that children stay
    // horizontally centered by content width (matching the pre-fix look),
    // and ConstrainedBox(minHeight: maxHeight) so the Center box fills the
    // viewport when the column is short — letting `mainAxisAlignment:
    // center` actually center the column vertically.
    return SafeArea(
      child: LayoutBuilder(
        builder: (context, constraints) => SingleChildScrollView(
          padding: EdgeInsets.zero,
          child: ConstrainedBox(
            constraints: BoxConstraints(
              minHeight: constraints.maxHeight,
              minWidth: constraints.maxWidth,
            ),
            child: Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.upload_file_rounded,
                      size: 80,
                      color: TurnaTheme.brandTeal.withValues(alpha: 0.6),
                    ),
                    const SizedBox(height: 24),
                    // No duplicate title here; the AppBar already shows it.
                    Text(
                      AppStrings.ankiImportSelectSubtitle,
                      style: TextStyle(
                        color: TurnaTheme.textSecondaryColor(context),
                        fontSize: 15,
                        height: 1.4,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 32),
                    if (_error != null)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 16),
                        child: Text(
                          _error!,
                          style: const TextStyle(color: TurnaTheme.error),
                          textAlign: TextAlign.center,
                        ),
                      ),
                    ElevatedButton.icon(
                      onPressed: _pickFile,
                      icon: const Icon(Icons.folder_open),
                      label: Text(AppStrings.ankiChooseFile),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: TurnaTheme.brandTeal,
                        foregroundColor: TurnaTheme.textOnPrimary,
                        padding: const EdgeInsets.symmetric(
                            horizontal: 32, vertical: 16),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  // ─── Step 1: Parsing ────────────────────────────────────────────────

  Widget _buildParsingStep() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          if (_progress > 0)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 60),
              child: LinearProgressIndicator(
                value: _progress,
                backgroundColor: TurnaTheme.brandTeal.withValues(alpha: 0.1),
                valueColor:
                    const AlwaysStoppedAnimation<Color>(TurnaTheme.brandTeal),
              ),
            )
          else
            const CircularProgressIndicator(),
          const SizedBox(height: 24),
          Text(
            AppStrings.ankiParsing,
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
            ),
          ),
          if (_progressMessage.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              _progressMessage,
              style: TextStyle(
                color: TurnaTheme.textSecondaryColor(context),
                fontSize: 13,
              ),
            ),
          ],
          const SizedBox(height: 24),
          OutlinedButton.icon(
            onPressed: () {
              setState(() {
                _cancelRequested = true;
                _step = 0;
                _progress = 0;
                _progressMessage = '';
              });
            },
            icon: const Icon(Icons.close, size: 18),
            label: Text(AppStrings.commonCancel),
            style: OutlinedButton.styleFrom(
              foregroundColor: TurnaTheme.textSecondaryColor(context),
              side: BorderSide(
                color: TurnaTheme.textHintColor(context).withValues(alpha: 0.5),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ─── Step 2: Preview ────────────────────────────────────────────────

  Widget _buildPreviewStep() {
    final collection = _collection!;
    return Column(
      children: [
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
            children: [
              _buildContentSection(collection),
              const SizedBox(height: 12),
              _buildMappingSection(collection),
              const SizedBox(height: 12),
              _AdvancedOptionsCard(
                summary: '重复卡片：${_strategyLabel(context, _strategy)}',
                children: [
                  _buildOrganizationBlock(),
                  const SizedBox(height: 12),
                  _buildStrategySection(),
                ],
              ),
            ],
          ),
        ),
        _StickyImportBar(
          onPressed:
              _hasLegacyBlockingRecognition(collection) ? null : _executeImport,
          disabledHint: _hasLegacyBlockingRecognition(collection)
              ? AppStrings.ankiMappingFixBlocking
              : null,
        ),
      ],
    );
  }

  /// Section 1: what is in the deck. Collection summary, deck structure,
  /// and the auto-detected unit/lesson organization all live here.
  Widget _buildContentSection(AnkiCollection collection) {
    return _SectionCard(
      icon: Icons.layers_rounded,
      title: AppStrings.ankiPreviewSectionContent,
      hint: AppStrings.ankiPreviewSectionContentHint,
      children: [
        // Stat strip: 4 compact stat boxes
        _StatStrip(
          items: [
            (AppStrings.ankiDecksLabel, collection.decks.length),
            (AppStrings.ankiNotesLabel, collection.notes.length),
            (AppStrings.ankiCardsLabel, collection.cards.length),
            (AppStrings.ankiMediaFilesLabel, collection.media.length),
          ],
        ),
        if (collection.decks.isNotEmpty) ...[
          const SizedBox(height: 12),
          const _Subheader(text: '牌组结构'),
          const SizedBox(height: 4),
          for (final deck in collection.decks.values)
            _InfoRow(
              deck.name,
              AppStrings.ankiDeckCardCount(deck.cardCount),
            ),
        ],
      ],
    );
  }

  /// Preview of the unit/lesson organization detected from Anki tags and
  /// notetype fields, plus a toggle to enable smart grouping.
  ///
  /// Reads the cached [_organizationPreview] populated by [_preparePreview]
  /// instead of re-running the O(notes) scan on every rebuild. The block is
  /// the only place in the preview screen that needs an O(notes) computation
  /// — every other section is O(1) in the collection size.
  Widget _buildOrganizationBlock() {
    final preview = _organizationPreview;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _Subheader(text: '组织结构'),
        const SizedBox(height: 4),
        if (preview != null && preview.hasAny) ...[
          if (_sectionBeta && preview.sectionNames.isNotEmpty) ...[
            _InfoRow('检测到 Section', preview.sectionCountLabel),
            if (preview.lowConfidenceSectionHint != null)
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Text(
                  preview.lowConfidenceSectionHint!,
                  style: TextStyle(
                    fontSize: 11,
                    color: TurnaTheme.textHintColor(context),
                  ),
                ),
              ),
          ],
          _InfoRow(AppStrings.ankiDetectedUnits, '${preview.unitCount}'),
          _InfoRow(AppStrings.ankiDetectedLessons, '${preview.lessonCount}'),
          _InfoRow(
              AppStrings.ankiResolvedCards, '${preview.resolvedCardCount}'),
        ] else
          _InfoRow(AppStrings.ankiOrganizationNone,
              AppStrings.ankiOrganizationNoneDesc),
        const SizedBox(height: 4),
        Material(
          type: MaterialType.transparency,
          child: SwitchListTile(
            value: _smartGrouping,
            onChanged: (v) => setState(() => _smartGrouping = v),
            title: Text(
              AppStrings.ankiSmartGrouping,
              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
            ),
            subtitle: Text(
              AppStrings.ankiSmartGroupingDesc,
              style: const TextStyle(fontSize: 12),
            ),
            dense: true,
            contentPadding: EdgeInsets.zero,
          ),
        ),
        // Plan 1 Phase 5 Beta: semantic Section grouping. Only affects this
        // new import; off by default.
        Material(
          type: MaterialType.transparency,
          child: SwitchListTile(
            value: _sectionBeta,
            onChanged: _smartGrouping
                ? (v) {
                    setState(() => _sectionBeta = v);
                    _recomputeOrganizationPreview();
                  }
                : null,
            title: const Text(
              '自动分 Section（Beta）',
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
            ),
            subtitle: const Text(
              '按 Chapter/章 字段或 Unit 前缀把多个 Unit 归入 Section',
              style: TextStyle(fontSize: 12),
            ),
            dense: true,
            contentPadding: EdgeInsets.zero,
          ),
        ),
      ],
    );
  }

  /// Re-run the O(notes) organization scan when the Section-Beta toggle
  /// changes so the preview reflects the section detections it enables.
  void _recomputeOrganizationPreview() {
    final collection = _collection;
    if (collection == null) return;
    const resolver = AnkiOrganizationResolver();
    _organizationPreview = resolver.preview(
      notes: collection.notes,
      notetypes: collection.notetypes,
      sectionBeta: _sectionBeta,
    );
  }

  _RecognitionAttention _legacyRecognitionAttention(
    int mid,
    AnkiNotetype notetype,
  ) {
    final mapping = _mappings[mid];
    final fieldCount = notetype.fieldNames.length;
    if (mapping == null || fieldCount == 0) {
      return _RecognitionAttention.blocking;
    }
    if (_mappingUsesFrontBackFields(mapping.type)) {
      final front = mapping.frontFieldIndex;
      final back = mapping.backFieldIndex;
      if (front < 0 || back < 0 || front >= fieldCount || back >= fieldCount) {
        return _RecognitionAttention.blocking;
      }
      if (fieldCount > 1 && front == back) {
        return _RecognitionAttention.blocking;
      }
    }
    return (_recognitionResults[mid]?.needsConfirmation ?? true)
        ? _RecognitionAttention.advisory
        : _RecognitionAttention.recognized;
  }

  bool _hasLegacyBlockingRecognition(AnkiCollection collection) =>
      collection.notetypes.entries.any(
        (entry) =>
            _legacyRecognitionAttention(entry.key, entry.value) ==
            _RecognitionAttention.blocking,
      );

  /// Section 2: how each card type is identified. Plain-language by design:
  /// one row per notetype with a ✓ (auto-recognized) / ⚠ (worth checking)
  /// state — confidence percentages, sources and evidence stay out of sight.
  /// The AI re-identification button only appears when something needs a
  /// manual look.
  Widget _buildMappingSection(AnkiCollection collection) {
    final entries = collection.notetypes.entries.toList();
    final attention = {
      for (final entry in entries)
        entry.key: _legacyRecognitionAttention(entry.key, entry.value),
    };
    final blocking = attention.values
        .where((value) => value == _RecognitionAttention.blocking)
        .length;
    final advisory = attention.values
        .where((value) => value == _RecognitionAttention.advisory)
        .length;
    final issues = entries
        .where((entry) =>
            attention[entry.key] == _RecognitionAttention.blocking ||
            attention[entry.key] == _RecognitionAttention.advisory)
        .toList();
    final shownEntries = _showAllRecognition ? entries : issues;
    final aiReady = context.watch<AiEngineConfigHolder>().config.isComplete;
    final statusColor = blocking > 0
        ? TurnaTheme.error
        : advisory > 0
            ? TurnaTheme.warning
            : TurnaTheme.brandTeal;
    return _SectionCard(
      icon: Icons.auto_awesome_outlined,
      title: AppStrings.ankiPreviewSectionMapping,
      hint: AppStrings.ankiPreviewSectionMappingHint,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              blocking > 0
                  ? Icons.error_outline_rounded
                  : advisory > 0
                      ? Icons.help_outline_rounded
                      : Icons.check_circle_outline_rounded,
              color: statusColor,
              size: 20,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                blocking > 0
                    ? AppStrings.ankiMappingSummaryBlocking(blocking)
                    : advisory > 0
                        ? AppStrings.ankiMappingSummaryNeedsCheck(
                            entries.length - advisory, advisory)
                        : AppStrings.ankiMappingSummaryAll(entries.length),
                style: TextStyle(
                  color: statusColor,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            TextButton(
              onPressed: () =>
                  setState(() => _showAllRecognition = !_showAllRecognition),
              child: Text(
                _showAllRecognition
                    ? AppStrings.commonCollapse
                    : AppStrings.ankiMappingViewAll,
              ),
            ),
          ],
        ),
        if (shownEntries.isNotEmpty) const SizedBox(height: 6),
        for (final entry in shownEntries)
          _NotetypeMappingRow(
            notetype: entry.value,
            mapping: _mappings[entry.key],
            recognition: _recognitionResults[entry.key],
            attention: attention[entry.key]!,
            onEdit: () => _editNotetypeMapping(entry.key, entry.value),
          ),
        if (advisory > 0 && aiReady) ...[
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: _isAiIdentifying ? null : _onAiIdentify,
            icon: _isAiIdentifying
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.auto_awesome_outlined, size: 18),
            label: Text(
              _isAiIdentifying
                  ? AppStrings.ankiAiIdentifying
                  : AppStrings.ankiAiRetry,
            ),
            style: OutlinedButton.styleFrom(
              foregroundColor: TurnaTheme.brandTeal,
              side: const BorderSide(color: TurnaTheme.brandTeal),
            ),
          ),
        ],
      ],
    );
  }

  /// Advanced: how collisions and learning progress are handled. Rendered
  /// inside the collapsed advanced-options card, so this returns bare
  /// children instead of another _SectionCard.
  Widget _buildStrategySection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _Subheader(text: '重复卡片怎么处理'),
        const SizedBox(height: 6),
        // Collision report with a thin progress bar so users can eyeball
        // the new-vs-existing ratio at a glance.
        _CollisionStrip(
          newCount: _newCount,
          existingCount: _existingCount,
        ),
        const SizedBox(height: 6),
        Text(
          AppStrings.ankiPreviewCollisionVisualHint,
          style: TextStyle(
            fontSize: 11,
            color: TurnaTheme.textHintColor(context),
          ),
        ),
        const SizedBox(height: 12),
        // Strategy selection: 4 cards with title, description, and a
        // "data consequence" line so users can compare tradeoffs side by
        // side. Force Replace is the only one that destroys existing
        // learning state, so it gets the warning-style hint.
        RadioGroup<ImportStrategy>(
          groupValue: _strategy,
          onChanged: (value) {
            if (value != null) setState(() => _strategy = value);
          },
          child: Column(
            children: [
              for (final s in ImportStrategy.values) ...[
                _StrategyOption(
                  value: s,
                  groupValue: _strategy,
                  title: _strategyLabel(context, s),
                  description: _strategyDescription(context, s),
                  consequence: _strategyConsequence(s),
                  isWarning: s == ImportStrategy.forceReplace,
                  onChanged: (v) => setState(() => _strategy = v),
                ),
                const SizedBox(height: 8),
              ],
            ],
          ),
        ),
        const SizedBox(height: 4),
        Material(
          color: TurnaTheme.brandTeal.withValues(alpha: 0.04),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(TurnaTheme.radiusSmall),
            side: BorderSide(
              color: TurnaTheme.brandTeal.withValues(alpha: 0.12),
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
            child: SwitchListTile.adaptive(
              contentPadding: EdgeInsets.zero,
              title: Text(
                AppStrings.ankiImportLearningProgress,
                style:
                    const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
              ),
              subtitle: Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Text(
                  _importLearningProgress
                      ? AppStrings.ankiImportLearningProgressOnDesc
                      : AppStrings.ankiImportLearningProgressOffDesc,
                  style: const TextStyle(fontSize: 12),
                ),
              ),
              value: _importLearningProgress,
              onChanged: (value) {
                setState(() => _importLearningProgress = value);
              },
            ),
          ),
        ),
      ],
    );
  }

  // ─── Step 3: Importing ──────────────────────────────────────────────

  Widget _buildImportingStep() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          if (_progress > 0)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 60),
              child: LinearProgressIndicator(
                value: _progress,
                backgroundColor: TurnaTheme.brandTeal.withValues(alpha: 0.1),
                valueColor:
                    const AlwaysStoppedAnimation<Color>(TurnaTheme.brandTeal),
              ),
            )
          else
            const CircularProgressIndicator(),
          const SizedBox(height: 24),
          Text(
            _progressMessage.isEmpty
                ? AppStrings.ankiPreparingImport
                : _progressMessage,
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 24),
          OutlinedButton.icon(
            onPressed: () {
              setState(() {
                _cancelRequested = true;
              });
            },
            icon: const Icon(Icons.close, size: 18),
            label: Text(AppStrings.commonCancel),
            style: OutlinedButton.styleFrom(
              foregroundColor: TurnaTheme.textSecondaryColor(context),
              side: BorderSide(
                color: TurnaTheme.textHintColor(context).withValues(alpha: 0.5),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ─── Step 4: Done ───────────────────────────────────────────────────

  Widget _buildDoneStep() {
    final summary = _summary;
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(24, 24, 24, 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SizedBox(height: 8),
            const Center(
              child: Icon(
                Icons.check_circle_outline,
                size: 72,
                color: TurnaTheme.success,
              ),
            ),
            const SizedBox(height: 16),
            Center(
              child: Text(
                AppStrings.ankiImportComplete,
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
              ),
            ),
            if (summary != null) ...[
              const SizedBox(height: 8),
              Center(
                child: Text(
                  AppStrings.ankiDoneSummary(summary.cardCount),
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                    color: TurnaTheme.brandTeal,
                  ),
                ),
              ),
              Center(
                child: Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(
                    summary.lessonCount > 0
                        ? AppStrings.ankiLessonsCreated(summary.lessonCount)
                        : AppStrings.anki21bTreeDeferred,
                    style: TextStyle(
                      fontSize: 13,
                      color: TurnaTheme.textSecondaryColor(context),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 20),
              // Source data: counts the user can compare against the source file.
              _DoneGroup(
                title: AppStrings.ankiDoneGroupSource,
                rows: [
                  AppStrings.ankiImportSourceCards(summary.sourceCardCount),
                  AppStrings.ankiImportStructuredCards(
                      summary.structuredCardCount),
                  AppStrings.ankiImportFidelityCards(summary.fidelityCardCount),
                ],
              ),
              if (summary.wordEntryCount > 0) ...[
                const SizedBox(height: 12),
                _DoneGroup(
                  title: AppStrings.ankiDoneGroupVocab,
                  rows: [
                    AppStrings.ankiVocabAdded(summary.wordEntryCount),
                  ],
                ),
              ],
              // Status notes: only show non-zero warnings so a clean import
              // does not list "0 missing media" / "0 buried" etc.
              if (summary.unknownTemplateCount > 0 ||
                  summary.suspendedCardCount > 0 ||
                  summary.buriedCardCount > 0 ||
                  summary.missingMediaCount > 0 ||
                  summary.failedMediaCount > 0) ...[
                const SizedBox(height: 12),
                _DoneGroup(
                  title: AppStrings.ankiDoneGroupStatus,
                  rows: [
                    if (summary.unknownTemplateCount > 0)
                      AppStrings.ankiImportUnknownTemplates(
                          summary.unknownTemplateCount),
                    if (summary.suspendedCardCount > 0)
                      AppStrings.ankiImportSuspended(
                          summary.suspendedCardCount),
                    if (summary.buriedCardCount > 0)
                      AppStrings.ankiImportBuried(summary.buriedCardCount),
                    if (summary.missingMediaCount > 0 ||
                        summary.failedMediaCount > 0)
                      AppStrings.ankiImportMissingMedia(
                          summary.missingMediaCount + summary.failedMediaCount),
                  ],
                ),
              ],
              const SizedBox(height: 12),
              // Single-line learning-progress summary (kept / reset). Avoids
              // showing two redundant chips when only one is meaningful.
              _LearningProgressBadge(
                kept: _importLearningProgress,
                hasScheduling: summary.hasScheduling,
                hasReviewHistory: summary.hasReviewHistory,
              ),
            ],
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: _startLearningNow,
              icon: const Icon(Icons.play_arrow_rounded, size: 20),
              label: Text(
                AppStrings.ankiStartLearning,
                style: const TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 16,
                ),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: TurnaTheme.brandTeal,
                foregroundColor: TurnaTheme.textOnPrimary,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
            const SizedBox(height: 8),
            // Secondary action: open course management with the new course
            // highlighted (switch / reorder / inspect) — a distinct
            // destination from "Done", which simply returns (plan 34 R1-4).
            OutlinedButton.icon(
              onPressed: _viewDecks,
              icon: const Icon(Icons.list_alt_rounded, size: 18),
              label: Text(AppStrings.ankiDoneViewDecks),
              style: OutlinedButton.styleFrom(
                foregroundColor: TurnaTheme.brandTeal,
                side: const BorderSide(color: TurnaTheme.brandTeal),
                padding: const EdgeInsets.symmetric(vertical: 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
            const SizedBox(height: 4),
            TextButton(
              onPressed: () => context.router.maybePop(),
              child: Text(AppStrings.commonDone),
            ),
          ],
        ),
      ),
    );
  }

  // ─── Actions ────────────────────────────────────────────────────────

  /// Wire key of the catalog entry for a freshly imported id (legacy
  /// importId or official sourceId), or null when the entry is not (yet)
  /// in the catalog.
  String? _wireForImportId(String id, CourseProvider courseProvider) {
    for (final entry in courseProvider.catalogEntries) {
      if (entry.legacyImportId == id || entry.officialSourceId == id) {
        return entry.wireKey;
      }
    }
    return null;
  }

  /// "Start learning now" on the done step: switch to the freshly-imported
  /// course and pop back to the Learn tab, so the deck is immediately
  /// usable like a real course. This is the ONLY done action that switches
  /// the active course (plan 34 R1-4).
  Future<void> _startLearningNow() async {
    final importId = _summary?.importId;
    if (importId != null) {
      final courseProvider = context.read<CourseProvider>();
      final wire = _wireForImportId(importId, courseProvider);
      if (wire != null) {
        await courseProvider.setCourseScope(wire);
      }
    }
    if (mounted) context.router.maybePop();
  }

  /// "View decks" on the done step: open course management with the new
  /// course highlighted. The current course stays active.
  Future<void> _viewDecks() async {
    final importId = _summary?.importId;
    String? highlight;
    if (importId != null) {
      highlight = _wireForImportId(importId, context.read<CourseProvider>());
    }
    await context.router.push(CourseManagementRoute(highlightWire: highlight));
  }

  Future<void> _pickFile() async {
    try {
      final result = await ValidatedFilePicker.pickFiles(
        allowedExtensions: _ankiExtensions,
        dialogTitle: AppStrings.ankiImportDialogTitle,
      );

      if (result == null || result.files.isEmpty) return;
      final path = result.files.single.path;
      if (path == null) return;

      await _proceedWithPath(path);
    } on ValidatedFilePickerInvalidExtension {
      setState(() => _error = AppStrings.ankiPickFileError);
    } catch (e) {
      setState(() {
        _error = AppStrings.ankiPickFileFailed(e);
        _step = 0;
      });
    }
  }

  Future<void> _proceedWithPath(String path) async {
    setState(() {
      _filePath = path;
      _error = null;
      _step = 1;
    });
    // Doc 34 W0: one atomic plan for the whole import. Official-first skips
    // the Dart apkg parse; unsupported / fail-closed create zero sources;
    // legacyOnly (explicit haemostasis only) keeps the parse → preview flow.
    final plan = AnkiImportFacade.planFor(
      OfficialAnkiFeatureFlags.current,
      isSample: false,
      filePath: path,
    );
    _plan = plan;
    if (plan.kind == AnkiImportExecutionKind.officialFirst) {
      await _runOfficialFirstFlow(path);
      return;
    }
    if (plan.kind == AnkiImportExecutionKind.failClosed ||
        plan.kind == AnkiImportExecutionKind.unsupported) {
      if (!mounted) return;
      setState(() {
        _error = _humanizePlanFailure(plan);
        _step = 0;
        _plan = null;
      });
      return;
    }
    // legacyOnly haemostasis only — production planFor never selects this.
    await _parseFile(path);
  }

  Future<void> _loadSampleDeck() async {
    // Doc 34: in-memory sample is not an Official package and must not create
    // a mixed Official-owner / Legacy-writer half-state on Android production.
    final samplePlan = AnkiImportFacade.planFor(
      OfficialAnkiFeatureFlags.current,
      isSample: true,
      filePath: AnkiSampleDeck.sourcePath,
    );
    _plan = samplePlan;
    if (samplePlan.kind != AnkiImportExecutionKind.legacyOnly) {
      if (!mounted) return;
      setState(() {
        _error = _humanizePlanFailure(samplePlan);
        _isSample = false;
        _step = 0;
        _plan = null;
      });
      return;
    }

    setState(() {
      _error = null;
      _isSample = true;
      _step = 1;
      _progress = 0;
      _progressMessage = AppStrings.ankiParsing;
      _cancelRequested = false;
    });

    try {
      final collection = AnkiSampleDeck.build();
      await _preparePreview(
        collection,
        sourcePath: AnkiSampleDeck.sourcePath,
        isSample: true,
      );
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = AppStrings.ankiParseFailed(e);
        _step = 0;
        _isSample = false;
      });
    }
  }

  Future<void> _parseFile(String path) async {
    final totalSw = Stopwatch()..start();
    setState(() {
      _cancelRequested = false;
      _progress = 0;
      _progressMessage = '';
      _isSample = false;
    });
    try {
      final parseSw = Stopwatch()..start();
      final collection = await _importer.parse(
        path,
        onProgress: (p, msg) {
          if (mounted) {
            setState(() {
              _progress = p;
              _progressMessage = msg;
            });
          }
        },
        isCancelled: () => _cancelRequested,
      );
      parseSw.stop();
      _logTiming('parse: _importer.parse', parseSw, {
        'cards': collection.cards.length,
        'notes': collection.notes.length,
        'decks': collection.decks.length,
        'media': collection.media.length,
      });

      final prepSw = Stopwatch()..start();
      await _preparePreview(collection, sourcePath: path, isSample: false);
      prepSw.stop();
      _logTiming('parse: _preparePreview', prepSw);

      totalSw.stop();
      _logTiming('parse: total', totalSw);
    } on AnkiImportCancelled {
      totalSw.stop();
      _logTiming('parse: cancelled', totalSw);
      // User pressed cancel — nothing was written; return to file picker.
      if (mounted) {
        setState(() {
          _step = 0;
          _progress = 0;
          _progressMessage = '';
        });
      }
    } on OfficialAnkiException catch (e) {
      totalSw.stop();
      _logTiming('parse: official failed', totalSw, {
        'code': e.code.name,
        'key': e.messageKey,
      });
      if (e.code == OfficialAnkiErrorCode.importCancelled) {
        if (mounted) {
          setState(() {
            _step = 0;
            _progress = 0;
            _progressMessage = '';
          });
        }
      } else {
        if (mounted) {
          setState(() {
            _error = _mapOfficialErrorToHuman(e);
            _step = 0;
          });
        }
      }
    } catch (e) {
      totalSw.stop();
      _logTiming('parse: failed', totalSw, {'error': e.toString()});
      if (mounted) {
        setState(() {
          _error = _mapGeneralErrorToHuman(e);
          _step = 0;
        });
      }
    }
  }

  String _mapOfficialErrorToHuman(OfficialAnkiException e) {
    if (e.code == OfficialAnkiErrorCode.packageInvalid ||
        e.code == OfficialAnkiErrorCode.collectionCorrupt) {
      return AppStrings.ankiCorruptDeck;
    }
    if (e.code == OfficialAnkiErrorCode.packageNotFound ||
        e.code == OfficialAnkiErrorCode.ioError) {
      return AppStrings.ankiFileReadFailed;
    }
    if (e.code == OfficialAnkiErrorCode.unsupportedPlatform ||
        e.code == OfficialAnkiErrorCode.contractVersionMismatch) {
      return AppStrings.ankiPickFileError;
    }
    return '${AppStrings.ankiImportFailedHuman} (${e.code.name})';
  }

  String _mapGeneralErrorToHuman(Object error) {
    if (error is FileSystemException || error is IOException) {
      return AppStrings.ankiFileReadFailed;
    }
    if (error is AnkiImportException) {
      return error.message;
    }
    final msg = error.toString();
    if (msg.contains('.colpkg')) {
      return AppStrings.ankiColpkgUnsupported;
    }
    if (msg.contains('.apkg')) {
      return AppStrings.ankiPickFileError;
    }
    return AppStrings.ankiParseFailed(error);
  }

  String _humanizePlanFailure(AnkiImportExecutionPlan plan) {
    if (plan.reason == 'colpkg_not_supported_until_official_backend') {
      return AppStrings.ankiColpkgUnsupported;
    }
    return AppStrings.ankiImportUnavailable(plan.reason);
  }

  /// Shared path after a collection is available (parsed file or sample).
  Future<void> _preparePreview(
    AnkiCollection collection, {
    required String sourcePath,
    required bool isSample,
  }) async {
    // Build a complete local recognition result before showing the preview.
    // An empty API key deliberately disables the remote AI branch while still
    // running persisted rules, deterministic rules and the labeled fallback.
    final mappingSw = Stopwatch()..start();
    final recognitionResults = await CardRecognitionPipeline().recognizeAll(
      config: const AiEngineConfig(apiKey: ''),
      notetypes: collection.notetypes,
      notes: collection.notes,
    );
    final mappings = {
      for (final entry in recognitionResults.entries)
        entry.key: _canonicalizeMapping(entry.value.mapping),
    };
    mappingSw.stop();
    _logTiming('preview: mapping inference', mappingSw,
        {'notetypes': collection.notetypes.length});

    // Run the unit/lesson organization scan once. preview() is O(notes) and
    // was previously re-invoked on every preview rebuild (strategy change,
    // smart-grouping toggle, mapping edit, etc.) — for multi-thousand-card
    // decks that added visible jank to every tap. Caching it here means the
    // build path just reads the field, which is O(1).
    final orgSw = Stopwatch()..start();
    const orgResolver = AnkiOrganizationResolver();
    final orgPreview = orgResolver.preview(
      notes: collection.notes,
      notetypes: collection.notetypes,
    );
    orgSw.stop();
    _logTiming('preview: org scan', orgSw, {'notes': collection.notes.length});

    // The source hash was computed once during parsing (from the bytes
    // already loaded for ZIP extraction), so we can detect re-imports here
    // without re-reading the whole file on the main isolate.
    final hash = collection.sourceHash;

    // Real collision report:
    // - Same file imported before (hash match) -> ids are deterministic
    //   (anki-<importId>-c<cardId>, decision 2), so count notes already in
    //   the SRS queue under the previous importId as "existing".
    // - Otherwise everything is new.
    final daoSw = Stopwatch()..start();
    final existingImport = await LegacyAnkiImportInspector(
      getIt<CourseDatabase>(),
    ).findExistingByHash(hash);
    daoSw.stop();
    _logTiming(
        'preview: dao.findByHash', daoSw, {'hit': existingImport != null});
    if (!mounted) return;
    var existingCount = 0;
    if (existingImport != null) {
      final srsSw = Stopwatch()..start();
      final srsIds = context.read<SrsProvider>().state.keys.toSet();
      // Card-level wordIds: a note is already imported if any of its
      // cards is in the SRS queue under the previous importId.
      final existingNids = <int>{
        for (final card in collection.cards)
          if (srsIds.contains('anki-${existingImport.importId}-c${card.id}'))
            card.nid,
      };
      existingCount =
          collection.notes.where((n) => existingNids.contains(n.id)).length;
      srsSw.stop();
      _logTiming('preview: srs compare', srsSw, {
        'cards': collection.cards.length,
        'srsSize': srsIds.length,
        'existingNotes': existingCount,
      });
    }

    if (!mounted) return;
    setState(() {
      _filePath = sourcePath;
      _collection = collection;
      _mappings = mappings;
      _recognitionResults = recognitionResults;
      _showAllRecognition = false;
      _sourceHash = hash;
      _existingImport = existingImport;
      _newCount = collection.notes.length - existingCount;
      _existingCount = existingCount;
      _organizationPreview = orgPreview;
      _isSample = isSample;
      // A re-import defaults to merge (update in place); first import keeps
      // merge as well — it behaves identically when nothing exists.
      _strategy = ImportStrategy.merge;
      _step = 2;
    });
  }

  /// Open the mapping editor for one notetype (using the first note of that
  /// mid as a live sample). When the user saves an override, it is written
  /// back into [_mappings] so the change flows into the import assemblers
  /// via `mappingOverrides` - no downstream change needed. An explicit edit
  /// is a user confirmation: the mapping is persisted as a rule keyed by the
  /// notetype signature so future imports of the same kind reuse it.
  Future<void> _editNotetypeMapping(int mid, AnkiNotetype notetype) async {
    final notes = _collection?.notes ?? const <AnkiNote>[];
    AnkiNote? note;
    for (final n in notes) {
      if (n.mid == mid) {
        note = n;
        break;
      }
    }
    if (!mounted) return;
    final result = await showDialog<NotetypeMapping>(
      context: context,
      builder: (ctx) => _NotetypeMappingEditor(
        notetype: notetype,
        note: note,
        initialMapping: _mappings[mid],
      ),
    );
    if (result == null) return;
    setState(() {
      _mappings[mid] = result;
      _recognitionResults[mid] = CardRecognitionResult(
        mapping: result,
        confidence: 1.0,
        source: CardRecognitionSource.persisted,
        evidence: '用户手动确认的映射（已保存为规则）',
      );
    });
    unawaited(AnkiNotetypeRuleStore().save(
      NotetypeSignature.of(
        notetype,
        version: CardRecognitionPipeline.recognizerVersion,
      ).value,
      result,
    ));
  }

  /// Run the versioned recognition pipeline over all notetypes: persisted
  /// rules first, then deterministic rules, then one batched AI request
  /// (privacy-safe sample features only), then heuristic fallback. Every
  /// result carries source/confidence/evidence so the preview can explain
  /// itself (Plan 1 Phase 4).
  Future<void> _onAiIdentify() async {
    final collection = _collection;
    if (collection == null || collection.notetypes.isEmpty) return;
    final config = context.read<AiEngineConfigHolder>().config;
    if (!config.isComplete) {
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(AppStrings.aiNotConfiguredTitle),
          content: Text(AppStrings.ankiAiNotConfiguredMessage),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: Text(AppStrings.commonOk),
            ),
          ],
        ),
      );
      return;
    }
    setState(() => _isAiIdentifying = true);
    try {
      final pipelineSw = Stopwatch()..start();
      final results = await CardRecognitionPipeline(
        engine: getIt<AiEngine>(),
      ).recognizeAll(
        config: config,
        notetypes: collection.notetypes,
        notes: collection.notes,
      );
      pipelineSw.stop();
      _logTiming('preview: recognition pipeline', pipelineSw, {
        'notetypes': collection.notetypes.length,
        'ai': results.values
            .where((r) => r.source == CardRecognitionSource.ai)
            .length,
      });
      if (!mounted) return;
      setState(() {
        _mappings = {
          for (final e in results.entries)
            e.key: _canonicalizeMapping(e.value.mapping),
        };
        _recognitionResults = results;
        _isAiIdentifying = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _isAiIdentifying = false);
    }
  }

  Future<void> _executeImport() async {
    if (_officialSourceId != null) {
      await _executeOfficialProjectionImport();
      return;
    }
    final collection = _collection;
    final filePath = _filePath;
    final hash = _sourceHash;
    final plan = _plan;
    if (collection == null ||
        filePath == null ||
        hash == null ||
        plan == null) {
      return;
    }

    final totalSw = Stopwatch()..start();
    setState(() {
      _step = 3;
      _cancelRequested = false;
      _progress = 0;
      _progressMessage = AppStrings.ankiPreparingImport;
    });

    final executor = LegacyAnkiImportExecutor(
      database: getIt<CourseDatabase>(),
      srsProvider: context.read<SrsProvider>(),
      reviewHistoryDao: getIt<ReviewHistoryDao>(),
      mistakeProvider: getIt<MistakeProvider>(),
      audioController: getIt<AudioController>(),
    );
    try {
      final courseProvider = context.read<CourseProvider>();
      final result = await executor.execute(
        LegacyAnkiImportRequest(
          collection: collection,
          filePath: filePath,
          sourceHash: hash,
          plan: plan,
          strategy: _strategy,
          mappingOverrides: Map<int, NotetypeMapping>.unmodifiable(_mappings),
          smartGrouping: _smartGrouping,
          sectionBetaGrouping: _sectionBeta,
          liteThreshold: context.read<SettingsProvider>().ankiLiteThreshold,
          importLearningProgress: _importLearningProgress,
          dailyNewLimit: getIt<AnkiDeckManager>().dailyNewLimit,
          isSample: _isSample,
          previous: _existingImport,
          isCancelled: () => _cancelRequested,
          onProgress: (stage, progress, detail) {
            if (!mounted) return;
            setState(() {
              _progress = progress;
              _progressMessage = detail.isNotEmpty
                  ? detail
                  : switch (stage) {
                      LegacyAnkiImportStage.copyingMedia =>
                        AppStrings.ankiCopyingMedia,
                      LegacyAnkiImportStage.assemblingCourse =>
                        AppStrings.ankiAssemblingCourse,
                      LegacyAnkiImportStage.migratingSrs =>
                        AppStrings.ankiMigratingSrs,
                      LegacyAnkiImportStage.savingMetadata =>
                        AppStrings.ankiSavingMetadata,
                    };
            });
          },
        ),
      );
      if (!mounted) return;

      if (!result.noOp) {
        CourseLoader.invalidateCaches();
        await courseProvider.reloadCourse();
        final newWire = _wireForImportId(result.importId, courseProvider);
        if (newWire != null) {
          final wires = [
            for (final entry in courseProvider.catalogEntries) entry.wireKey,
          ];
          if (!wires.contains(newWire)) {
            wires.add(newWire);
            await courseProvider.persistCourseOrder(wires);
          }
        }
      }
      if (!mounted) return;
      setState(() {
        _summary = result.summary;
        _step = 4;
      });
      unawaited(_persistRecognizedRules());
    } on AnkiImportCancelled {
      if (!mounted) return;
      setState(() {
        _step = 2;
        _progress = 0;
        _progressMessage = '';
      });
    } on OfficialAnkiException catch (error) {
      if (!mounted) return;
      setState(() {
        _error = _mapOfficialErrorToHuman(error);
        _step = 2;
        _progress = 0;
        _progressMessage = '';
      });
    } catch (error) {
      debugPrint('[AnkiImport] import failed: $error');
      if (!mounted) return;
      setState(() {
        _error = AppStrings.ankiImportFailed(error);
        _step = 2;
        _progress = 0;
        _progressMessage = '';
      });
    } finally {
      totalSw.stop();
      _logTiming('import: total', totalSw, {
        'cards': collection.cards.length,
        'strategy': _strategy.name,
      });
    }
  }

  /// Persist the notetype rules for mappings the user accepted on import:
  /// AI verdicts and already-persisted rules (explicit edits are saved in
  /// [_editNotetypeMapping]). Fallback results are never persisted — they
  /// carry no confirmed signal.
  Future<void> _persistRecognizedRules() async {
    final collection = _collection;
    if (collection == null || _recognitionResults.isEmpty) return;
    final store = AnkiNotetypeRuleStore();
    for (final entry in _recognitionResults.entries) {
      final notetype = collection.notetypes[entry.key];
      if (notetype == null) continue;
      final source = entry.value.source;
      if (source != CardRecognitionSource.ai &&
          source != CardRecognitionSource.persisted) {
        continue;
      }
      await store.save(
        NotetypeSignature.of(
          notetype,
          version: CardRecognitionPipeline.recognizerVersion,
        ).value,
        _mappings[entry.key] ?? entry.value.mapping,
      );
    }
  }

  static const _officialFirst = OfficialAnkiOfficialFirstService();

  // ─── P5F-2: official-first flow (saga → schema preview → projection) ──

  /// Official-first entry: saga + migration link + projection preview.
  /// No Dart apkg parse happens on this path.
  Future<void> _runOfficialFirstFlow(String path) async {
    setState(() => _progressMessage = AppStrings.ankiImportingOfficialFirst);
    try {
      final plan = _plan;
      if (plan == null || !plan.isOfficialFirst) {
        throw OfficialAnkiException(
          code: OfficialAnkiErrorCode.invalidState,
          messageKey: 'official_anki.flag_fail_closed',
          debugDetails: plan?.reason ?? 'import_plan_missing',
        );
      }
      final preview = await _officialFirst.importThenPreview(
        filePath: path,
        plan: plan,
        course: getIt<CourseDatabase>(),
      );
      if (!mounted) return;
      setState(() {
        _officialSourceId = preview.sourceId;
        _officialSourceHash = preview.sourceHash;
        _officialCardCount = preview.cardCount;
        _officialNoteCount = preview.noteCount;
        _officialDecks = preview.decks;
        _officialSchemas = preview.schemas;
        _officialSuggestions = preview.suggestions;
        _officialConfirmedNotetypes = {};
        _officialSkippedNotetypes = {};
        _officialService = preview.service;
        _officialNeedsMapping = false;
        _showAllOfficialRecognition = false;
        _step = 2;
        _progress = 0;
        _progressMessage = '';
      });
    } on OfficialAnkiException catch (e) {
      if (!mounted) return;
      setState(() {
        _error = _mapOfficialErrorToHuman(e);
        _step = 0;
        _progressMessage = '';
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = _mapGeneralErrorToHuman(e);
        _step = 0;
        _progressMessage = '';
      });
    }
  }

  /// Projection-based preview: deck list from the official collection,
  /// per-notetype mapping confirmation, and the dedupe hint instead of the
  /// four legacy collision strategies (same-hash re-imports no-op in the
  /// saga).
  _RecognitionAttention _officialRecognitionAttention(
    OfficialAnkiProjectionSchema schema,
  ) {
    final id = schema.notetypeId;
    if (_officialSkippedNotetypes.contains(id)) {
      return _RecognitionAttention.skipped;
    }
    final suggestion = _officialSuggestions[id];
    if (suggestion == null) return _RecognitionAttention.blocking;
    final conflict =
        OfficialAnkiProjectionMapper().mappingConflict(suggestion) != null;
    final missingTarget =
        suggestion.role(OfficialAnkiFieldRole.targetText) == null;
    final missingAnswer = !suggestion.singleFieldMode &&
        suggestion.role(OfficialAnkiFieldRole.nativeText) == null;
    if (conflict ||
        missingTarget ||
        missingAnswer ||
        suggestion.status == OfficialAnkiMappingStatus.needsMapping) {
      return _RecognitionAttention.blocking;
    }
    if (_officialConfirmedNotetypes.contains(id)) {
      return _RecognitionAttention.recognized;
    }
    if (suggestion.status == OfficialAnkiMappingStatus.needsConfirm ||
        suggestion.status == OfficialAnkiMappingStatus.needsReview) {
      return _RecognitionAttention.advisory;
    }
    return _RecognitionAttention.recognized;
  }

  bool get _hasOfficialBlockingRecognition => _officialSchemas.any(
        (schema) =>
            _officialRecognitionAttention(schema) ==
            _RecognitionAttention.blocking,
      );

  Widget _buildOfficialPreviewStep() {
    final schemas = _officialSchemas;
    final attention = {
      for (final schema in schemas)
        schema.notetypeId: _officialRecognitionAttention(schema),
    };
    final blocking = attention.values
        .where((value) => value == _RecognitionAttention.blocking)
        .length;
    final advisory = attention.values
        .where((value) => value == _RecognitionAttention.advisory)
        .length;
    final issues = schemas
        .where((schema) =>
            attention[schema.notetypeId] == _RecognitionAttention.blocking ||
            attention[schema.notetypeId] == _RecognitionAttention.advisory)
        .toList();
    final shownSchemas = _showAllOfficialRecognition ? schemas : issues;
    final statusColor = blocking > 0
        ? TurnaTheme.error
        : advisory > 0
            ? TurnaTheme.warning
            : TurnaTheme.brandTeal;
    return Column(
      children: [
        Expanded(
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Text(
                    _error!,
                    style: const TextStyle(color: TurnaTheme.error),
                  ),
                ),
              if (_officialNeedsMapping)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Text(
                    AppStrings.ankiOfficialNeedsMapping,
                    style: const TextStyle(color: TurnaTheme.error),
                  ),
                ),
              _SectionCard(
                icon: Icons.layers_rounded,
                title: AppStrings.ankiPreviewSectionContent,
                hint: AppStrings.ankiOfficialPreviewBody,
                children: [
                  _StatStrip(
                    items: [
                      (AppStrings.ankiDecksLabel, _officialDecks.length),
                      (AppStrings.ankiNotesLabel, _officialNoteCount),
                      (AppStrings.ankiCardsLabel, _officialCardCount),
                    ],
                  ),
                  if (_officialDecks.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    const _Subheader(text: '牌组结构'),
                    const SizedBox(height: 4),
                    for (final deck in _officialDecks)
                      _InfoRow(
                        deck.name,
                        AppStrings.ankiDeckCardCount(
                          deck.newCount + deck.learnCount + deck.reviewCount,
                        ),
                      ),
                  ],
                  const SizedBox(height: 12),
                  Text(
                    AppStrings.ankiOfficialDedupeHint,
                    style: TextStyle(
                      fontSize: 12,
                      color: TurnaTheme.textSecondaryColor(context),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              _SectionCard(
                icon: Icons.category_rounded,
                title: AppStrings.ankiPreviewSectionMapping,
                hint: AppStrings.ankiOfficialMappingHint,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(
                        blocking > 0
                            ? Icons.error_outline_rounded
                            : advisory > 0
                                ? Icons.help_outline_rounded
                                : Icons.check_circle_outline_rounded,
                        size: 20,
                        color: statusColor,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          blocking > 0
                              ? AppStrings.ankiMappingSummaryBlocking(blocking)
                              : advisory > 0
                                  ? AppStrings.ankiMappingSummaryNeedsCheck(
                                      schemas.length - advisory, advisory)
                                  : AppStrings.ankiMappingSummaryAll(
                                      schemas.length),
                          style: TextStyle(
                            color: statusColor,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      TextButton(
                        onPressed: () => setState(() =>
                            _showAllOfficialRecognition =
                                !_showAllOfficialRecognition),
                        child: Text(
                          _showAllOfficialRecognition
                              ? AppStrings.commonCollapse
                              : AppStrings.ankiMappingViewAll,
                        ),
                      ),
                    ],
                  ),
                  if (shownSchemas.isNotEmpty) const SizedBox(height: 6),
                  for (final schema in shownSchemas)
                    Builder(builder: (context) {
                      final level = attention[schema.notetypeId]!;
                      final rowColor = switch (level) {
                        _RecognitionAttention.blocking => TurnaTheme.error,
                        _RecognitionAttention.advisory => TurnaTheme.warning,
                        _RecognitionAttention.recognized =>
                          TurnaTheme.brandTeal,
                        _RecognitionAttention.skipped =>
                          TurnaTheme.textHintColor(context),
                      };
                      final statusText = switch (level) {
                        _RecognitionAttention.blocking =>
                          AppStrings.ankiMappingMustFix,
                        _RecognitionAttention.advisory =>
                          AppStrings.ankiMappingNeedsCheck,
                        _RecognitionAttention.recognized =>
                          AppStrings.ankiMappingRecognizedAuto,
                        _RecognitionAttention.skipped =>
                          AppStrings.ankiOfficialMappingSkipped,
                      };
                      return ListTile(
                        contentPadding: EdgeInsets.zero,
                        dense: true,
                        title: Text(schema.name),
                        subtitle: Text(
                          statusText,
                          style: TextStyle(color: rowColor, fontSize: 12),
                        ),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              level == _RecognitionAttention.blocking
                                  ? Icons.error_outline_rounded
                                  : level == _RecognitionAttention.advisory
                                      ? Icons.help_outline_rounded
                                      : level == _RecognitionAttention.skipped
                                          ? Icons.skip_next_outlined
                                          : Icons.check_circle_outline_rounded,
                              size: 18,
                              color: rowColor,
                            ),
                            const Icon(Icons.chevron_right, size: 18),
                          ],
                        ),
                        onTap: () => _openOfficialMapping(schema),
                      );
                    }),
                ],
              ),
            ],
          ),
        ),
        _StickyImportBar(
          onPressed: _hasOfficialBlockingRecognition ? null : _executeImport,
          disabledHint: _hasOfficialBlockingRecognition
              ? AppStrings.ankiMappingFixBlocking
              : null,
        ),
      ],
    );
  }

  Future<void> _openOfficialMapping(
    OfficialAnkiProjectionSchema schema,
  ) async {
    final service = _officialService;
    if (service == null) return;
    final suggestion =
        _officialSuggestions[schema.notetypeId] ?? service.suggestFor(schema);
    await context.router.push(
      OfficialAnkiMappingRoute(
        notetypeName: schema.name,
        suggestion: suggestion,
        schema: schema,
        onConfirm: (next) {
          service.confirmMapping(schema: schema, suggestion: next);
          setState(() {
            _officialSuggestions[schema.notetypeId] = next;
            _officialConfirmedNotetypes.add(schema.notetypeId);
            _officialSkippedNotetypes.remove(schema.notetypeId);
            _officialNeedsMapping = false;
          });
        },
        onSkip: () {
          service.skipNotetype(schema: schema);
          setState(() {
            _officialSkippedNotetypes.add(schema.notetypeId);
            _officialConfirmedNotetypes.remove(schema.notetypeId);
          });
        },
      ),
    );
  }

  /// Official-first execution: confirm remaining suggestions (the preview
  /// offered explicit edits), project the course tree from the official
  /// collection, publish placements from the projection index, then promote
  /// the source to a course scope.
  Future<void> _executeOfficialProjectionImport() async {
    final service = _officialService;
    final sourceId = _officialSourceId;
    final sourceHash = _officialSourceHash;
    if (service == null || sourceId == null || sourceHash == null) return;
    if (_hasOfficialBlockingRecognition) {
      setState(() => _officialNeedsMapping = true);
      return;
    }

    setState(() {
      _step = 3;
      _cancelRequested = false;
      _progress = 0;
      _progressMessage = AppStrings.ankiAssemblingCourse;
    });
    try {
      // Proceeding accepts the remaining suggested mappings; skipped
      // notetypes stay skipped.
      for (final schema in _officialSchemas) {
        if (_officialSkippedNotetypes.contains(schema.notetypeId)) continue;
        if (_officialConfirmedNotetypes.contains(schema.notetypeId)) continue;
        final suggestion = _officialSuggestions[schema.notetypeId] ??
            service.suggestFor(schema);
        service.confirmMapping(schema: schema, suggestion: suggestion);
        _officialConfirmedNotetypes.add(schema.notetypeId);
      }

      final result = await _officialFirst.projectAndPublish(
        service: service,
        sourceId: sourceId,
        sourceHash: sourceHash,
      );
      if (result.needsMapping) {
        if (!mounted) return;
        setState(() {
          _officialNeedsMapping = true;
          _step = 2;
          _progress = 0;
          _progressMessage = '';
        });
        return;
      }
      if (result.failed) {
        throw OfficialAnkiException(
          code: OfficialAnkiErrorCode.invalidState,
          messageKey: 'official_anki.projection_failed',
          debugDetails: result.errorCode ?? 'unknown',
        );
      }

      if (!mounted) return;
      final courseProvider = context.read<CourseProvider>();
      CourseLoader.invalidateCaches();
      // Refresh the catalog and stay on the user's current course — the
      // import must never steal the active scope (plan 34 R1-4).
      await courseProvider.reloadCourse();
      final newWire = _wireForImportId(sourceId, courseProvider);
      if (newWire != null) {
        final wires = [
          for (final e in courseProvider.catalogEntries) e.wireKey,
        ];
        if (!wires.contains(newWire)) {
          wires.add(newWire);
          await courseProvider.persistCourseOrder(wires);
        }
      }

      final summary = await OfficialAnkiCourseProjectionStore(
        getIt<CourseDatabase>(),
      ).readOfficialProjectionSummary(sourceId);
      if (!mounted) return;
      setState(() {
        _summary = AnkiImportSummary(
          importId: sourceId,
          sectionCount: summary.sectionIds.length,
          unitCount: 0,
          lessonCount: summary.lessonCount,
          cardCount: result.itemCount,
          wordEntryCount: result.itemCount,
          sourceCardCount: _officialCardCount,
        );
        _step = 4;
        _progress = 0;
        _progressMessage = '';
      });
    } on OfficialAnkiException catch (e) {
      if (!mounted) return;
      setState(() {
        _error = _mapOfficialErrorToHuman(e);
        _step = 2;
        _progress = 0;
        _progressMessage = '';
      });
    } catch (e) {
      debugPrint('[AnkiImport] official-first projection failed: $e');
      if (!mounted) return;
      setState(() {
        _error = AppStrings.ankiImportFailed(e);
        _step = 2;
        _progress = 0;
        _progressMessage = '';
      });
    }
  }

  // ─── Helpers ────────────────────────────────────────────────────────

  String _strategyLabel(BuildContext context, ImportStrategy s) {
    return switch (s) {
      ImportStrategy.merge => AppStrings.ankiStrategyMerge,
      ImportStrategy.skipExisting => AppStrings.ankiStrategySkipExisting,
      ImportStrategy.forceReplace => AppStrings.ankiStrategyForceReplace,
      ImportStrategy.appendAsNew => AppStrings.ankiStrategyAppendAsNew,
    };
  }

  String _strategyDescription(BuildContext context, ImportStrategy s) {
    return switch (s) {
      ImportStrategy.merge => AppStrings.ankiStrategyMergeDesc,
      ImportStrategy.skipExisting => AppStrings.ankiStrategySkipExistingDesc,
      ImportStrategy.forceReplace => AppStrings.ankiStrategyForceReplaceDesc,
      ImportStrategy.appendAsNew => AppStrings.ankiStrategyAppendAsNewDesc,
    };
  }

  /// Data-consequence caption shown beneath each strategy option so users can
  /// tell at a glance which option will preserve vs destroy their existing
  /// review state. Only "force replace" is destructive.
  String _strategyConsequence(ImportStrategy s) {
    return switch (s) {
      ImportStrategy.merge => AppStrings.ankiStrategyMergeConsequence,
      ImportStrategy.skipExisting =>
        AppStrings.ankiStrategySkipExistingConsequence,
      ImportStrategy.forceReplace =>
        AppStrings.ankiStrategyForceReplaceConsequence,
      ImportStrategy.appendAsNew =>
        AppStrings.ankiStrategyAppendAsNewConsequence,
    };
  }
}

// ─── Shared widgets ─────────────────────────────────────────────────

/// Top-of-page step indicator for the 5-step import wizard. Highlights the
/// active step in brand teal and shows completed steps as filled dots so the
/// user always knows where they are in the flow. The parsing/importing
/// loading screens suppress the indicator because the [LinearProgressIndicator]
/// already conveys "something is happening".
class _WizardStepper extends StatelessWidget {
  final int currentStep; // 0..4
  const _WizardStepper({required this.currentStep});

  // Non-const: AppStrings getters aren't const-evaluable, so the list of step
  // labels has to be built at runtime.
  static final _steps = <(String, IconData)>[
    (AppStrings.ankiStepSelect, Icons.upload_file_rounded),
    (AppStrings.ankiStepParse, Icons.manage_search_rounded),
    (AppStrings.ankiStepPreview, Icons.preview_rounded),
    (AppStrings.ankiStepImport, Icons.cloud_download_rounded),
    (AppStrings.ankiStepDone, Icons.check_circle_outline_rounded),
  ];

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 4),
      child: Row(
        children: [
          for (var i = 0; i < _steps.length; i++) ...[
            _StepDot(
              label: _steps[i].$1,
              icon: _steps[i].$2,
              state: i < currentStep
                  ? _StepState.done
                  : i == currentStep
                      ? _StepState.active
                      : _StepState.idle,
            ),
            if (i < _steps.length - 1)
              Expanded(
                child: Container(
                  height: 2,
                  margin: const EdgeInsets.symmetric(horizontal: 4),
                  color: i < currentStep
                      ? TurnaTheme.brandTeal.withValues(alpha: 0.5)
                      : TurnaTheme.textHintColor(context)
                          .withValues(alpha: 0.2),
                ),
              ),
          ],
        ],
      ),
    );
  }
}

enum _StepState { done, active, idle }

class _StepDot extends StatelessWidget {
  final String label;
  final IconData icon;
  final _StepState state;
  const _StepDot({
    required this.label,
    required this.icon,
    required this.state,
  });

  @override
  Widget build(BuildContext context) {
    final color = switch (state) {
      _StepState.done => TurnaTheme.brandTeal,
      _StepState.active => TurnaTheme.brandTeal,
      _StepState.idle => TurnaTheme.textHintColor(context),
    };
    final isActive = state == _StepState.active;
    final isDone = state == _StepState.done;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 32,
          height: 32,
          decoration: BoxDecoration(
            color: isActive || isDone
                ? color.withValues(alpha: 0.12)
                : Colors.transparent,
            border: Border.all(color: color, width: 1.5),
            shape: BoxShape.circle,
          ),
          alignment: Alignment.center,
          child: isDone
              ? Icon(Icons.check_rounded, size: 16, color: color)
              : Icon(icon, size: 16, color: color),
        ),
        const SizedBox(height: 4),
        Text(
          label,
          style: TextStyle(
            fontSize: 11,
            fontWeight: isActive ? FontWeight.w700 : FontWeight.w400,
            color: color,
          ),
        ),
      ],
    );
  }
}

/// Section card with an icon, title, and supporting hint. Replaces the
/// stack of equal-weight [_InfoCard]s on the preview screen so the user
/// sees three clear groups (content / mapping / strategy) instead of a
/// flat list of seven.
class _SectionCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String hint;
  final List<Widget> children;

  const _SectionCard({
    required this.icon,
    required this.title,
    required this.hint,
    required this.children,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: TurnaTheme.cardBg(context),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(TurnaTheme.radiusLarge),
        side: BorderSide(
          color: TurnaTheme.brandTeal.withValues(alpha: 0.12),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 10),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.all(7),
                  decoration: BoxDecoration(
                    color: TurnaTheme.brandTeal.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(TurnaTheme.radiusSmall),
                  ),
                  child: Icon(icon, color: TurnaTheme.brandTeal, size: 18),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        hint,
                        style: TextStyle(
                          fontSize: 12,
                          color: TurnaTheme.textSecondaryColor(context),
                          height: 1.3,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          Divider(
            height: 1,
            thickness: 1,
            color: TurnaTheme.brandTeal.withValues(alpha: 0.08),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 10, 14, 14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: children,
            ),
          ),
        ],
      ),
    );
  }
}

/// Small uppercase-ish label used as an in-card subheader (e.g. "牌组结构").
class _Subheader extends StatelessWidget {
  final String text;
  const _Subheader({required this.text});

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: TextStyle(
        fontSize: 12,
        fontWeight: FontWeight.w700,
        color: TurnaTheme.textHintColor(context),
        letterSpacing: 0.3,
      ),
    );
  }
}

/// 4-up compact stat row for the content section. Avoids stacking the
/// 牌组/笔记/卡片/媒体 counts as four separate rows that all look the same.
class _StatStrip extends StatelessWidget {
  final List<(String, int)> items;
  const _StatStrip({required this.items});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        for (var i = 0; i < items.length; i++) ...[
          Expanded(
            child: _StatChip(label: items[i].$1, value: items[i].$2),
          ),
          if (i < items.length - 1) const SizedBox(width: 6),
        ],
      ],
    );
  }
}

class _StatChip extends StatelessWidget {
  final String label;
  final int value;
  const _StatChip({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
      decoration: BoxDecoration(
        color: TurnaTheme.brandTeal.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(TurnaTheme.radiusMedium),
        border: Border.all(
          color: TurnaTheme.brandTeal.withValues(alpha: 0.12),
        ),
      ),
      child: Column(
        children: [
          Text(
            '$value',
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w800,
              color: TurnaTheme.brandTeal,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: TextStyle(
              fontSize: 11,
              color: TurnaTheme.textSecondaryColor(context),
            ),
            textAlign: TextAlign.center,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }
}

/// Compact new-vs-existing collision summary. The thin progress bar lets
/// users see at a glance how much of this import is "new" vs "already in
/// the system" without having to read two separate numbers.
class _CollisionStrip extends StatelessWidget {
  final int newCount;
  final int existingCount;
  const _CollisionStrip({required this.newCount, required this.existingCount});

  @override
  Widget build(BuildContext context) {
    final total = newCount + existingCount;
    final newFraction = total == 0 ? 0.0 : newCount / total;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                AppStrings.ankiNewCards,
                style: TextStyle(
                  fontSize: 13,
                  color: TurnaTheme.textSecondaryColor(context),
                ),
              ),
            ),
            Text(
              '$newCount',
              style: const TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w700,
                color: TurnaTheme.brandTeal,
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Text(
                AppStrings.ankiExistingCards,
                style: TextStyle(
                  fontSize: 13,
                  color: TurnaTheme.textSecondaryColor(context),
                ),
              ),
            ),
            Text(
              '$existingCount',
              style: const TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: SizedBox(
            height: 6,
            child: Row(
              children: [
                Expanded(
                  flex: (newFraction * 1000).round().clamp(0, 1000),
                  child: Container(color: TurnaTheme.brandTeal),
                ),
                Expanded(
                  flex: ((1 - newFraction) * 1000).round().clamp(0, 1000),
                  child: Container(
                    color: TurnaTheme.textHintColor(context)
                        .withValues(alpha: 0.3),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

/// One strategy radio row. The "consequence" line is the key new affordance:
/// it tells the user the data impact of choosing this option without
/// forcing them to tap a tooltip. Force-replace is the only destructive
/// option and is highlighted in red.
class _StrategyOption extends StatelessWidget {
  final ImportStrategy value;
  final ImportStrategy groupValue;
  final String title;
  final String description;
  final String consequence;
  final bool isWarning;
  final ValueChanged<ImportStrategy> onChanged;

  const _StrategyOption({
    required this.value,
    required this.groupValue,
    required this.title,
    required this.description,
    required this.consequence,
    required this.isWarning,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final selected = value == groupValue;
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(TurnaTheme.radiusMedium),
      child: InkWell(
        onTap: () => onChanged(value),
        borderRadius: BorderRadius.circular(TurnaTheme.radiusMedium),
        child: Container(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
          decoration: BoxDecoration(
            color: selected
                ? TurnaTheme.brandTeal.withValues(alpha: 0.08)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(TurnaTheme.radiusMedium),
            border: Border.all(
              color: selected
                  ? TurnaTheme.brandTeal
                  : TurnaTheme.textHintColor(context).withValues(alpha: 0.25),
              width: selected ? 1.5 : 1,
            ),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.only(top: 1),
                child: SizedBox(
                  width: 20,
                  height: 20,
                  child: Radio<ImportStrategy>(
                    value: value,
                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    visualDensity: VisualDensity.compact,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      description,
                      style: TextStyle(
                        fontSize: 12,
                        color: TurnaTheme.textSecondaryColor(context),
                        height: 1.4,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        Icon(
                          isWarning
                              ? Icons.warning_amber_rounded
                              : Icons.check_circle_outline,
                          size: 13,
                          color: isWarning
                              ? TurnaTheme.error
                              : TurnaTheme.textHintColor(context),
                        ),
                        const SizedBox(width: 4),
                        Expanded(
                          child: Text(
                            consequence,
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: isWarning
                                  ? TurnaTheme.error
                                  : TurnaTheme.textHintColor(context),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Bottom-anchored primary action bar on the preview step. Kept sticky so
/// users do not have to scroll back to the bottom of the long preview page
/// after adjusting strategy / learning-progress settings.
class _StickyImportBar extends StatelessWidget {
  final VoidCallback? onPressed;
  final String? disabledHint;
  const _StickyImportBar({required this.onPressed, this.disabledHint});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: TurnaTheme.cardBg(context),
        border: Border(
          top: BorderSide(
            color: TurnaTheme.brandTeal.withValues(alpha: 0.18),
          ),
        ),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 10, 20, 10),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (disabledHint != null) ...[
                Text(
                  disabledHint!,
                  style: const TextStyle(
                    color: TurnaTheme.error,
                    fontSize: 12,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 6),
              ],
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: onPressed,
                  icon: const Icon(Icons.cloud_download_rounded, size: 20),
                  label: Text(
                    AppStrings.ankiPreviewStartImport,
                    style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 16,
                    ),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: TurnaTheme.brandTeal,
                    foregroundColor: TurnaTheme.textOnPrimary,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Grouped detail block on the done step. Collapses "源数据 / 词汇 / 状态"
/// into one card with a subheader, so a clean import does not look like
/// a wall of identical one-line texts.
class _DoneGroup extends StatelessWidget {
  final String title;
  final List<String> rows;
  const _DoneGroup({required this.title, required this.rows});

  @override
  Widget build(BuildContext context) {
    if (rows.isEmpty) return const SizedBox.shrink();
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: BoxDecoration(
        color: TurnaTheme.cardBg(context),
        borderRadius: BorderRadius.circular(TurnaTheme.radiusLarge),
        border: Border.all(
          color: TurnaTheme.brandTeal.withValues(alpha: 0.1),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: TurnaTheme.textHintColor(context),
              letterSpacing: 0.3,
            ),
          ),
          const SizedBox(height: 8),
          for (final row in rows)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 3),
              child: Text(
                row,
                style: TextStyle(
                  fontSize: 13,
                  color: TurnaTheme.textSecondaryColor(context),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Single-line learning-progress summary on the done step. Distinguishes
/// "kept" (with optional sub-stats) from "reset" so the user can confirm
/// the import honored the choice they made on the preview step.
class _LearningProgressBadge extends StatelessWidget {
  final bool kept;
  final bool hasScheduling;
  final bool hasReviewHistory;
  const _LearningProgressBadge({
    required this.kept,
    required this.hasScheduling,
    required this.hasReviewHistory,
  });

  @override
  Widget build(BuildContext context) {
    if (!kept) {
      return _Badge(
        icon: Icons.restart_alt_rounded,
        color: TurnaTheme.textSecondaryColor(context),
        text: AppStrings.ankiDoneProgressReset,
      );
    }
    if (!hasScheduling && !hasReviewHistory) {
      return _Badge(
        icon: Icons.check_circle_outline,
        color: TurnaTheme.textHintColor(context),
        text: '已导入',
      );
    }
    return Row(
      children: [
        Expanded(
          child: _Badge(
            icon: Icons.check_circle_outline,
            color: TurnaTheme.brandTeal,
            text: AppStrings.ankiDoneProgressKept,
          ),
        ),
      ],
    );
  }
}

class _Badge extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String text;
  const _Badge({required this.icon, required this.color, required this.text});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(TurnaTheme.radiusMedium),
        border: Border.all(color: color.withValues(alpha: 0.25)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 6),
          Text(
            text,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  final String label;
  final String value;

  const _InfoRow(this.label, this.value);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Wrap both halves in Flexible so the row can shrink and the value
          // ellipsizes instead of overflowing the card on narrow screens.
          Flexible(
            child: Text(
              label,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: TurnaTheme.textSecondaryColor(context),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Flexible(
            child: Text(
              value,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.end,
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }
}

/// Canonical types shown in the import mapping editor. Legacy aliases
/// ([NotetypeMappingType.multiSelect], [NotetypeMappingType.typeAnswer]) are
/// omitted so the dropdown never lists two identical labels.
const List<NotetypeMappingType> _userSelectableMappingTypes = [
  NotetypeMappingType.ankiCard,
  NotetypeMappingType.wordEntry,
  NotetypeMappingType.expression,
  NotetypeMappingType.cloze,
  NotetypeMappingType.multipleChoice,
  NotetypeMappingType.fillBlank,
  NotetypeMappingType.listenPick,
];

/// Collapse legacy aliases so dropdown [initialValue] always matches an item.
NotetypeMappingType _canonicalizeMappingType(NotetypeMappingType type) {
  switch (type) {
    case NotetypeMappingType.multiSelect:
      return NotetypeMappingType.multipleChoice;
    case NotetypeMappingType.typeAnswer:
      return NotetypeMappingType.fillBlank;
    case NotetypeMappingType.ankiCard:
    case NotetypeMappingType.wordEntry:
    case NotetypeMappingType.expression:
    case NotetypeMappingType.cloze:
    case NotetypeMappingType.multipleChoice:
    case NotetypeMappingType.fillBlank:
    case NotetypeMappingType.listenPick:
      return type;
  }
}

/// Rewrite legacy type aliases on a [NotetypeMapping] (no field clamping).
NotetypeMapping _canonicalizeMapping(NotetypeMapping m) {
  final canonical = _canonicalizeMappingType(m.type);
  return canonical == m.type ? m : m.copyWith(type: canonical);
}

bool _mappingUsesFrontBackFields(NotetypeMappingType type) {
  switch (_canonicalizeMappingType(type)) {
    case NotetypeMappingType.ankiCard:
    case NotetypeMappingType.wordEntry:
    case NotetypeMappingType.expression:
    case NotetypeMappingType.fillBlank:
    case NotetypeMappingType.typeAnswer:
    case NotetypeMappingType.listenPick:
      return true;
    case NotetypeMappingType.cloze:
    case NotetypeMappingType.multipleChoice:
    case NotetypeMappingType.multiSelect:
      return false;
  }
}

/// Human-readable label for the automatic layout classification shown in the
/// import preview and sample-card dialog.
String _mappingTypeLabel(NotetypeMappingType type) {
  switch (_canonicalizeMappingType(type)) {
    case NotetypeMappingType.ankiCard:
      return AppStrings.ankiMappingTypeAnkiCard;
    case NotetypeMappingType.wordEntry:
      return AppStrings.ankiMappingTypeWordEntry;
    case NotetypeMappingType.expression:
      return AppStrings.ankiMappingTypeExpression;
    case NotetypeMappingType.cloze:
      return AppStrings.ankiMappingTypeCloze;
    case NotetypeMappingType.multipleChoice:
    case NotetypeMappingType.multiSelect:
      return AppStrings.ankiMappingTypeAutoChoice;
    case NotetypeMappingType.fillBlank:
    case NotetypeMappingType.typeAnswer:
      return AppStrings.ankiMappingTypeFillBlank;
    case NotetypeMappingType.listenPick:
      return AppStrings.ankiMappingTypeListenPick;
  }
}

/// One automatic notetype-mapping row. Tapping the row (or its trailing
/// edit icon) opens [_NotetypeMappingEditor] so the user can override the
/// auto-detected type and front/back fields.
class _NotetypeMappingRow extends StatelessWidget {
  final AnkiNotetype notetype;
  final NotetypeMapping? mapping;
  final CardRecognitionResult? recognition;
  final _RecognitionAttention attention;
  final VoidCallback onEdit;

  const _NotetypeMappingRow({
    required this.notetype,
    required this.mapping,
    required this.attention,
    required this.onEdit,
    this.recognition,
  });

  @override
  Widget build(BuildContext context) {
    final color = switch (attention) {
      _RecognitionAttention.blocking => TurnaTheme.error,
      _RecognitionAttention.advisory => TurnaTheme.warning,
      _RecognitionAttention.recognized => TurnaTheme.brandTeal,
      _RecognitionAttention.skipped => TurnaTheme.textHintColor(context),
    };
    final status = switch (attention) {
      _RecognitionAttention.blocking => AppStrings.ankiMappingMustFix,
      _RecognitionAttention.advisory => AppStrings.ankiMappingNeedsCheck,
      _RecognitionAttention.recognized => AppStrings.ankiMappingRecognizedAuto,
      _RecognitionAttention.skipped => AppStrings.ankiOfficialMappingSkipped,
    };
    final warnings = recognition?.warnings ?? const <String>[];
    final detail = warnings.isEmpty ? null : warnings.first;
    return Material(
      color: Colors.transparent,
      child: ListTile(
        contentPadding: EdgeInsets.zero,
        dense: true,
        onTap: onEdit,
        title: Text(
          notetype.name,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
        subtitle: Text(
          detail != null && attention != _RecognitionAttention.recognized
              ? '${_mappingTypeLabel(mapping?.type ?? NotetypeMappingType.ankiCard)} · $detail'
              : _mappingTypeLabel(
                  mapping?.type ?? NotetypeMappingType.ankiCard,
                ),
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              attention == _RecognitionAttention.blocking
                  ? Icons.error_outline_rounded
                  : attention == _RecognitionAttention.advisory
                      ? Icons.help_outline_rounded
                      : Icons.check_circle_outline_rounded,
              color: color,
              size: 17,
            ),
            const SizedBox(width: 4),
            Text(
              status,
              style: TextStyle(
                color: color,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(width: 2),
            const Icon(Icons.chevron_right, size: 18),
          ],
        ),
      ),
    );
  }
}

/// Editable notetype-mapping dialog for one notetype. Lets the user override
/// the auto-detected card type and the front/back field indices, with a live
/// sample preview (first note of that mid). Returns the edited
/// [NotetypeMapping] via [Navigator.pop] when saved, or `null` when cancelled
/// / dismissed - the caller decides whether to apply the change.
class _NotetypeMappingEditor extends StatefulWidget {
  final AnkiNotetype notetype;
  final AnkiNote? note;
  final NotetypeMapping? initialMapping;

  const _NotetypeMappingEditor({
    required this.notetype,
    required this.note,
    required this.initialMapping,
  });

  @override
  State<_NotetypeMappingEditor> createState() => _NotetypeMappingEditorState();
}

class _NotetypeMappingEditorState extends State<_NotetypeMappingEditor> {
  late NotetypeMapping _draft;

  @override
  void initState() {
    super.initState();
    _draft = _normalizeMapping(
      widget.initialMapping ?? AnkiCardAdapter.inferMapping(widget.notetype),
    );
  }

  /// Clamp field indices and collapse legacy type aliases so the dropdown
  /// value is always one of [_userSelectableMappingTypes].
  NotetypeMapping _normalizeMapping(NotetypeMapping m) {
    final canonical = _canonicalizeMappingType(m.type);
    final next = canonical == m.type ? m : m.copyWith(type: canonical);
    return _clampFields(next);
  }

  /// Clamp front/back indices to the notetype's actual field range so the
  /// dropdowns always have a valid selection (a 1-field notetype would
  /// otherwise keep the default backFieldIndex=1).
  NotetypeMapping _clampFields(NotetypeMapping m) {
    final n = widget.notetype.fieldNames.length;
    if (n == 0) return m;
    final maxIdx = n - 1;
    final front = m.frontFieldIndex.clamp(0, maxIdx);
    final back = m.backFieldIndex.clamp(0, maxIdx);
    if (front == m.frontFieldIndex && back == m.backFieldIndex) return m;
    return m.copyWith(frontFieldIndex: front, backFieldIndex: back);
  }

  /// Whether the mapping type relies on user-selected front/back fields.
  /// Cloze and choice types resolve their fields per-card at adapt time, so
  /// exposing manual field selectors there would be misleading.
  bool _typeUsesFrontBackFields(NotetypeMappingType t) {
    return _mappingUsesFrontBackFields(t);
  }

  void _swapFields() {
    setState(() {
      _draft = _draft.copyWith(
        frontFieldIndex: _draft.backFieldIndex,
        backFieldIndex: _draft.frontFieldIndex,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final fields = widget.notetype.fieldNames;
    final showFields =
        _typeUsesFrontBackFields(_draft.type) && fields.isNotEmpty;
    final noteFields = widget.note?.fields ?? const <String>[];
    String fieldValue(int idx) => (idx >= 0 && idx < noteFields.length)
        ? AnkiCardAdapter.stripHtmlPublic(noteFields[idx])
        : '-';

    return AlertDialog(
      title: Text(AppStrings.ankiMappingEditTitle),
      content: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              widget.notetype.name,
              style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
            ),
            const SizedBox(height: 12),
            if (widget.note == null)
              Text(
                '-',
                style: TextStyle(color: TurnaTheme.textHintColor(context)),
              )
            else ...[
              _PreviewField(
                label: AppStrings.ankiNotetypeSampleFront,
                value: fieldValue(_draft.frontFieldIndex),
              ),
              const SizedBox(height: 8),
              _PreviewField(
                label: AppStrings.ankiNotetypeSampleBack,
                value: fieldValue(_draft.backFieldIndex),
              ),
            ],
            if (showFields && fields.length > 1) ...[
              const SizedBox(height: 10),
              Align(
                alignment: Alignment.center,
                child: OutlinedButton.icon(
                  key: const Key('legacy-mapping-swap'),
                  onPressed: _swapFields,
                  icon: const Icon(Icons.swap_vert_rounded, size: 18),
                  label: Text(AppStrings.ankiMappingSwapSides),
                ),
              ),
            ],
            const SizedBox(height: 8),
            Theme(
              data:
                  Theme.of(context).copyWith(dividerColor: Colors.transparent),
              child: ExpansionTile(
                key: const Key('legacy-mapping-more'),
                tilePadding: EdgeInsets.zero,
                childrenPadding: EdgeInsets.zero,
                title: Text(
                  AppStrings.ankiMappingMoreAdjustments,
                  style: const TextStyle(fontSize: 14),
                ),
                children: [
                  _fieldLabel(context, AppStrings.ankiMappingFieldType),
                  const SizedBox(height: 6),
                  DropdownButtonFormField<NotetypeMappingType>(
                    initialValue: _canonicalizeMappingType(_draft.type),
                    isExpanded: true,
                    decoration: _dropdownDecoration(context),
                    items: [
                      for (final t in _userSelectableMappingTypes)
                        DropdownMenuItem(
                          value: t,
                          child: Text(_mappingTypeLabel(t)),
                        ),
                    ],
                    onChanged: (t) {
                      if (t == null) return;
                      final next = _canonicalizeMappingType(t);
                      if (next == _draft.type) return;
                      setState(() => _draft = _draft.copyWith(type: next));
                    },
                  ),
                  const SizedBox(height: 12),
                  if (showFields) ...[
                    _fieldSelector(
                      context,
                      label: AppStrings.ankiMappingFieldFront,
                      value: _draft.frontFieldIndex,
                      fields: fields,
                      onChanged: (i) => setState(() =>
                          _draft = _draft.copyWith(frontFieldIndex: i ?? 0)),
                    ),
                    const SizedBox(height: 10),
                    _fieldSelector(
                      context,
                      label: AppStrings.ankiMappingFieldBack,
                      value: _draft.backFieldIndex,
                      fields: fields,
                      onChanged: (i) => setState(() =>
                          _draft = _draft.copyWith(backFieldIndex: i ?? 0)),
                    ),
                  ] else
                    _autoFieldsHint(context),
                  if (_draft.reason.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    _ReasonDisclosure(reason: _draft.reason),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () {
            setState(() => _draft = _normalizeMapping(
                  AnkiCardAdapter.inferMapping(widget.notetype),
                ));
          },
          child: Text(AppStrings.ankiMappingResetAuto),
        ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(null),
          child: Text(AppStrings.commonCancel),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(_draft),
          child: Text(AppStrings.ankiMappingConfirmCorrect),
        ),
      ],
    );
  }

  Widget _fieldLabel(BuildContext context, String label) {
    return Text(
      label,
      style: TextStyle(
        fontWeight: FontWeight.w600,
        color: TurnaTheme.textSecondaryColor(context),
      ),
    );
  }

  Widget _fieldSelector(
    BuildContext context, {
    required String label,
    required int value,
    required List<String> fields,
    required ValueChanged<int?> onChanged,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        _fieldLabel(context, label),
        const SizedBox(height: 6),
        DropdownButtonFormField<int>(
          initialValue: value,
          isExpanded: true,
          decoration: _dropdownDecoration(context),
          items: [
            for (var i = 0; i < fields.length; i++)
              DropdownMenuItem(value: i, child: Text(fields[i])),
          ],
          onChanged: onChanged,
        ),
      ],
    );
  }

  Widget _autoFieldsHint(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(
          Icons.info_outline_rounded,
          size: 16,
          color: TurnaTheme.textHintColor(context),
        ),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            AppStrings.ankiMappingFieldsAutoHint,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: TurnaTheme.textHintColor(context),
                ),
          ),
        ),
      ],
    );
  }

  InputDecoration _dropdownDecoration(BuildContext context) {
    return InputDecoration(
      isDense: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      filled: true,
      fillColor: TurnaTheme.tintLight,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(TurnaTheme.radiusMedium),
        borderSide: BorderSide.none,
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(TurnaTheme.radiusMedium),
        borderSide: BorderSide.none,
      ),
    );
  }
}

/// Collapsible "why was it recognized this way" note inside the mapping
/// editor — collapsed by default so the dialog stays simple; the reasoning
/// stays one tap away for users who care.
class _ReasonDisclosure extends StatefulWidget {
  const _ReasonDisclosure({required this.reason});

  final String reason;

  @override
  State<_ReasonDisclosure> createState() => _ReasonDisclosureState();
}

class _ReasonDisclosureState extends State<_ReasonDisclosure> {
  var _expanded = false;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerLeft,
      child: InkWell(
        borderRadius: BorderRadius.circular(TurnaTheme.radiusSmall),
        onTap: () => setState(() => _expanded = !_expanded),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                _expanded ? Icons.expand_less : Icons.lightbulb_outline_rounded,
                size: 16,
                color: TurnaTheme.textSecondaryColor(context),
              ),
              const SizedBox(width: 6),
              Text(
                '${AppStrings.ankiMappingReason}${_expanded ? '' : ' ▾'}',
                style: TextStyle(
                  fontSize: 12,
                  color: TurnaTheme.textSecondaryColor(context),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Collapsed-by-default container for expert knobs (strategy, grouping).
/// The collapsed header shows the current defaults as a one-line summary so
/// casual users can just tap "开始导入" without wading through options.
class _AdvancedOptionsCard extends StatelessWidget {
  const _AdvancedOptionsCard({
    required this.summary,
    required this.children,
  });

  final String summary;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(TurnaTheme.radiusMedium),
        border: Border.all(
          color: TurnaTheme.textHintColor(context).withValues(alpha: 0.2),
        ),
      ),
      child: Theme(
        // Remove ExpansionTile's default hairlines — the card border is the
        // only outline.
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          tilePadding: const EdgeInsets.symmetric(horizontal: 12),
          childrenPadding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
          iconColor: TurnaTheme.brandTeal,
          title: Text(
            AppStrings.ankiAdvancedOptionsTitle,
            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
          ),
          subtitle: Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Text(
              summary,
              style: TextStyle(
                fontSize: 12,
                color: TurnaTheme.textHintColor(context),
              ),
            ),
          ),
          children: children,
        ),
      ),
    );
  }
}

class _PreviewField extends StatelessWidget {
  final String label;
  final String value;

  const _PreviewField({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          label,
          style: TextStyle(
            fontWeight: FontWeight.w600,
            color: TurnaTheme.textSecondaryColor(context),
          ),
        ),
        const SizedBox(height: 2),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: TurnaTheme.inputFillColor(context),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Text(value),
        ),
      ],
    );
  }
}

// Dart imports:
import 'dart:async';
import 'dart:convert';
import 'dart:io';

// Flutter imports:
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

// Package imports:
import 'package:auto_route/auto_route.dart';
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';
import 'package:turna/application/settings_provider.dart';

// Project imports:
import 'package:turna/application/ai/engine/ai_engine_config_holder.dart';
import 'package:turna/application/anki/anki_card_adapter.dart';
import 'package:turna/application/anki/anki_deck_assembler.dart';
import 'package:turna/application/anki/anki_deck_manager.dart';
import 'package:turna/application/anki/anki_importer.dart';
import 'package:turna/application/anki/anki_import_cleanup_service.dart';
import 'package:turna/application/anki_official/contract/official_anki_errors.dart';
import 'package:turna/application/anki_official/engine/official_anki_engine.dart';
import 'package:turna/application/anki_official/import/anki_import_facade.dart';
import 'package:turna/application/anki_official/import/official_anki_import_state.dart';
import 'package:turna/application/anki_official/migration/official_anki_migration_dao.dart';
import 'package:turna/application/anki_official/migration/official_anki_new_import_cutover.dart';
import 'package:turna/application/anki_official/official_anki_composition.dart';
import 'package:turna/application/anki_official/official_anki_feature_flags.dart';
import 'package:turna/application/anki_official/official_anki_ids.dart';
import 'package:turna/application/anki_official/official_anki_paths.dart';
import 'package:turna/application/anki_official/projection/official_anki_projection_service.dart';
import 'package:turna/application/anki_official/storage/official_anki_database.dart';
import 'package:turna/application/anki/anki_models.dart';
import 'package:turna/application/anki/anki_organization_resolver.dart';
import 'package:turna/application/anki/anki_sample_deck.dart';
import 'package:turna/application/anki/anki_notetype_ai.dart';
import 'package:turna/application/anki/anki_srs_migrator.dart';
import 'package:turna/application/anki/unified_anki_import_orchestrator.dart';
import 'package:turna/application/course_provider.dart';
import 'package:turna/application/srs_provider.dart';
import 'package:turna/courses/course_loader.dart';
import 'package:turna/data/anki_import_dao.dart';
import 'package:turna/data/anki_note_dao.dart';
import 'package:turna/data/course_database.dart';
import 'package:turna/data/course_repository.dart';
import 'package:turna/data/review_history_dao.dart';
import 'package:turna/di/injection.dart';
import 'package:turna/domain/audio/anki_audio_resolver.dart';
import 'package:turna/l10n/app_strings.dart';
import 'package:turna/utils/ohos_file_picker.dart';
import 'package:turna/views/theme.dart';

/// Import strategy when collisions are detected.
enum ImportStrategy { merge, skipExisting, forceReplace, appendAsNew }

/// File extensions accepted by the Anki import wizard. Single source of truth
/// shared with [OhosFilePicker.pickFiles] for its suffix filter.
const _ankiExtensions = ['apkg', 'colpkg'];

/// User choice in the fallback bottom sheet.
enum _AnkiFallbackChoice { scan, path }

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

  const AnkiImportPage({super.key, this.startWithSample = false});

  @override
  State<AnkiImportPage> createState() => _AnkiImportPageState();
}

class _AnkiImportPageState extends State<AnkiImportPage> {
  final _importer = AnkiImporter();

  // Wizard state
  int _step = 0; // 0=select, 1=parsing, 2=preview, 3=importing, 4=done
  String? _filePath;
  AnkiCollection? _collection;
  String? _error;
  bool _isSample = false;

  // Preview data
  Map<int, NotetypeMapping> _mappings = {};
  int _newCount = 0;
  int _existingCount = 0;
  ImportStrategy _strategy = ImportStrategy.merge;
  bool _smartGrouping = true;
  bool _importLearningProgress = false;
  // Cached unit/lesson organization summary for the content section. Computed
  // once in [_preparePreview] and read on every preview rebuild so the user
  // does not pay the O(notes) cost each time they flip a strategy switch.
  AnkiOrganizationPreview? _organizationPreview;

  // AI notetype identification (optional; runs LLM over all notetypes).
  bool _isAiIdentifying = false;

  // Incremental-update detection (computed at parse time)
  String? _sourceHash;
  AnkiImportRecord? _existingImport;

  // Progress
  String _progressMessage = '';
  double _progress = 0; // 0..1, 0 means indeterminate
  bool _cancelRequested = false;
  AnkiImportSummary? _summary;

  // ─── Perf instrumentation ──────────────────────────────────────────
  //
  // Set to false to silence every [debugPrint] the import flow emits. Kept
  // on by default during the perf-investigation phase so we can collect real
  // numbers from a 5K+ card file; flip once we have data.
  static const bool _kEnableTimingLogs = true;

  /// Compact, parseable log line for a single timed phase. Format is
  /// `[AnkiImport] <label>: <ms>ms (<key>=<value> ...)` so the lines can be
  /// grepped or piped into a quick spreadsheet without parsing JSON.
  void _logTiming(String label, Stopwatch sw,
      [Map<String, Object?>? extras]) {
    if (!_kEnableTimingLogs) return;
    final buf = StringBuffer('[AnkiImport] $label: ${sw.elapsedMilliseconds}ms');
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
        return _buildPreviewStep();
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
    // (instead of overflowing with a yellow "BOTTOM OVERFLOWED" stripe) when
    // the IME or a small viewport reduces the available height. Without this,
    // opening "输入文件路径" on HarmonyOS pushed the bottom buttons off-screen
    // by ~158 px on the narrow phones we target.
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
                    // Always-available fallback so users on platforms with a
                    // broken system picker (e.g. some OHOS ROMs) have a way in
                    // before they hit an error. Cheap, low visual weight.
                    TextButton.icon(
                      onPressed: _showScanResults,
                      icon: const Icon(Icons.search, size: 18),
                      label: Text(AppStrings.ankiImportFallbackScanHint),
                      style: TextButton.styleFrom(
                        foregroundColor: TurnaTheme.brandTeal,
                      ),
                    ),
                    const SizedBox(height: 24),
                    // Sample-deck entry: a visually distinct card so it does
                    // not compete with the primary CTA but is still obvious.
                    _SampleDeckCard(onTap: _loadSampleDeck),
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
              _buildStrategySection(),
            ],
          ),
        ),
        _StickyImportBar(onPressed: _executeImport),
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
        const SizedBox(height: 12),
        _buildOrganizationBlock(),
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
      ],
    );
  }

  /// Section 2: how each card type is identified. The notetype mapping
  /// override list plus the optional AI re-identification button.
  Widget _buildMappingSection(AnkiCollection collection) {
    return _SectionCard(
      icon: Icons.auto_awesome_outlined,
      title: AppStrings.ankiPreviewSectionMapping,
      hint: AppStrings.ankiPreviewSectionMappingHint,
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Text(
            AppStrings.ankiMappingOverrideHint,
            style: TextStyle(
              fontSize: 12,
              color: TurnaTheme.textHintColor(context),
            ),
          ),
        ),
        for (final entry in collection.notetypes.entries)
          _NotetypeMappingRow(
            notetype: entry.value,
            mapping: _mappings[entry.key],
            onEdit: () => _editNotetypeMapping(entry.key, entry.value),
          ),
        if (collection.notetypes.isNotEmpty) ...[
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
            decoration: BoxDecoration(
              color: TurnaTheme.brandTeal.withValues(alpha: 0.04),
              borderRadius: BorderRadius.circular(TurnaTheme.radiusSmall),
              border: Border.all(
                color: TurnaTheme.brandTeal.withValues(alpha: 0.12),
              ),
            ),
            child: Row(
              children: [
                Icon(
                  Icons.lightbulb_outline,
                  size: 16,
                  color: TurnaTheme.textSecondaryColor(context),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    AppStrings.ankiMappingAutoChoiceHint,
                    style: TextStyle(
                      fontSize: 12,
                      color: TurnaTheme.textSecondaryColor(context),
                    ),
                  ),
                ),
              ],
            ),
          ),
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
                  : AppStrings.ankiAiIdentify,
            ),
            style: OutlinedButton.styleFrom(
              foregroundColor: TurnaTheme.brandTeal,
              side: const BorderSide(color: TurnaTheme.brandTeal),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            AppStrings.ankiAiIdentifyHint,
            style: TextStyle(
              fontSize: 11,
              color: TurnaTheme.textHintColor(context),
            ),
          ),
        ],
      ],
    );
  }

  /// Section 3: how collisions and learning progress are handled.
  Widget _buildStrategySection() {
    return _SectionCard(
      icon: Icons.tune_rounded,
      title: AppStrings.ankiPreviewSectionStrategy,
      hint: AppStrings.ankiPreviewSectionStrategyHint,
      children: [
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
                style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
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
                  AppStrings.ankiImportFidelityCards(
                      summary.fidelityCardCount),
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
                          summary.missingMediaCount +
                              summary.failedMediaCount),
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
            // Secondary action: return to the deck list (the page that
            // pushed this wizard onto the stack). Same destination as the
            // "Done" text button, but more discoverable for users who
            // explicitly want to review what was imported.
            OutlinedButton.icon(
              onPressed: () => context.router.maybePop(),
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

  /// "Start learning now" on the done step: scope the course tree to the
  /// freshly-imported deck and pop back to the Learn tab, so the deck is
  /// immediately usable like a real course.
  Future<void> _startLearningNow() async {
    final importId = _summary?.importId;
    if (importId != null) {
      await context.read<CourseProvider>().setCourseScope('anki:$importId');
    }
    if (mounted) context.router.maybePop();
  }

  Future<void> _pickFile() async {
    try {
      // OhosFilePicker honors allowedExtensions as a suffix filter on every
      // platform and throws OhosFilePickerInvalidExtension when the user picks
      // a non-matching file, so the extension set lives in one place.
      final result = await OhosFilePicker.pickFiles(
        allowedExtensions: _ankiExtensions,
        dialogTitle: AppStrings.ankiImportDialogTitle,
      );

      if (result == null || result.files.isEmpty) return;
      final path = result.files.single.path;
      if (path == null) return;

      setState(() {
        _filePath = path;
        _error = null;
        _step = 1;
      });

      await _parseFile(path);
    } on OhosFilePickerInvalidExtension {
      setState(() => _error = AppStrings.ankiPickFileError);
    } catch (e) {
      setState(() {
        _error = AppStrings.ankiPickFileFailed(e);
        _step = 0;
      });
      // On OHos, picker failures are usually device-level (missing
      // pickersheet). Offer the manual fallbacks so the user isn't stuck.
      if (defaultTargetPlatform.name == 'ohos') {
        await _showFallbackSheet();
      }
    }
  }

  /// Show a bottom sheet with two fallback flows: scan well-known
  /// directories, or accept a manually-pasted path. Used when the system
  /// file picker failed (e.g. trimmed emulator ROMs).
  Future<void> _showFallbackSheet() async {
    if (!mounted) return;
    final choice = await showModalBottomSheet<_AnkiFallbackChoice>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 12),
              child: Text(
                AppStrings.ankiFallbackPickFileFirst,
                style: Theme.of(ctx).textTheme.titleMedium,
              ),
            ),
            ListTile(
              leading: const Icon(Icons.search),
              title: Text(AppStrings.ankiFallbackScanTitle),
              subtitle: Text(AppStrings.ankiFallbackScanSubtitle),
              onTap: () => Navigator.of(ctx).pop(_AnkiFallbackChoice.scan),
            ),
            ListTile(
              leading: const Icon(Icons.edit_note),
              title: Text(AppStrings.ankiFallbackPathTitle),
              subtitle: Text(AppStrings.ankiFallbackPathSubtitle),
              onTap: () => Navigator.of(ctx).pop(_AnkiFallbackChoice.path),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
    if (!mounted || choice == null) return;
    if (choice == _AnkiFallbackChoice.scan) {
      await _showScanResults();
    } else {
      await _showPathInputDialog();
    }
  }

  /// Scan the app sandbox + cached/known directories for .apkg/.colpkg and
  /// show them in a simple chooser dialog.
  Future<List<PlatformFile>> _scanLocalApkgFiles() async {
    final dirs = <Directory>[];
    try {
      dirs.add(await getApplicationSupportDirectory());
    } catch (_) {}
    try {
      dirs.add(await getApplicationDocumentsDirectory());
    } catch (_) {}
    // Device A G1: do not scan shared Download. User apkgs live there.
    final seen = <String>{};
    final hits = <PlatformFile>[];
    for (final dir in dirs) {
      if (!dir.existsSync()) continue;
      try {
        for (final entity in dir.listSync()) {
          if (entity is! File) continue;
          final path = entity.path;
          final lower = path.toLowerCase();
          if (!lower.endsWith('.apkg') && !lower.endsWith('.colpkg')) {
            continue;
          }
          if (!seen.add(path)) continue;
          hits.add(
            PlatformFile(
              path: path,
              name: path.split(RegExp(r'[/\\]')).last,
              size: entity.lengthSync(),
            ),
          );
        }
      } catch (_) {}
    }
    return hits;
  }

  Future<void> _showScanResults() async {
    if (!mounted) return;
    setState(() => _error = null);
    List<PlatformFile> hits;
    try {
      hits = defaultTargetPlatform.name == 'ohos'
          ? await OhosFilePicker.scanForFiles(
              allowedExtensions: _ankiExtensions,
            )
          : await _scanLocalApkgFiles();
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = '${AppStrings.ankiFallbackScanFailed}$e');
      return;
    }
    if (!mounted) return;
    if (hits.isEmpty) {
      setState(() => _error = AppStrings.ankiFallbackScanEmpty);
      return;
    }
    final picked = await showDialog<PlatformFile>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: Text(AppStrings.ankiFallbackScanTitle),
        children: [
          for (final f in hits)
            SimpleDialogOption(
              onPressed: () => Navigator.of(ctx).pop(f),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(f.name,
                      style: const TextStyle(fontWeight: FontWeight.w600)),
                  Text(
                    f.path ?? '',
                    style: Theme.of(ctx).textTheme.bodySmall,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
        ],
      ),
    );
    if (picked?.path == null) return;
    await _proceedWithPath(picked!.path!);
  }

  /// Open a dialog with a text field where the user pastes a full path.
  ///
  /// The dialog body is its own [StatefulWidget] ([_AnkiPathInputDialog]) so
  /// the [TextEditingController] is owned and disposed by the dialog's
  /// [State], not by this method's outer scope. Disposing the controller
  /// manually *after* `showDialog` returned (the previous implementation)
  /// raced with `TextField`/`EditableText` unmount and tripped the Flutter
  /// framework assertion `_dependents.isEmpty` at `widgets/framework.dart`
  /// ~line 6171, crashing the app on any Cancel/Confirm tap.
  Future<void> _showPathInputDialog() async {
    if (!mounted) return;
    final path = await showDialog<String>(
      context: context,
      builder: (ctx) => const _AnkiPathInputDialog(),
    );
    final trimmed = path?.trim();
    if (trimmed == null || trimmed.isEmpty) return;
    try {
      await OhosFilePicker.importFromPath(
        path: trimmed,
        allowedExtensions: _ankiExtensions,
      );
      await _proceedWithPath(trimmed);
    } on PlatformException catch (e) {
      if (!mounted) return;
      setState(() =>
          _error = '${AppStrings.ankiPickFileFailed(e.message ?? e.code)}');
    }
  }

  /// Common post-pick path: same as [OhosFilePicker.pickFiles] success path.
  Future<void> _proceedWithPath(String path) async {
    setState(() {
      _filePath = path;
      _error = null;
      _step = 1;
    });
    await _parseFile(path);
  }

  Future<void> _loadSampleDeck() async {
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
      _logTiming('parse: failed', totalSw, {'error': e.runtimeType.toString()});
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
    if (msg.contains('.apkg') || msg.contains('.colpkg')) {
      return AppStrings.ankiPickFileError;
    }
    return AppStrings.ankiParseFailed(error);
  }

  /// Shared path after a collection is available (parsed file or sample).
  Future<void> _preparePreview(
    AnkiCollection collection, {
    required String sourcePath,
    required bool isSample,
  }) async {
    // Infer notetype mappings (canonicalize so UI never stores legacy aliases)
    final mappingSw = Stopwatch()..start();
    final mappings = <int, NotetypeMapping>{};
    for (final entry in collection.notetypes.entries) {
      mappings[entry.key] =
          _canonicalizeMapping(AnkiCardAdapter.inferMapping(entry.value));
    }
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
    final dao = AnkiImportDao(getIt<CourseDatabase>());
    final daoSw = Stopwatch()..start();
    final existingImport = await dao.findByHash(hash);
    daoSw.stop();
    _logTiming('preview: dao.findByHash', daoSw,
        {'hit': existingImport != null});
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
  /// via `mappingOverrides` - no downstream change needed.
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
    setState(() => _mappings[mid] = result);
  }

  /// Run AI notetype identification over all notetypes and replace the
  /// inferred mappings with the LLM result. Requires a configured AI API;
  /// otherwise prompts the user to configure one. [AnkiNotetypeAI.identifyAll]
  /// falls back to heuristics per-notetype on LLM/parse failure, so it never
  /// throws for content reasons.
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
      final result = await AnkiNotetypeAI()
          .identifyAll(config: config, notetypes: collection.notetypes);
      if (!mounted) return;
      setState(() {
        _mappings = {
          for (final e in result.entries) e.key: _canonicalizeMapping(e.value),
        };
        _isAiIdentifying = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _isAiIdentifying = false);
    }
  }

  Future<void> _executeImport() async {
    final collection = _collection;
    final filePath = _filePath;
    final hash = _sourceHash;
    if (collection == null || filePath == null || hash == null) return;

    final totalSw = Stopwatch()..start();
    setState(() {
      _step = 3;
      _cancelRequested = false;
      _progress = 0;
      _progressMessage = AppStrings.ankiPreparingImport;
    });

    AnkiImportCleanupService? cleanup;
    String? activeImportId;
    var shouldRollbackOnFailure = false;
    var srsIdsBefore = <String>{};
    SrsProvider? activeSrsProvider;
    final dao = AnkiImportDao(getIt<CourseDatabase>());
    try {
      final courseProvider = context.read<CourseProvider>();
      final srsProvider = context.read<SrsProvider>();
      activeSrsProvider = srsProvider;
      srsIdsBefore = srsProvider.state.keys.toSet();
      final liteThreshold = context.read<SettingsProvider>().ankiLiteThreshold;
      final database = getIt<CourseDatabase>();
      final repo = CourseRepository(database);
      final noteDao = AnkiNoteDao(database);
      cleanup = AnkiImportCleanupService(
        repository: repo,
        srsProvider: srsProvider,
        importDao: dao,
        noteDao: noteDao,
        reviewHistoryDao: getIt<ReviewHistoryDao>(),
        audioResolver: AnkiAudioResolver(),
      );

      // Re-imports of the same file reuse the previous importId so card ids
      // (`anki-<importId>-c<cardId>`) stay stable and merge/skipExisting can
      // match; appendAsNew always mints a fresh id (duplicate deck).
      final previous = _existingImport;
      var importId = previous?.importId ??
          DateTime.now().millisecondsSinceEpoch.toRadixString(36);
      if (_strategy == ImportStrategy.appendAsNew ||
          (_strategy == ImportStrategy.forceReplace && previous != null)) {
        importId = DateTime.now().millisecondsSinceEpoch.toRadixString(36);
      }
      activeImportId = importId;
      shouldRollbackOnFailure = previous == null ||
          _strategy == ImportStrategy.appendAsNew ||
          _strategy == ImportStrategy.forceReplace;

      final officialCapable = AnkiImportFacade.decisionFor(
            OfficialAnkiFeatureFlags.current,
          ) ==
          AnkiImportDecision.official;
      final unifiedRequest = UnifiedAnkiImportRequest(
        importId: importId,
        sourceHash: hash,
        canonicalCardIds: [
          for (final card in collection.cards) card.id,
        ],
        officialCapable: officialCapable,
        reuseExistingIdentity: _strategy != ImportStrategy.appendAsNew &&
            _strategy != ImportStrategy.forceReplace,
      );
      final unifiedBegin =
          await UnifiedAnkiImportOrchestrator.instance.begin(unifiedRequest);
      if (unifiedBegin.noOp) {
        setState(() {
          _summary = AnkiImportSummary(
            importId: importId,
            sectionCount: 0,
            unitCount: 0,
            lessonCount: 0,
            cardCount: unifiedBegin.canonicalCardCount,
            wordEntryCount: unifiedBegin.canonicalCardCount,
            sourceCardCount: unifiedBegin.canonicalCardCount,
          );
          _step = 4;
        });
        return;
      }

      var effectiveCollection = collection;

      // Existing SRS states are always idempotently preserved by the
      // migrator. Rebuild navigation and canonical source from the complete
      // package even for Skip Existing; filtering the collection here used to
      // create an empty successful import when every card already existed.

      late AnkiImportSummary summary;
      var mediaReport = const AnkiMediaCopyReport();

      // Copy media files (audio/images) into persistent storage BEFORE opening
      // the DB transaction so the SQLite write lock isn't held across all file
      // I/O - a multi-thousand-card deck can copy thousands of files, and
      // holding the write txn open for that blocks every other DB write in the
      // app. copyMedia is best-effort (returns a report of missing/failed
      // files); a catastrophic failure throws here, before the transaction
      // opens, so nothing is committed - same rollback semantics as before.
      setState(() => _progressMessage = AppStrings.ankiCopyingMedia);
      final mediaSw = Stopwatch()..start();
      mediaReport = await AnkiAudioResolver().copyMedia(
        sourceDir: collection.mediaDir,
        importId: importId,
        mediaMapping: collection.media,
      );
      mediaSw.stop();
      _logTiming('import: copyMedia', mediaSw, {
        'available': mediaReport.availableCount,
        'missing': mediaReport.missingCount,
        'failed': mediaReport.failedCount,
      });

      final txnSw = Stopwatch()..start();
      final assembleSw = Stopwatch(); // started inside the txn
      final migrateSw = Stopwatch();
      final saveSw = Stopwatch();
      await database.transaction(() async {
        // NoteStore rows reference anki_imports(import_id). Create the parent
        // before the assembler writes notetypes, notes, and card metadata. The
        // final upsert below refreshes counts and media metadata after the
        // import completes.
        await dao.upsert(AnkiImportRecord(
          importId: importId,
          sourcePath: filePath,
          sourceHash: hash,
          importedAt: DateTime.now().millisecondsSinceEpoch ~/ 1000,
          deckCount: collection.decks.length,
          noteCount: effectiveCollection.notes.length,
          cardCount: effectiveCollection.cards.length,
        ));

        if (previous != null && importId == previous.importId) {
          await _clearDerivedImportData(importId, repo, noteDao);
        }

        setState(() => _progressMessage = AppStrings.ankiAssemblingCourse);

        // Assemble and write course tree
        final assembler = AnkiDeckAssembler();
        assembleSw
          ..reset()
          ..start();
        summary = await assembler.assemble(
          collection: effectiveCollection,
          importId: importId,
          repo: repo,
          noteDao: noteDao,
          mappingOverrides: _mappings,
          smartGrouping: _smartGrouping,
          liteThreshold: liteThreshold,
          onProgress: (p, msg) {
            if (mounted)
              setState(() {
                _progress = p;
                _progressMessage = msg;
              });
          },
          isCancelled: () => _cancelRequested,
        );
        assembleSw.stop();
        _logTiming('import: assemble', assembleSw, {'cards': summary.cardCount});

        if (_cancelRequested) throw const AnkiImportCancelled();

        setState(() => _progressMessage = AppStrings.ankiMigratingSrs);

        // Official-owned imports must not create Turna Anki SRS rows.
        if (unifiedBegin.wroteTurnaSrs && !unifiedBegin.noOp) {
          final migrator = AnkiSrsMigrator();
          final dailyNew = getIt<AnkiDeckManager>().dailyNewLimit;
          migrateSw
            ..reset()
            ..start();
          await migrator.migrate(
            cards: effectiveCollection.cards,
            importId: importId,
            srsProvider: srsProvider,
            revlog: effectiveCollection.revlog,
            reviewHistoryDao: getIt<ReviewHistoryDao>(),
            newCardsPerDay: dailyNew,
            collectionCreationTime: effectiveCollection.collectionCreationTime,
            importScheduling: _importLearningProgress,
          );
          migrateSw.stop();
          _logTiming('import: migrate', migrateSw,
              {'cards': effectiveCollection.cards.length});
        }

        setState(() => _progressMessage = AppStrings.ankiSavingMetadata);

        // Save import metadata (media was copied before the transaction opened).
        saveSw
          ..reset()
          ..start();
        await dao.upsert(AnkiImportRecord(
          importId: importId,
          sourcePath: filePath,
          sourceHash: hash,
          importedAt: DateTime.now().millisecondsSinceEpoch ~/ 1000,
          deckCount: collection.decks.length,
          noteCount: effectiveCollection.notes.length,
          cardCount: effectiveCollection.cards.length,
          mediaCount: mediaReport.availableCount,
          notetypesJson: jsonEncode(
            _mappings.map((k, v) => MapEntry(k.toString(), v.toJson())),
          ),
          sourceCardCount: effectiveCollection.cards.length,
          storedCardCount: effectiveCollection.cards.length,
          indexedCardCount: summary.cardCount,
          importedScheduling: _importLearningProgress,
        ));
        await dao.markComplete(
          importId,
          sourceCardCount: effectiveCollection.cards.length,
          indexedCardCount: summary.cardCount,
          importedScheduling: _importLearningProgress,
        );
        saveSw.stop();
        _logTiming('import: save metadata', saveSw);
      });
      txnSw.stop();
      _logTiming('import: transaction total', txnSw);
      await UnifiedAnkiImportOrchestrator.instance.finalize(unifiedRequest);

      // Build Force Replace under a fresh id and remove the old copy only
      // after the replacement has committed successfully.
      if (_strategy == ImportStrategy.forceReplace && previous != null) {
        final cleanupSw = Stopwatch()..start();
        try {
          await _removeExistingImport(
            previous.importId,
            repo,
            srsProvider,
            dao,
          );
        } catch (_) {
          // Keeping both complete copies is safer than deleting the new one
          // after a cleanup-only failure.
        }
        cleanupSw.stop();
        _logTiming('import: forceReplace cleanup', cleanupSw);
      }

      // If official engine is enabled and we are importing a real file, sync to official Anki collection & migration record
      if (!_isSample && !unifiedBegin.noOp) {
        try {
          final flags = OfficialAnkiFeatureFlags.current;
          final decision = AnkiImportFacade.decisionFor(flags);
          OfficialAnkiImporter? officialImporter =
              OfficialAnkiCompositionRoot.session;
          if (decision == AnkiImportDecision.official &&
              officialImporter == null) {
            final support = await getApplicationSupportDirectory();
            officialImporter =
                await OfficialAnkiCompositionRoot.requireImporter(
              supportDir: support,
            );
          }
          final facade = AnkiImportFacade.resolve(
            flags: flags,
            officialImporter: officialImporter,
            legacyImporter: _importer,
          );
          if (facade.isOfficial) {
            final official = await facade.importOfficialOrNull(
              packagePath: filePath,
              displayName: filePath.split(RegExp(r'[/\\]')).last,
            );
            if (official != null &&
                official.state == OfficialAnkiSourceState.active) {
              final support = await getApplicationSupportDirectory();
              final paths = OfficialAnkiPaths(
                profileId: 'profile-default-01',
                profileRoot: Directory('${support.path}/official_anki/default'),
              );
              final catalog = OfficialAnkiCompositionRoot.readOnlyCatalog ??
                  OfficialAnkiDatabase.file(paths.catalogFile.path);
              try {
                final migrationDao = OfficialAnkiMigrationDao(catalog);
                final now = DateTime.now().millisecondsSinceEpoch;
                final existing = migrationDao.findByLegacyImport(
                  profileId: paths.profileId,
                  legacyImportId: importId,
                );
                if (existing == null) {
                  migrationDao.insertObservingOfficial(
                    migrationId: newOfficialAnkiId('mig'),
                    profileId: paths.profileId,
                    legacyImportId: importId,
                    officialSourceId: official.sourceId,
                    sourceHash: hash,
                    nowMillis: now,
                    cardCount: summary.cardCount,
                  );
                } else if (existing.recordedKind != 'official' ||
                    existing.officialSourceId != official.sourceId) {
                  migrationDao.setOfficialSourceAndRecordedKind(
                    migrationId: existing.migrationId,
                    officialSourceId: official.sourceId,
                    recordedKind: 'official',
                    nowMillis: now,
                  );
                }
              } finally {
                if (OfficialAnkiCompositionRoot.readOnlyCatalog == null) {
                  catalog.close();
                }
              }
            }
          }
        } catch (e) {
          debugPrint(
            '[AnkiImport] Official import cutover sync failed/deferred: $e',
          );
        }
      }

      // Promote the import to a first-class course entry:
      // 1) Drop CourseLoader shells/vocab memo so the new Anki section(s)
      //    appear in [CourseProvider.courseEntries] without an app restart.
      // 2) Scope Learn to this deck so it is not "merged into" the built-in
      //    Turkish tree (built-in scope hides level=='Anki').
      // setCourseScope early-returns when already on the same scope (re-import),
      // so force a reload in that case.
      final scopeSw = Stopwatch()..start();
      CourseLoader.invalidateCaches();
      final scope = 'anki:$importId';
      if (courseProvider.courseScope == scope) {
        await courseProvider.reloadCourse();
      } else {
        await courseProvider.setCourseScope(scope);
      }
      // Persist order so the new deck is stable in the course-management list.
      final scopes = [
        for (final e in courseProvider.courseEntries) e.scope,
      ];
      if (!scopes.contains(scope)) {
        scopes.add(scope);
      }
      await courseProvider.persistCourseOrder(scopes);
      scopeSw.stop();
      _logTiming('import: scope setup', scopeSw);

      setState(() {
        _summary = summary.copyWith(
          missingMediaCount: mediaReport.missingCount,
          failedMediaCount: mediaReport.failedCount,
        );
        _step = 4;
      });
    } on AnkiImportCancelled {
      if (activeSrsProvider != null && activeImportId != null) {
        final addedIds = activeSrsProvider.state.keys
            .where((id) =>
                id.startsWith('anki-$activeImportId-') &&
                !srsIdsBefore.contains(id))
            .toList();
        await activeSrsProvider.rollbackImportedIds(addedIds);
      }
      // Cancellation must not leave a half-written import behind.
      if (shouldRollbackOnFailure &&
          cleanup != null &&
          activeImportId != null) {
        try {
          await cleanup.deleteAll(activeImportId);
        } catch (_) {
          // Cancellation should still return the wizard to the preview even
          // if one cleanup backend is temporarily unavailable.
        }
      }
      // Mark the lifecycle row 'failed' so the import manager can surface
      // partial-import state instead of leaving it stuck in 'pending'.
      if (activeImportId != null) {
        try {
          await dao.markFailed(
            activeImportId,
            reason: 'cancelled',
          );
        } catch (_) {
          // Lifecycle write failure is non-fatal; the cleanup above already
          // removed the user's data.
        }
      }
      setState(() {
        _step = 2;
        _progress = 0;
        _progressMessage = '';
      });
    } catch (e) {
      if (activeSrsProvider != null && activeImportId != null) {
        final addedIds = activeSrsProvider.state.keys
            .where((id) =>
                id.startsWith('anki-$activeImportId-') &&
                !srsIdsBefore.contains(id))
            .toList();
        await activeSrsProvider.rollbackImportedIds(addedIds);
      }
      if (shouldRollbackOnFailure &&
          cleanup != null &&
          activeImportId != null) {
        try {
          await cleanup.deleteAll(activeImportId);
        } catch (_) {
          // Preserve the original import error; diagnostics can report the
          // cleanup failure on the next import attempt.
        }
      }
      if (activeImportId != null) {
        try {
          await dao.markFailed(
            activeImportId,
            reason: e.toString(),
          );
        } catch (_) {
          // Lifecycle write failure is non-fatal; the cleanup above already
          // removed the user's data.
        }
      }
      setState(() {
        _error = AppStrings.ankiImportFailed(e);
        _step = 2;
      });
    } finally {
      totalSw.stop();
      _logTiming('import: total', totalSw, {
        'cards': collection.cards.length,
        'strategy': _strategy.name,
      });
      AnkiImporter.cleanupExtractedDir(collection.mediaDir);
    }
  }

  /// Remove every trace of a previous import (forceReplace strategy):
  /// vocabulary, section tree, SRS states and the import record.
  Future<void> _removeExistingImport(
    String importId,
    CourseRepository repo,
    SrsProvider srsProvider,
    AnkiImportDao dao,
  ) async {
    await AnkiImportCleanupService(
      repository: repo,
      srsProvider: srsProvider,
      importDao: dao,
      noteDao: AnkiNoteDao(getIt<CourseDatabase>()),
      reviewHistoryDao: getIt<ReviewHistoryDao>(),
      audioResolver: AnkiAudioResolver(),
    ).deleteAll(importId);
  }

  /// Clear only derived course/canonical rows before an in-place rebuild.
  /// Called inside the surrounding database transaction, so failure restores
  /// the previous complete import. User SRS/review history and media remain.
  Future<void> _clearDerivedImportData(
    String importId,
    CourseRepository repo,
    AnkiNoteDao noteDao,
  ) async {
    await repo.deleteByTag('anki:$importId');
    final sections = await repo.sectionShells();
    for (final section in sections) {
      if (section.id.startsWith('anki-$importId-')) {
        await repo.deleteSection(section.id);
      }
    }
    await noteDao.deleteByImport(importId);
    await noteDao.deletePrerenderedByPrefix('anki-$importId-');
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
                      : TurnaTheme.textHintColor(context).withValues(alpha: 0.2),
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
                    borderRadius:
                        BorderRadius.circular(TurnaTheme.radiusSmall),
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
                    groupValue: groupValue,
                    onChanged: (v) => onChanged(v!),
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
  final VoidCallback onPressed;
  const _StickyImportBar({required this.onPressed});

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
          child: SizedBox(
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

/// Tappable "try a sample deck" card used on the file-selection step. Sits
/// below the primary CTA as a low-pressure alternative entry point so users
/// can preview the import flow without picking a real file.
class _SampleDeckCard extends StatelessWidget {
  final VoidCallback onTap;
  const _SampleDeckCard({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(TurnaTheme.radiusLarge),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(TurnaTheme.radiusLarge),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: TurnaTheme.brandTeal.withValues(alpha: 0.06),
            borderRadius: BorderRadius.circular(TurnaTheme.radiusLarge),
            border: Border.all(
              color: TurnaTheme.brandTeal.withValues(alpha: 0.2),
            ),
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: TurnaTheme.brandTeal.withValues(alpha: 0.12),
                  borderRadius:
                      BorderRadius.circular(TurnaTheme.radiusMedium),
                ),
                child: const Icon(
                  Icons.auto_awesome_rounded,
                  color: TurnaTheme.brandTeal,
                  size: 22,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      AppStrings.ankiTrySample,
                      style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 15,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      AppStrings.ankiSampleHint,
                      style: TextStyle(
                        color: TurnaTheme.textSecondaryColor(context),
                        fontSize: 12,
                        height: 1.3,
                      ),
                    ),
                  ],
                ),
              ),
              const Icon(
                Icons.chevron_right,
                color: TurnaTheme.brandTeal,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Body of the manual-path input dialog used by [_showPathInputDialog].
///
/// Extracted into its own [StatefulWidget] so the [TextEditingController] is
/// created in [State.initState] and disposed in [State.dispose]. This keeps
/// the controller lifetime aligned with the [TextField]'s `EditableText`
/// element, which is what the Flutter framework requires for its
/// `_dependents.isEmpty` invariant during `Element.unmount`.
class _AnkiPathInputDialog extends StatefulWidget {
  const _AnkiPathInputDialog();

  @override
  State<_AnkiPathInputDialog> createState() => _AnkiPathInputDialogState();
}

class _AnkiPathInputDialogState extends State<_AnkiPathInputDialog> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(AppStrings.ankiFallbackPathTitle),
      content: TextField(
        controller: _controller,
        autofocus: true,
        decoration: InputDecoration(
          labelText: AppStrings.ankiFallbackPathHint,
          hintText: AppStrings.ankiFallbackPathHint,
        ),
        maxLines: 3,
        minLines: 1,
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('取消'),
        ),
        ElevatedButton(
          onPressed: () => Navigator.of(context).pop(_controller.text),
          child: Text(AppStrings.ankiFallbackPathAction),
        ),
      ],
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
  final VoidCallback onEdit;

  const _NotetypeMappingRow({
    required this.notetype,
    required this.mapping,
    required this.onEdit,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(TurnaTheme.radiusMedium),
        child: InkWell(
          onTap: onEdit,
          borderRadius: BorderRadius.circular(TurnaTheme.radiusMedium),
          child: Semantics(
            button: true,
            label: AppStrings.ankiMappingEditTooltip,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          notetype.name,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                        const SizedBox(height: 4),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 8),
                          decoration: BoxDecoration(
                            color:
                                TurnaTheme.brandTeal.withValues(alpha: 0.08),
                            borderRadius:
                                BorderRadius.circular(TurnaTheme.radiusSmall),
                            border: Border.all(
                              color: TurnaTheme.brandTeal
                                  .withValues(alpha: 0.18),
                            ),
                          ),
                          child: Row(
                            children: [
                              const Icon(
                                Icons.auto_awesome_outlined,
                                size: 16,
                                color: TurnaTheme.brandTeal,
                              ),
                              const SizedBox(width: 7),
                              Expanded(
                                child: Text(
                                  _mappingTypeLabel(
                                    mapping?.type ??
                                        NotetypeMappingType.ankiCard,
                                  ),
                                  style: const TextStyle(
                                      fontWeight: FontWeight.w600),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  const Icon(
                    Icons.edit_outlined,
                    size: 20,
                    color: TurnaTheme.brandTeal,
                  ),
                ],
              ),
            ),
          ),
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
    switch (_canonicalizeMappingType(t)) {
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
                onChanged: (i) => setState(
                    () => _draft = _draft.copyWith(frontFieldIndex: i ?? 0)),
              ),
              const SizedBox(height: 10),
              _fieldSelector(
                context,
                label: AppStrings.ankiMappingFieldBack,
                value: _draft.backFieldIndex,
                fields: fields,
                onChanged: (i) => setState(
                    () => _draft = _draft.copyWith(backFieldIndex: i ?? 0)),
              ),
            ] else
              _autoFieldsHint(context),
            const SizedBox(height: 14),
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
            if (_draft.reason.isNotEmpty) ...[
              const SizedBox(height: 12),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    Icons.lightbulb_outline_rounded,
                    size: 16,
                    color: TurnaTheme.textSecondaryColor(context),
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          AppStrings.ankiMappingReason,
                          style: TextStyle(
                            fontWeight: FontWeight.w600,
                            color: TurnaTheme.textSecondaryColor(context),
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          _draft.reason,
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ],
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
          child: Text(AppStrings.commonSave),
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
              DropdownMenuItem(value: i, child: Text('$i. ${fields[i]}')),
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

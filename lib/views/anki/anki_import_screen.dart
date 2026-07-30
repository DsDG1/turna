// Dart imports:
import 'dart:async';
import 'dart:convert';

// Flutter imports:
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

// Package imports:
import 'package:auto_route/auto_route.dart';
import 'package:provider/provider.dart';

// Project imports:
import 'package:varnamala/application/anki/anki_card_adapter.dart';
import 'package:varnamala/application/anki/anki_deck_assembler.dart';
import 'package:varnamala/application/anki/anki_importer.dart';
import 'package:varnamala/application/anki/anki_models.dart';
import 'package:varnamala/application/anki/anki_organization_resolver.dart';
import 'package:varnamala/application/anki/anki_sample_deck.dart';
import 'package:varnamala/application/anki/anki_srs_migrator.dart';
import 'package:varnamala/application/course_provider.dart';
import 'package:varnamala/application/srs_provider.dart';
import 'package:varnamala/data/anki_import_dao.dart';
import 'package:varnamala/data/course_database.dart';
import 'package:varnamala/data/course_repository.dart';
import 'package:varnamala/data/review_history_dao.dart';
import 'package:varnamala/di/injection.dart';
import 'package:varnamala/domain/audio/anki_audio_resolver.dart';
import 'package:varnamala/l10n/app_strings.dart';
import 'package:varnamala/utils/ohos_file_picker.dart';
import 'package:varnamala/views/theme.dart';

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

  // Incremental-update detection (computed at parse time)
  String? _sourceHash;
  AnkiImportRecord? _existingImport;

  // Progress
  String _progressMessage = '';
  double _progress = 0; // 0..1, 0 means indeterminate
  bool _cancelRequested = false;
  AnkiImportSummary? _summary;

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
      ),
      body: _buildBody(),
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
                      color: VarnamalaTheme.peacockTeal.withValues(alpha: 0.6),
                    ),
                    const SizedBox(height: 24),
                    Text(
                      AppStrings.ankiImportSelectTitle,
                      style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 12),
                    Text(
                      AppStrings.ankiImportSelectSubtitle,
                      style: TextStyle(
                        color: VarnamalaTheme.textSecondaryColor(context),
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 32),
                    if (_error != null)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 16),
                        child: Text(
                          _error!,
                          style: const TextStyle(color: VarnamalaTheme.error),
                          textAlign: TextAlign.center,
                        ),
                      ),
                    ElevatedButton.icon(
                      onPressed: _pickFile,
                      icon: const Icon(Icons.folder_open),
                      label: Text(AppStrings.ankiChooseFile),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: VarnamalaTheme.peacockTeal,
                        foregroundColor: VarnamalaTheme.textOnPrimary,
                        padding: const EdgeInsets.symmetric(
                            horizontal: 32, vertical: 16),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                    ),
                    // Manual fallbacks. Always available on OHos (where the
                    // system file picker may be missing), and on every
                    // platform the user can still prefer a direct path if
                    // they copied it elsewhere.
                    if (defaultTargetPlatform == TargetPlatform.ohos) ...[
                      const SizedBox(height: 16),
                      Text(
                        AppStrings.ankiFallbackPickFileFirst,
                        style: TextStyle(
                          color: VarnamalaTheme.textHintColor(context),
                          fontSize: 12,
                        ),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 8),
                      OutlinedButton.icon(
                        onPressed: _showScanResults,
                        icon: const Icon(Icons.search),
                        label: Text(AppStrings.ankiFallbackScanTitle),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: VarnamalaTheme.peacockTeal,
                          side:
                              const BorderSide(color: VarnamalaTheme.peacockTeal),
                          padding: const EdgeInsets.symmetric(
                              horizontal: 24, vertical: 12),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                      ),
                      const SizedBox(height: 8),
                      TextButton.icon(
                        onPressed: _showPathInputDialog,
                        icon: const Icon(Icons.edit_note, size: 18),
                        label: Text(AppStrings.ankiFallbackPathTitle),
                        style: TextButton.styleFrom(
                          foregroundColor: VarnamalaTheme.peacockTeal,
                        ),
                      ),
                    ],
                    const SizedBox(height: 16),
                    OutlinedButton.icon(
                      onPressed: _loadSampleDeck,
                      icon: const Icon(Icons.auto_awesome_rounded),
                      label: Text(AppStrings.ankiTrySample),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: VarnamalaTheme.peacockTeal,
                        side:
                            const BorderSide(color: VarnamalaTheme.peacockTeal),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 28, vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      AppStrings.ankiSampleHint,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: VarnamalaTheme.textHintColor(context),
                          ),
                      textAlign: TextAlign.center,
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
                backgroundColor:
                    VarnamalaTheme.peacockTeal.withValues(alpha: 0.1),
                valueColor: const AlwaysStoppedAnimation<Color>(
                    VarnamalaTheme.peacockTeal),
              ),
            )
          else
            const CircularProgressIndicator(),
          const SizedBox(height: 24),
          Text(AppStrings.ankiParsing),
          if (_progressMessage.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              _progressMessage,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: VarnamalaTheme.textSecondaryColor(context),
                  ),
            ),
          ],
          const SizedBox(height: 24),
          TextButton(
            onPressed: () {
              setState(() {
                _cancelRequested = true;
                _step = 0;
                _progress = 0;
                _progressMessage = '';
              });
            },
            child: Text(AppStrings.commonCancel),
          ),
        ],
      ),
    );
  }

  // ─── Step 2: Preview ────────────────────────────────────────────────

  Widget _buildPreviewStep() {
    final collection = _collection!;
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        // Summary card
        _InfoCard(
          title: AppStrings.ankiCollectionSummary,
          children: [
            _InfoRow(AppStrings.ankiDecksLabel, '${collection.decks.length}'),
            _InfoRow(AppStrings.ankiNotesLabel, '${collection.notes.length}'),
            _InfoRow(AppStrings.ankiCardsLabel, '${collection.cards.length}'),
            _InfoRow(AppStrings.ankiMediaFilesLabel, '${collection.media.length}'),
          ],
        ),
        const SizedBox(height: 16),

        // Deck structure
        _InfoCard(
          title: AppStrings.ankiDeckStructure,
          children: [
            for (final deck in collection.decks.values)
              _InfoRow(deck.name, AppStrings.ankiDeckCardCount(deck.cardCount)),
          ],
        ),
        const SizedBox(height: 16),

        // Smart organization preview (tags / notetype fields -> units & lessons)
        _buildOrganizationCard(collection),
        const SizedBox(height: 16),

        // Notetype mappings
        _InfoCard(
          title: AppStrings.ankiNotetypeMapping,
          children: [
            for (final entry in collection.notetypes.entries)
              _InfoRow(
                entry.value.name,
                _mappings[entry.key]?.type.name ?? 'ankiCard',
              ),
          ],
        ),
        const SizedBox(height: 16),

        // Collision report
        _InfoCard(
          title: AppStrings.ankiCollisionReport,
          children: [
            _InfoRow(AppStrings.ankiNewCards, '$_newCount'),
            _InfoRow(AppStrings.ankiExistingCards, '$_existingCount'),
          ],
        ),
        const SizedBox(height: 16),

        // Strategy selection
        Text(
          AppStrings.ankiImportStrategy,
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w700,
              ),
        ),
        const SizedBox(height: 8),
        for (final s in ImportStrategy.values)
          RadioListTile<ImportStrategy>(
            title: Text(_strategyLabel(context, s)),
            subtitle: Text(_strategyDescription(context, s)),
            value: s,
            groupValue: _strategy,
            onChanged: (v) => setState(() => _strategy = v!),
            dense: true,
          ),
        const SizedBox(height: 24),

        // Import button
        ElevatedButton(
          onPressed: _executeImport,
          style: ElevatedButton.styleFrom(
            backgroundColor: VarnamalaTheme.peacockTeal,
            foregroundColor: VarnamalaTheme.textOnPrimary,
            padding: const EdgeInsets.symmetric(vertical: 16),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
          child: Text(
            AppStrings.commonImport,
            style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
          ),
        ),
      ],
    );
  }

  /// Preview of the unit/lesson organization detected from Anki tags and
  /// notetype fields, plus a toggle to enable smart grouping.
  Widget _buildOrganizationCard(AnkiCollection collection) {
    final l10n = AppStrings;
    const resolver = AnkiOrganizationResolver();
    final preview = resolver.preview(
      notes: collection.notes,
      notetypes: collection.notetypes,
    );
    return _InfoCard(
      title: AppStrings.ankiOrganizationTitle,
      children: [
        if (preview.hasAny) ...[
          _InfoRow(AppStrings.ankiDetectedUnits, '${preview.unitCount}'),
          _InfoRow(AppStrings.ankiDetectedLessons, '${preview.lessonCount}'),
          _InfoRow(AppStrings.ankiResolvedCards, '${preview.resolvedCardCount}'),
        ] else
          _InfoRow(AppStrings.ankiOrganizationNone, AppStrings.ankiOrganizationNoneDesc),
        SwitchListTile(
          value: _smartGrouping,
          onChanged: (v) => setState(() => _smartGrouping = v),
          title: Text(AppStrings.ankiSmartGrouping),
          subtitle: Text(AppStrings.ankiSmartGroupingDesc),
          dense: true,
          contentPadding: EdgeInsets.zero,
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
                backgroundColor:
                    VarnamalaTheme.peacockTeal.withValues(alpha: 0.1),
                valueColor: const AlwaysStoppedAnimation<Color>(
                    VarnamalaTheme.peacockTeal),
              ),
            )
          else
            const CircularProgressIndicator(),
          const SizedBox(height: 24),
          Text(_progressMessage.isEmpty
              ? AppStrings.ankiPreparingImport
              : _progressMessage),
          const SizedBox(height: 24),
          TextButton(
            onPressed: () {
              setState(() {
                _cancelRequested = true;
              });
            },
            child: Text(AppStrings.commonCancel),
          ),
        ],
      ),
    );
  }

  // ─── Step 4: Done ───────────────────────────────────────────────────

  Widget _buildDoneStep() {
    final summary = _summary;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(
              Icons.check_circle_outline,
              size: 80,
              color: VarnamalaTheme.success,
            ),
            const SizedBox(height: 24),
            Text(
              AppStrings.ankiImportComplete,
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
            ),
            const SizedBox(height: 16),
            if (summary != null) ...[
              Text(AppStrings.ankiCardsImported(summary.cardCount)),
              Text(AppStrings.ankiLessonsCreated(summary.lessonCount)),
              if (summary.wordEntryCount > 0)
                Text(AppStrings.ankiVocabAdded(summary.wordEntryCount)),
            ],
            const SizedBox(height: 32),
            ElevatedButton(
              onPressed: _startLearningNow,
              style: ElevatedButton.styleFrom(
                backgroundColor: VarnamalaTheme.peacockTeal,
                foregroundColor: VarnamalaTheme.textOnPrimary,
                padding:
                    const EdgeInsets.symmetric(horizontal: 32, vertical: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: Text(AppStrings.ankiStartLearning),
            ),
            const SizedBox(height: 12),
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
      await context
          .read<CourseProvider>()
          .setCourseScope('anki:$importId');
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
      if (defaultTargetPlatform == TargetPlatform.ohos) {
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
  Future<void> _showScanResults() async {
    if (!mounted) return;
    setState(() => _error = null);
    List<PlatformFile> hits;
    try {
      hits = await OhosFilePicker.scanForFiles(allowedExtensions: _ankiExtensions);
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
                  Text(f.name, style: const TextStyle(fontWeight: FontWeight.w600)),
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
      setState(() => _error = '${AppStrings.ankiPickFileFailed(e.message ?? e.code)}');
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
    setState(() {
      _cancelRequested = false;
      _progress = 0;
      _progressMessage = '';
      _isSample = false;
    });
    try {
      final collection = await _importer.parse(
        path,
        onProgress: (p, msg) {
          if (mounted) setState(() { _progress = p; _progressMessage = msg; });
        },
        isCancelled: () => _cancelRequested,
      );

      await _preparePreview(collection, sourcePath: path, isSample: false);
    } on AnkiImportCancelled {
      // User pressed cancel — nothing was written; return to file picker.
      setState(() {
        _step = 0;
        _progress = 0;
        _progressMessage = '';
      });
    } catch (e) {
      setState(() {
        _error = AppStrings.ankiParseFailed(e);
        _step = 0;
      });
    }
  }

  /// Shared path after a collection is available (parsed file or sample).
  Future<void> _preparePreview(
    AnkiCollection collection, {
    required String sourcePath,
    required bool isSample,
  }) async {
    // Infer notetype mappings
    final mappings = <int, NotetypeMapping>{};
    for (final entry in collection.notetypes.entries) {
      mappings[entry.key] = AnkiCardAdapter.inferMapping(entry.value);
    }

    // The source hash was computed once during parsing (from the bytes
    // already loaded for ZIP extraction), so we can detect re-imports here
    // without re-reading the whole file on the main isolate.
    final hash = collection.sourceHash;

    // Real collision report:
    // - Same file imported before (hash match) → ids are deterministic
    //   (`anki-<importId>-n<noteId>`), so count notes already in the SRS
    //   queue under the previous importId as "existing".
    // - Otherwise everything is new.
    final dao = AnkiImportDao(getIt<CourseDatabase>());
    final existingImport = await dao.findByHash(hash);
    if (!mounted) return;
    var existingCount = 0;
    if (existingImport != null) {
      final srsIds = context.read<SrsProvider>().state.keys.toSet();
      final prefix = 'anki-${existingImport.importId}-n';
      existingCount =
          collection.notes.where((n) => srsIds.contains('$prefix${n.id}')).length;
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
      _isSample = isSample;
      // A re-import defaults to merge (update in place); first import keeps
      // merge as well — it behaves identically when nothing exists.
      _strategy = ImportStrategy.merge;
      _step = 2;
    });
  }

  Future<void> _executeImport() async {
    final collection = _collection;
    final filePath = _filePath;
    final hash = _sourceHash;
    if (collection == null || filePath == null || hash == null) return;

    setState(() {
      _step = 3;
      _cancelRequested = false;
      _progress = 0;
      _progressMessage = AppStrings.ankiPreparingImport;
    });

    try {
      final courseProvider = context.read<CourseProvider>();
      final srsProvider = context.read<SrsProvider>();
      final database = getIt<CourseDatabase>();
      final repo = CourseRepository(database);
      final dao = AnkiImportDao(database);

      // Re-imports of the same file reuse the previous importId so note ids
      // (`anki-<importId>-n<noteId>`) stay stable and merge/skipExisting can
      // match; appendAsNew always mints a fresh id (duplicate deck).
      final previous = _existingImport;
      var importId = previous?.importId ??
          DateTime.now().millisecondsSinceEpoch.toRadixString(36);
      if (_strategy == ImportStrategy.appendAsNew) {
        importId = DateTime.now().millisecondsSinceEpoch.toRadixString(36);
      }

      var effectiveCollection = collection;

      if (_strategy == ImportStrategy.forceReplace && previous != null) {
        await _removeExistingImport(
            previous.importId, repo, srsProvider, dao);
      } else if (_strategy == ImportStrategy.skipExisting && previous != null) {
        // Drop notes already in the SRS queue (i.e. already imported).
        final srsIds = srsProvider.state.keys.toSet();
        final keptNotes = collection.notes
            .where((n) => !srsIds.contains('anki-$importId-n${n.id}'))
            .toList();
        final keptNoteIds = keptNotes.map((n) => n.id).toSet();
        final keptCardIds = collection.cards
            .where((c) => keptNoteIds.contains(c.nid))
            .map((c) => c.id)
            .toSet();
        effectiveCollection = collection.copyWith(
          notes: keptNotes,
          cards: collection.cards
              .where((c) => keptNoteIds.contains(c.nid))
              .toList(),
          revlog: collection.revlog
              .where((r) => keptCardIds.contains(r.cid))
              .toList(),
        );
      }

      setState(() => _progressMessage = AppStrings.ankiAssemblingCourse);

      // Assemble and write course tree
      final assembler = AnkiDeckAssembler();
      final summary = await assembler.assemble(
        collection: effectiveCollection,
        importId: importId,
        repo: repo,
        mappingOverrides: _mappings,
        smartGrouping: _smartGrouping,
        onProgress: (p, msg) {
          if (mounted) setState(() { _progress = p; _progressMessage = msg; });
        },
        isCancelled: () => _cancelRequested,
      );

      if (_cancelRequested) {
        setState(() { _step = 2; _progress = 0; });
        return;
      }

      setState(() => _progressMessage = AppStrings.ankiMigratingSrs);

      // Migrate SRS state + backfill review history from the revlog
      final migrator = AnkiSrsMigrator();
      await migrator.migrate(
        cards: effectiveCollection.cards,
        importId: importId,
        srsProvider: srsProvider,
        revlog: effectiveCollection.revlog,
        reviewHistoryDao: getIt<ReviewHistoryDao>(),
      );

      setState(() => _progressMessage = AppStrings.ankiSavingMetadata);

      // Copy media files (audio/images) into persistent storage so
      // `anki://<importId>/<file>` references resolve after the temp
      // extraction directory is gone.
      final mediaCopied = await AnkiAudioResolver().copyMediaFiles(
        sourceDir: collection.mediaDir,
        importId: importId,
        mediaMapping: collection.media,
      );

      // Save import metadata
      await dao.upsert(AnkiImportRecord(
        importId: importId,
        sourcePath: filePath,
        sourceHash: hash,
        importedAt: DateTime.now().millisecondsSinceEpoch ~/ 1000,
        deckCount: collection.decks.length,
        noteCount: effectiveCollection.notes.length,
        cardCount: effectiveCollection.cards.length,
        mediaCount: mediaCopied,
        notetypesJson: jsonEncode(
          _mappings.map((k, v) => MapEntry(k.toString(), v.toJson())),
        ),
      ));

      // Refresh course tree
      await courseProvider.reloadCourse();

      setState(() {
        _summary = summary;
        _step = 4;
      });
    } on AnkiImportCancelled {
      // User pressed cancel during assemble. Partial course tree may have been
      // written; leave it (user can re-import or uninstall via deck manager).
      setState(() {
        _step = 2;
        _progress = 0;
        _progressMessage = '';
      });
    } catch (e) {
      setState(() {
        _error = AppStrings.ankiImportFailed(e);
        _step = 2;
      });
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
    await repo.deleteByTag('anki:$importId');
    final sections = await repo.sectionShells();
    for (final section in sections) {
      if (section.id.startsWith('anki-$importId-')) {
        await repo.deleteSection(section.id);
      }
    }
    await srsProvider.removeByPrefix('anki-$importId-');
    await dao.delete(importId);
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
}

// ─── Shared widgets ─────────────────────────────────────────────────

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

class _InfoCard extends StatelessWidget {
  final String title;
  final List<Widget> children;

  const _InfoCard({required this.title, required this.children});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: VarnamalaTheme.cardBg(context),
        borderRadius: BorderRadius.circular(VarnamalaTheme.radiusLarge),
        border: Border.all(
          color: VarnamalaTheme.peacockTeal.withValues(alpha: 0.12),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
          ),
          const SizedBox(height: 12),
          ...children,
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
                color: VarnamalaTheme.textSecondaryColor(context),
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

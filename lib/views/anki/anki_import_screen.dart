// Flutter imports:
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';

// Package imports:
import 'package:auto_route/auto_route.dart';
import 'package:crypto/crypto.dart';
import 'package:provider/provider.dart';

// Project imports:
import 'package:varnamala/application/anki/anki_card_adapter.dart';
import 'package:varnamala/application/anki/anki_deck_assembler.dart';
import 'package:varnamala/application/anki/anki_importer.dart';
import 'package:varnamala/application/anki/anki_models.dart';
import 'package:varnamala/application/anki/anki_srs_migrator.dart';
import 'package:varnamala/application/course_provider.dart';
import 'package:varnamala/application/srs_provider.dart';
import 'package:varnamala/data/anki_import_dao.dart';
import 'package:varnamala/data/course_database.dart';
import 'package:varnamala/data/course_repository.dart';
import 'package:varnamala/di/injection.dart';
import 'package:varnamala/domain/audio/anki_audio_resolver.dart';
import 'package:varnamala/l10n/app_localizations.dart';
import 'package:varnamala/utils/ohos_file_picker.dart';
import 'package:varnamala/views/theme.dart';

/// Import strategy when collisions are detected.
enum ImportStrategy { merge, skipExisting, forceReplace, appendAsNew }

/// Anki import wizard screen. Guides the user through:
/// 1. File selection
/// 2. Parsing + preview (deck structure, notetype mapping, collision report)
/// 3. Strategy selection
/// 4. Import execution with progress
@RoutePage()
class AnkiImportPage extends StatefulWidget {
  const AnkiImportPage({super.key});

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

  // Preview data
  Map<int, NotetypeMapping> _mappings = {};
  int _newCount = 0;
  int _existingCount = 0;
  ImportStrategy _strategy = ImportStrategy.merge;

  // Incremental-update detection (computed at parse time)
  String? _sourceHash;
  AnkiImportRecord? _existingImport;

  // Progress
  String _progressMessage = '';
  double _progress = 0; // 0..1, 0 means indeterminate
  bool _cancelRequested = false;
  AnkiImportSummary? _summary;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(AppLocalizations.of(context)!.ankiImportTitle),
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
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.upload_file_rounded,
              size: 80,
              color: VarnamalaTheme.peacockTeal.withValues(alpha: 0.6),
            ),
            const SizedBox(height: 24),
            Text(
              AppLocalizations.of(context)!.ankiImportSelectTitle,
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
            ),
            const SizedBox(height: 12),
            Text(
              AppLocalizations.of(context)!.ankiImportSelectSubtitle,
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
              label: Text(AppLocalizations.of(context)!.ankiChooseFile),
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
          ],
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
          Text(AppLocalizations.of(context)!.ankiParsing),
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
            child: Text(AppLocalizations.of(context)!.commonCancel),
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
          title: AppLocalizations.of(context)!.ankiCollectionSummary,
          children: [
            _InfoRow(AppLocalizations.of(context)!.ankiDecksLabel, '${collection.decks.length}'),
            _InfoRow(AppLocalizations.of(context)!.ankiNotesLabel, '${collection.notes.length}'),
            _InfoRow(AppLocalizations.of(context)!.ankiCardsLabel, '${collection.cards.length}'),
            _InfoRow(AppLocalizations.of(context)!.ankiMediaFilesLabel, '${collection.media.length}'),
          ],
        ),
        const SizedBox(height: 16),

        // Deck structure
        _InfoCard(
          title: AppLocalizations.of(context)!.ankiDeckStructure,
          children: [
            for (final deck in collection.decks.values)
              _InfoRow(deck.name, AppLocalizations.of(context)!.ankiDeckCardCount(deck.cardCount)),
          ],
        ),
        const SizedBox(height: 16),

        // Notetype mappings
        _InfoCard(
          title: AppLocalizations.of(context)!.ankiNotetypeMapping,
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
          title: AppLocalizations.of(context)!.ankiCollisionReport,
          children: [
            _InfoRow(AppLocalizations.of(context)!.ankiNewCards, '$_newCount'),
            _InfoRow(AppLocalizations.of(context)!.ankiExistingCards, '$_existingCount'),
          ],
        ),
        const SizedBox(height: 16),

        // Strategy selection
        Text(
          AppLocalizations.of(context)!.ankiImportStrategy,
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
            AppLocalizations.of(context)!.commonImport,
            style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
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
              ? AppLocalizations.of(context)!.ankiPreparingImport
              : _progressMessage),
          const SizedBox(height: 24),
          TextButton(
            onPressed: () {
              setState(() {
                _cancelRequested = true;
              });
            },
            child: Text(AppLocalizations.of(context)!.commonCancel),
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
              AppLocalizations.of(context)!.ankiImportComplete,
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
            ),
            const SizedBox(height: 16),
            if (summary != null) ...[
              Text(AppLocalizations.of(context)!.ankiCardsImported(summary.cardCount)),
              Text(AppLocalizations.of(context)!.ankiLessonsCreated(summary.lessonCount)),
              if (summary.wordEntryCount > 0)
                Text(AppLocalizations.of(context)!.ankiVocabAdded(summary.wordEntryCount)),
            ],
            const SizedBox(height: 32),
            ElevatedButton(
              onPressed: () => context.router.maybePop(),
              style: ElevatedButton.styleFrom(
                backgroundColor: VarnamalaTheme.peacockTeal,
                foregroundColor: VarnamalaTheme.textOnPrimary,
                padding:
                    const EdgeInsets.symmetric(horizontal: 32, vertical: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: Text(AppLocalizations.of(context)!.commonDone),
            ),
          ],
        ),
      ),
    );
  }

  // ─── Actions ────────────────────────────────────────────────────────

  Future<void> _pickFile() async {
    try {
      // On Android, .apkg/.colpkg have no registered MIME type, so
      // FileType.custom + allowedExtensions makes the native plugin error out
      // silently (MimeTypeMap returns null for both → empty mime array →
      // "Unsupported filter" error → picker never opens). Use FileType.any so
      // the system file chooser opens; we validate the extension afterward.
      final result = await OhosFilePicker.pickFiles(
        allowedExtensions: const ['apkg', 'colpkg'],
        dialogTitle: AppLocalizations.of(context)!.ankiImportDialogTitle,
      );

      if (result == null || result.files.isEmpty) return;
      final path = result.files.single.path;
      if (path == null) return;

      final ext = path.toLowerCase();
      if (!ext.endsWith('.apkg') && !ext.endsWith('.colpkg')) {
        setState(() => _error = AppLocalizations.of(context)!.ankiPickFileError);
        return;
      }

      setState(() {
        _filePath = path;
        _error = null;
        _step = 1;
      });

      await _parseFile(path);
    } catch (e) {
      setState(() {
        _error = AppLocalizations.of(context)!.ankiPickFileFailed(e);
        _step = 0;
      });
    }
  }

  Future<void> _parseFile(String path) async {
    setState(() {
      _cancelRequested = false;
      _progress = 0;
      _progressMessage = '';
    });
    try {
      final collection = await _importer.parse(
        path,
        onProgress: (p, msg) {
          if (mounted) setState(() { _progress = p; _progressMessage = msg; });
        },
        isCancelled: () => _cancelRequested,
      );

      // Infer notetype mappings
      final mappings = <int, NotetypeMapping>{};
      for (final entry in collection.notetypes.entries) {
        mappings[entry.key] = AnkiCardAdapter.inferMapping(entry.value);
      }

      // Compute the source hash now so the preview can detect re-imports
      // and the execute step doesn't re-read the whole file.
      final hash = sha256.convert(File(path).readAsBytesSync()).toString();

      // Real collision report:
      // - Same file imported before (hash match) → ids are deterministic
      //   (`anki-<importId>-n<noteId>`), so count notes already in the SRS
      //   queue under the previous importId as "existing".
      // - Otherwise everything is new.
      final dao = AnkiImportDao(getIt<CourseDatabase>());
      final existingImport = await dao.findByHash(hash);
      var existingCount = 0;
      if (existingImport != null) {
        final srsIds = context.read<SrsProvider>().state.keys.toSet();
        final prefix = 'anki-${existingImport.importId}-n';
        existingCount =
            collection.notes.where((n) => srsIds.contains('$prefix${n.id}')).length;
      }

      setState(() {
        _collection = collection;
        _mappings = mappings;
        _sourceHash = hash;
        _existingImport = existingImport;
        _newCount = collection.notes.length - existingCount;
        _existingCount = existingCount;
        // A re-import defaults to merge (update in place); first import keeps
        // merge as well — it behaves identically when nothing exists.
        _strategy = ImportStrategy.merge;
        _step = 2;
      });
    } on AnkiImportCancelled {
      // User pressed cancel — nothing was written; return to file picker.
      setState(() {
        _step = 0;
        _progress = 0;
        _progressMessage = '';
      });
    } catch (e) {
      setState(() {
        _error = AppLocalizations.of(context)!.ankiParseFailed(e);
        _step = 0;
      });
    }
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
      _progressMessage = AppLocalizations.of(context)!.ankiPreparingImport;
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
        effectiveCollection = collection.copyWith(
          notes: keptNotes,
          cards: collection.cards
              .where((c) => keptNoteIds.contains(c.nid))
              .toList(),
        );
      }

      setState(() => _progressMessage = AppLocalizations.of(context)!.ankiAssemblingCourse);

      // Assemble and write course tree
      final assembler = AnkiDeckAssembler();
      final summary = await assembler.assemble(
        collection: effectiveCollection,
        importId: importId,
        repo: repo,
        mappingOverrides: _mappings,
        onProgress: (p, msg) {
          if (mounted) setState(() { _progress = p; _progressMessage = msg; });
        },
        isCancelled: () => _cancelRequested,
      );

      if (_cancelRequested) {
        setState(() { _step = 2; _progress = 0; });
        return;
      }

      setState(() => _progressMessage = AppLocalizations.of(context)!.ankiMigratingSrs);

      // Migrate SRS state
      final migrator = AnkiSrsMigrator();
      await migrator.migrate(
        cards: effectiveCollection.cards,
        importId: importId,
        srsProvider: srsProvider,
      );

      setState(() => _progressMessage = AppLocalizations.of(context)!.ankiSavingMetadata);

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
        _error = AppLocalizations.of(context)!.ankiImportFailed(e);
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
    final l = AppLocalizations.of(context)!;
    return switch (s) {
      ImportStrategy.merge => l.ankiStrategyMerge,
      ImportStrategy.skipExisting => l.ankiStrategySkipExisting,
      ImportStrategy.forceReplace => l.ankiStrategyForceReplace,
      ImportStrategy.appendAsNew => l.ankiStrategyAppendAsNew,
    };
  }

  String _strategyDescription(BuildContext context, ImportStrategy s) {
    final l = AppLocalizations.of(context)!;
    return switch (s) {
      ImportStrategy.merge => l.ankiStrategyMergeDesc,
      ImportStrategy.skipExisting => l.ankiStrategySkipExistingDesc,
      ImportStrategy.forceReplace => l.ankiStrategyForceReplaceDesc,
      ImportStrategy.appendAsNew => l.ankiStrategyAppendAsNewDesc,
    };
  }
}

// ─── Shared widgets ─────────────────────────────────────────────────

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
        children: [
          Text(
            label,
            style: TextStyle(
              color: VarnamalaTheme.textSecondaryColor(context),
            ),
          ),
          Text(
            value,
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }
}

// Dart imports:
import 'dart:async';

// Flutter imports:
import 'package:flutter/material.dart';

// Package imports:
import 'package:auto_route/auto_route.dart';


// Project imports:
import 'package:turna/application/anki_official/review/formal_review_launcher.dart';
import 'package:turna/application/anki_official/browser/official_anki_source_aware_browser.dart';
import 'package:turna/application/anki_official/engine/official_formal_due_repository.dart';
import 'package:turna/application/anki_official/migration/official_anki_engine_kind.dart';
import 'package:turna/application/anki_official/official_anki_catalog_service.dart';
import 'package:turna/application/anki_official/official_anki_composition.dart';
import 'package:turna/application/anki_official/official_anki_feature_flags.dart';
import 'package:turna/core/logger.dart';
import 'package:turna/application/anki_official/official_anki_ids.dart';
import 'package:turna/core/theme.dart';
import 'package:turna/l10n/app_strings.dart';
import 'package:turna/views/widgets/turna_select.dart';

@RoutePage()
class AnkiCardBrowserPage extends StatefulWidget {
  final String importId;
  final String title;
  final String? sectionId;

  const AnkiCardBrowserPage({
    super.key,
    required this.importId,
    required this.title,
    this.sectionId,
  });

  @override
  State<AnkiCardBrowserPage> createState() => _AnkiCardBrowserPageState();
}

class _AnkiCardBrowserPageState extends State<AnkiCardBrowserPage> {
  final _searchController = TextEditingController();
  final _tagController = TextEditingController();
  Timer? _debounce;
  List<SourceAwareBrowserCard> _officialRows = const [];
  bool _loading = true;
  int? _flag;
  bool? _marked;
  bool? _suspended;
  bool? _buried;
  int? _deckId;
  Map<int, String> _deckOptions = const {};
  String? _officialUnavailableReason;
  String? _loadError;
  final OfficialAnkiPreviewCache _previewCache = OfficialAnkiPreviewCache();
  OfficialAnkiSourceAwareBrowser? _browser;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _searchController.dispose();
    _tagController.dispose();
    super.dispose();
  }

  /// Doc 38 P4-A: filter chips / deck dropdown / tag field share the search
  /// box's 250ms debounce so a quick sequence of taps does not fire one full
  /// search per tap.
  void _scheduleLoad() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 250), _load);
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _loadError = null;
    });
    try {
      await _loadInner();
    } catch (error) {
      // A thrown search used to leave `_loading` true forever (spinner
      // stuck, no retry). Surface the failure and keep the last rows.
      if (!mounted) return;
      setState(() {
        _loadError = error.toString();
        _loading = false;
      });
    }
  }

  Future<void> _loadInner() async {
    // Doc 34 W7: Official-first sources are browsed from the Official catalog
    // and must not depend on Legacy NoteStore rows.
    const catalogService = OfficialAnkiCatalogService();
    // Doc 38 P4-A: one long-lived browser (and preview LRU) for the page
    // so re-searches and row rebuilds hit the cache instead of the FFI.
    final browser = _browser ??= catalogService.browser(
      previewCache: _previewCache,
    );
    if (browser != null && catalogService.isOfficialSource(widget.importId)) {
      final result = await browser.searchWithAvailability(
        importOrSourceId: widget.importId,
        filter: OfficialBrowserFilter(
          query: _searchController.text,
          tag: _tagController.text,
          deckId: _deckId,
          flag: _flag,
          marked: _marked,
          suspended: _suspended,
          buried: _buried,
        ),
        ownerHint: AnkiEngineKind.official,
      );
      // Plan P4: the deck dropdown needs only the distinct deck ids — a
      // dedicated query, not a full card-descriptor materialization.
      final deckIds =
          catalogService.deckIdsForSource(widget.importId).toSet();
      final names = <int, String>{for (final id in deckIds) id: '#$id'};
      final engine = OfficialAnkiCompositionRoot.engine;
      if (engine != null) {
        try {
          for (final deck in await engine.listDeckTree()) {
            if (deckIds.contains(deck.deckId)) names[deck.deckId] = deck.name;
          }
        } catch (suppressed) {
          logger.w('[AnkiCardBrowserPage] suppressed error: $suppressed');
        }
      }
      if (!mounted) return;
      setState(() {
        _officialRows = result.rows;
        _officialUnavailableReason = result.available ? null : result.reason;
        _deckOptions = names;
        _loading = false;
      });
      return;
    }
    // Legacy NoteStore browsing is retired (plan P1): anything that does
    // not resolve to an Official source fails closed with a visible reason.
    if (!mounted) return;
    setState(() {
      _officialRows = const [];
      _officialUnavailableReason = 'legacy_note_store_retired';
      _loading = false;
    });
  }

  void _onSearchChanged(String _) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 250), _load);
  }

  Future<void> _toggleOfficial(SourceAwareBrowserCard row) async {
    final browser = _browser;
    if (browser == null) return;
    await browser.setOfficialSuspended(
      sourceId: row.sourceId,
      cardId: row.cardId,
      suspended: !row.suspended,
    );
    await _load();
  }

  void _openFormalReview(BuildContext context) {
    final importId = widget.importId.isNotEmpty
        ? widget.importId
        : LegacyAnkiIdentifiers.importIdFromSectionId(widget.sectionId ?? '');
    unawaited(
      const FormalReviewLauncher().open(
        context,
        entry: FormalReviewEntryKind.deckSection,
        courseId: importId.isEmpty ? 'anki' : 'anki-$importId',
        sectionId: widget.sectionId,
        officialOwner: OfficialFormalDueRepository.instance.officialImportIds
            .contains(importId),
        schedulerRuntimeAvailable:
            OfficialAnkiFeatureFlags.current.allowsOfficialScheduler,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(AppStrings.ankiBrowserPageTitle(widget.title)),
        actions: [
          IconButton(
            tooltip: AppStrings.ankiReviewAll,
            icon: const Icon(Icons.play_arrow_rounded),
            onPressed: () => _openFormalReview(context),
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: TextField(
              controller: _searchController,
              onChanged: _onSearchChanged,
              decoration: InputDecoration(
                hintText: AppStrings.ankiBrowserSearchHint,
                prefixIcon: const Icon(Icons.search),
                suffixIcon: _searchController.text.isEmpty
                    ? null
                    : IconButton(
                        tooltip: AppStrings.commonClear,
                        icon: const Icon(Icons.clear),
                        onPressed: () {
                          _searchController.clear();
                          unawaited(_load());
                        },
                      ),
                border: const OutlineInputBorder(),
              ),
            ),
          ),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Row(
              children: [
                TurnaFilterChip(
                  label: AppStrings.ankiBrowserMarked,
                  selected: _marked == true,
                  onSelected: (value) {
                    setState(() => _marked = value ? true : null);
                    _scheduleLoad();
                  },
                ),
                const SizedBox(width: 8),
                TurnaFilterChip(
                  label: AppStrings.ankiBrowserBuried,
                  selected: _buried == true,
                  onSelected: (value) {
                    setState(() => _buried = value ? true : null);
                    _scheduleLoad();
                  },
                ),
                const SizedBox(width: 8),
                TurnaFilterChip(
                  label: AppStrings.ankiBrowserSuspended,
                  selected: _suspended == true,
                  onSelected: (value) {
                    setState(() => _suspended = value ? true : null);
                    _scheduleLoad();
                  },
                ),
                const SizedBox(width: 8),
                for (final entry in const [
                  (1, Colors.red),
                  (2, Colors.orange),
                  (3, Colors.blue),
                  (4, Colors.green),
                ]) ...[
                  TurnaFilterChip(
                    avatar: Icon(Icons.flag, color: entry.$2, size: 16),
                    label: '${entry.$1}',
                    selected: _flag == entry.$1,
                    onSelected: (value) {
                      setState(() => _flag = value ? entry.$1 : null);
                      _scheduleLoad();
                    },
                  ),
                  const SizedBox(width: 8),
                ],
              ],
            ),
          ),
          if (_officialUnavailableReason == null)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Row(
                children: [
                  Expanded(
                    child: DropdownButtonFormField<int?>(
                      initialValue: _deckId,
                      decoration: InputDecoration(
                        labelText: AppStrings.ankiDecksLabel,
                        isDense: true,
                      ),
                      items: [
                        DropdownMenuItem<int?>(
                          value: null,
                          child: Text(AppStrings.ankiBrowserAllDecks),
                        ),
                        for (final entry in _deckOptions.entries)
                          DropdownMenuItem<int?>(
                            value: entry.key,
                            child: Text(entry.value),
                          ),
                      ],
                      onChanged: (value) {
                        setState(() => _deckId = value);
                        _scheduleLoad();
                      },
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextField(
                      controller: _tagController,
                      onChanged: _onSearchChanged,
                      decoration: InputDecoration(
                        labelText: AppStrings.ankiBrowserTagsLabel,
                        isDense: true,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _loadError != null
                    ? Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(AppStrings.ankiBrowserLoadFailed(_loadError!),
                                textAlign: TextAlign.center),
                            const SizedBox(height: 12),
                            FilledButton(
                              onPressed: _load,
                              child: Text(AppStrings.commonRetry),
                            ),
                          ],
                        ),
                      )
                    : _officialUnavailableReason != null
                        ? Center(
                            child: Text(
                              AppStrings.ankiBrowserOfficialUnavailable(
                                  _officialUnavailableReason!),
                              textAlign: TextAlign.center,
                            ),
                          )
                        : (_officialRows.isEmpty
                                ? Center(
                                    child:
                                        Text(AppStrings.ankiBrowserNoMatches))
                                : ListView.builder(
                                    padding: const EdgeInsets.fromLTRB(
                                        12, 0, 12, 20),
                                    itemCount: _officialRows.length,
                                    itemBuilder: (context, index) {
                                      final row = _officialRows[index];
                                      return Card(
                                        child: ListTile(
                                          leading: _FlagIcon(flag: row.flag),
                                          title: _OfficialPreviewText(
                                            browser: _browser,
                                            row: row,
                                          ),
                                          subtitle: Text(
                                            'Official #${row.cardId} · note #${row.noteId}'
                                            '${row.suspended ? ' · ${AppStrings.ankiBrowserSuspended}' : ''}'
                                            '${row.buried ? ' · ${AppStrings.ankiBrowserBuried}' : ''}'
                                            '${row.marked ? ' · ${AppStrings.ankiBrowserMarked}' : ''}',
                                            style: TextStyle(
                                              color: TurnaTheme.textHintColor(
                                                  context),
                                            ),
                                          ),
                                          trailing: PopupMenuButton<String>(
                                            onSelected: (value) {
                                              if (value == 'review') {
                                                _openFormalReview(context);
                                              } else if (value == 'suspend') {
                                                unawaited(_toggleOfficial(row));
                                              }
                                            },
                                            itemBuilder: (context) => [
                                              PopupMenuItem(
                                                value: 'review',
                                                child: Text(AppStrings
                                                    .ankiBrowserGoReview),
                                              ),
                                              PopupMenuItem(
                                                value: 'suspend',
                                                child: Text(
                                                  row.suspended
                                                      ? AppStrings
                                                          .ankiBrowserUnsuspend
                                                      : AppStrings
                                                          .ankiCardSuspend,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                      );
                                    },
                                  ))          ),
        ],
      ),
    );
  }

}

/// Doc 38 P4-A: the list row renders lazily — an empty preview triggers one
/// `previewFor` load (single renderCard FFI per card, LRU-cached); cached
/// rows paint with zero FFI. Detail/flip views keep full renderCard.
class _OfficialPreviewText extends StatefulWidget {
  const _OfficialPreviewText({required this.browser, required this.row});

  final OfficialAnkiSourceAwareBrowser? browser;
  final SourceAwareBrowserCard row;

  @override
  State<_OfficialPreviewText> createState() => _OfficialPreviewTextState();
}

class _OfficialPreviewTextState extends State<_OfficialPreviewText> {
  String _front = '';
  String _back = '';

  @override
  void initState() {
    super.initState();
    _front = widget.row.frontPreview;
    _back = widget.row.backPreview;
    if (_front.isEmpty) {
      unawaited(_load());
    }
  }

  Future<void> _load() async {
    final browser = widget.browser;
    if (browser == null) return;
    final preview = await browser.previewFor(widget.row.cardId);
    if (!mounted) return;
    if (preview.front == _front && preview.back == _back) return;
    setState(() {
      _front = preview.front;
      _back = preview.back;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_front.isEmpty) {
      return Text('card #${widget.row.cardId}',
          maxLines: 2, overflow: TextOverflow.ellipsis);
    }
    final back = _back.isEmpty ? '' : '  ·  $_back';
    return Text(
      '$_front$back',
      maxLines: 2,
      overflow: TextOverflow.ellipsis,
    );
  }
}

class _FlagIcon extends StatelessWidget {
  final int flag;
  const _FlagIcon({required this.flag});

  @override
  Widget build(BuildContext context) {
    if (flag == 0) {
      return const Icon(Icons.style_outlined, color: TurnaTheme.brandTeal);
    }
    final color = switch (flag) {
      1 => Colors.red,
      2 => Colors.orange,
      3 => Colors.blue,
      4 => Colors.green,
      _ => TurnaTheme.brandTeal,
    };
    return Icon(Icons.flag, color: color);
  }
}

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
import 'package:turna/views/widgets/directory_rows.dart';
import 'package:turna/views/widgets/search_field.dart';
import 'package:turna/views/widgets/turna_select.dart';

/// 卡牌浏览器 ——「湿地雾光」阅读目录版式：正面摘要 + 元信息的
/// [DirectoryEntryRow] 行（发丝线，不是卡）；搜索与标签走 [TurnaSearchField]
/// （防抖内建，页内不再手写输入防抖 Timer）。
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

  /// Doc 38 P4-A: filter chips / deck dropdown share a short burst debounce
  /// so a quick sequence of taps does not fire one full search per tap. 文本
  /// 输入的防抖已由 TurnaSearchField 内建，这里只承载非文本控件的连击。
  Timer? _burstDebounce;
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

  /// Doc 38 P4-A: 懒加载正面摘要的内存态（cardId → front/back）。浏览器
  /// 自带 LRU，这里只记「已取回的终值」让行随 setState 升级。
  final Map<int, (String front, String back)> _loadedPreviews = {};
  final Set<int> _previewsInFlight = {};

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  @override
  void dispose() {
    _burstDebounce?.cancel();
    _searchController.dispose();
    _tagController.dispose();
    super.dispose();
  }

  void _scheduleLoad() {
    _burstDebounce?.cancel();
    _burstDebounce = Timer(const Duration(milliseconds: 250), _load);
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
      final deckIds = catalogService.deckIdsForSource(widget.importId).toSet();
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

  /// 懒取一张卡的正面摘要（单次 renderCard FFI，浏览器侧 LRU 缓存）。
  Future<void> _ensurePreview(SourceAwareBrowserCard row) async {
    final browser = _browser;
    if (browser == null || _previewsInFlight.contains(row.cardId)) return;
    _previewsInFlight.add(row.cardId);
    try {
      final preview = await browser.previewFor(row.cardId);
      if (!mounted) return;
      final cached = _loadedPreviews[row.cardId];
      if (cached != null &&
          cached.$1 == preview.front &&
          cached.$2 == preview.back) {
        return;
      }
      setState(() {
        _loadedPreviews[row.cardId] = (preview.front, preview.back);
      });
    } finally {
      _previewsInFlight.remove(row.cardId);
    }
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
            child: TurnaSearchField(
              controller: _searchController,
              hint: AppStrings.ankiBrowserSearchHint,
              searching: _loading,
              onDebouncedChanged: (_) => unawaited(_load()),
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
                  // 熟识度 1-4 用品牌语义色，不用 Colors.* 原色 —— 后者在
                  // 深色 / 高对比模式下不随主题走，会突然变得刺眼或发灰。
                  (1, TurnaTheme.error),
                  (2, TurnaTheme.warning),
                  (3, TurnaTheme.brandSky),
                  (4, TurnaTheme.leagueEmerald),
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
                    child: TurnaSearchField(
                      controller: _tagController,
                      hint: AppStrings.ankiBrowserTagsLabel,
                      onDebouncedChanged: (_) => unawaited(_load()),
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
                            Text(
                              AppStrings.ankiBrowserLoadFailed(_loadError!),
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
                                child: Text(AppStrings.ankiBrowserNoMatches))
                            : ListView.builder(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 16,
                                  vertical: 4,
                                ),
                                itemCount: _officialRows.length,
                                itemBuilder: (context, index) {
                                  final row = _officialRows[index];
                                  return _buildEntryRow(context, row);
                                },
                              )),
          ),
        ],
      ),
    );
  }

  /// 阅读目录行：正面摘要（懒加载）+ 卡片元信息，发丝线分隔。
  Widget _buildEntryRow(BuildContext context, SourceAwareBrowserCard row) {
    final lazy = _loadedPreviews[row.cardId];
    final front = row.frontPreview.isNotEmpty
        ? row.frontPreview
        : lazy?.$1 ?? '';
    final back = row.backPreview.isNotEmpty
        ? row.backPreview
        : lazy?.$2 ?? '';
    if (front.isEmpty && _browser != null) {
      // 空 preview → 一次 renderCard FFI（Doc 38 P4-A），取回后行升级。
      unawaited(_ensurePreview(row));
    }
    final states = [
      if (row.suspended) AppStrings.ankiBrowserSuspended,
      if (row.buried) AppStrings.ankiBrowserBuried,
      if (row.marked) AppStrings.ankiBrowserMarked,
    ];
    final meta = StringBuffer('Official #${row.cardId} · note #${row.noteId}');
    for (final state in states) {
      meta.write(' · $state');
    }

    return DirectoryEntryRow(
      key: ValueKey('browser-card-${row.cardId}'),
      title: front.isEmpty ? 'card #${row.cardId}' : front,
      subtitle: back.isEmpty ? null : back,
      meta: meta.toString(),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _FlagIcon(flag: row.flag),
          PopupMenuButton<String>(
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
                child: Text(AppStrings.ankiBrowserGoReview),
              ),
              PopupMenuItem(
                value: 'suspend',
                child: Text(
                  row.suspended
                      ? AppStrings.ankiBrowserUnsuspend
                      : AppStrings.ankiCardSuspend,
                ),
              ),
            ],
          ),
        ],
      ),
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
      1 => TurnaTheme.error,
      2 => TurnaTheme.warning,
      3 => TurnaTheme.brandSky,
      4 => TurnaTheme.leagueEmerald,
      _ => TurnaTheme.brandTeal,
    };
    return Icon(Icons.flag, color: color);
  }
}

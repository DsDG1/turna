// Dart imports:
import 'dart:async';

// Flutter imports:
import 'package:flutter/material.dart';

// Package imports:
import 'package:auto_route/auto_route.dart';
import 'package:provider/provider.dart';

// Project imports:
import 'package:turna/application/anki/formal_review_launcher.dart';
import 'package:turna/application/anki_official/browser/official_anki_source_aware_browser.dart';
import 'package:turna/application/anki_official/engine/official_formal_due_repository.dart';
import 'package:turna/application/anki_official/migration/official_anki_engine_kind.dart';
import 'package:turna/application/anki_official/official_anki_composition.dart';
import 'package:turna/application/anki_official/official_anki_feature_flags.dart';
import 'package:turna/application/anki_official/storage/official_anki_source_dao.dart';
import 'package:turna/data/anki_note_dao.dart';
import 'package:turna/application/srs_provider.dart';
import 'package:turna/di/injection.dart';
import 'package:turna/application/anki_official/official_anki_ids.dart';
import 'package:turna/views/theme.dart';
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
  final _dao = getIt<AnkiNoteDao>();
  Timer? _debounce;
  List<AnkiCardBrowserRecord> _rows = const [];
  List<SourceAwareBrowserCard> _officialRows = const [];
  bool _loading = true;
  bool _officialSource = false;
  int? _flag;
  bool? _marked;
  bool? _suspended;
  bool? _buried;
  int? _deckId;
  Map<int, String> _deckOptions = const {};
  String? _officialUnavailableReason;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _searchController.dispose();
    _tagController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    // Doc 34 W7: Official-first sources are browsed from the Official catalog
    // and must not depend on Legacy NoteStore rows.
    final catalog = OfficialAnkiCompositionRoot.readOnlyCatalog;
    if (catalog != null) {
      final sources = OfficialAnkiSourceDao(catalog);
      final browser = OfficialAnkiSourceAwareBrowser(
        sources: sources,
        legacyNotes: _dao,
        engine: OfficialAnkiCompositionRoot.engine,
      );
      final source = sources.findById(widget.importId);
      if (source != null) {
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
        final cards = sources.listCards(widget.importId);
        final deckIds = cards.map((card) => card.deckId).toSet();
        final names = <int, String>{for (final id in deckIds) id: '#$id'};
        final engine = OfficialAnkiCompositionRoot.engine;
        if (engine != null) {
          try {
            for (final deck in await engine.listDeckTree()) {
              if (deckIds.contains(deck.deckId)) names[deck.deckId] = deck.name;
            }
          } catch (_) {}
        }
        if (!mounted) return;
        setState(() {
          _officialSource = true;
          _officialRows = result.rows;
          _officialUnavailableReason = result.available ? null : result.reason;
          _deckOptions = names;
          _rows = const [];
          _loading = false;
        });
        return;
      }
    }
    final rows = await _dao.searchNotes(
      widget.importId,
      _searchController.text,
      flag: _flag,
      marked: _marked,
      suspended: _suspended,
    );
    if (!mounted) return;
    setState(() {
      _officialSource = false;
      _officialRows = const [];
      _officialUnavailableReason = null;
      _rows = rows;
      _loading = false;
    });
  }

  void _onSearchChanged(String _) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 250), _load);
  }

  Future<void> _toggleOfficial(SourceAwareBrowserCard row) async {
    final catalog = OfficialAnkiCompositionRoot.readOnlyCatalog;
    final engine = OfficialAnkiCompositionRoot.engine;
    if (catalog == null || engine == null) return;
    final browser = OfficialAnkiSourceAwareBrowser(
      sources: OfficialAnkiSourceDao(catalog),
      legacyNotes: _dao,
      engine: engine,
    );
    await browser.setOfficialSuspended(
      sourceId: row.sourceId,
      cardId: row.cardId,
      suspended: !row.suspended,
    );
    await _load();
  }

  Future<void> _toggle(AnkiCardBrowserRecord row,
      {bool? marked, bool? suspended}) async {
    await _dao.setCardState(
      row.card.importId,
      row.card.cardId,
      marked: marked,
      suspended: suspended,
    );
    if (suspended != null &&
        mounted &&
        !row.card.wordId.startsWith('official-anki-')) {
      await context.read<SrsProvider>().setWordFlags(
            row.card.wordId,
            suspended: suspended,
          );
    }
    await _load();
  }

  Future<void> _showDetails(AnkiCardBrowserRecord row) async {
    final projection = await _dao.projectionForCard(
      row.card.importId,
      row.card.cardId,
    );
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('卡片来源与识别诊断'),
        content: SizedBox(
          width: 560,
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                _DiagnosticRow('原始 Card', '#${row.card.cardId}'),
                _DiagnosticRow('原始 Note', '#${row.note.noteId}'),
                _DiagnosticRow('Note Type', '#${row.note.mid}'),
                _DiagnosticRow('Deck', '#${row.card.did}'),
                _DiagnosticRow('原卡渲染', row.card.renderMode),
                _DiagnosticRow(
                  '课程练习',
                  projection == null
                      ? '仅保留原卡（无派生记录）'
                      : '${_projectionKindLabel(projection.kind)} · '
                          '${_projectionStatusLabel(projection.status)}',
                ),
                if (projection != null && projection.evidence.isNotEmpty)
                  _DiagnosticRow(
                    '识别依据',
                    projection.evidence.entries
                        .map((entry) => '${entry.key}=${entry.value}')
                        .join('，'),
                  ),
                const SizedBox(height: 12),
                Text('原始字段',
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w700,
                        )),
                const SizedBox(height: 6),
                for (var i = 0; i < row.note.fields.length; i++) ...[
                  Text('字段 ${i + 1}',
                      style: TextStyle(
                        color: TurnaTheme.textHintColor(context),
                        fontWeight: FontWeight.w600,
                      )),
                  SelectableText(_preview([row.note.fields[i]])),
                  const SizedBox(height: 8),
                ],
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('关闭'),
          ),
        ],
      ),
    );
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
        officialOwner: OfficialFormalDueRepository.instance.officialImportIds.contains(importId),
        schedulerRuntimeAvailable:
            OfficialAnkiFeatureFlags.current.allowsOfficialScheduler,
      ),
    );
  }

  String _projectionKindLabel(String kind) => switch (kind) {
        'structured' => '派生结构化练习',
        'canonical' => 'Anki 原卡',
        _ => kind,
      };

  String _projectionStatusLabel(String status) => switch (status) {
        'generated' => '已生成',
        'fallback' => '识别冲突，已回退原卡',
        'fidelity_required' => '需按原模板显示',
        'not_materialized' => '按需加载',
        _ => status,
      };

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('${widget.title} · 浏览'),
        actions: [
          IconButton(
            tooltip: '开始复习',
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
                hintText: '搜索正面、背面或标签',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: _searchController.text.isEmpty
                    ? null
                    : IconButton(
                        icon: const Icon(Icons.clear),
                        onPressed: () {
                          _searchController.clear();
                          _load();
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
                  label: '已标记',
                  selected: _marked == true,
                  onSelected: (value) {
                    setState(() => _marked = value ? true : null);
                    _load();
                  },
                ),
                const SizedBox(width: 8),
                TurnaFilterChip(
                  label: '已埋藏',
                  selected: _buried == true,
                  onSelected: (value) {
                    setState(() => _buried = value ? true : null);
                    _load();
                  },
                ),
                const SizedBox(width: 8),
                TurnaFilterChip(
                  label: '已暂停',
                  selected: _suspended == true,
                  onSelected: (value) {
                    setState(() => _suspended = value ? true : null);
                    _load();
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
                      _load();
                    },
                  ),
                  const SizedBox(width: 8),
                ],
              ],
            ),
          ),
          if (_officialSource)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Row(
                children: [
                  Expanded(
                    child: DropdownButtonFormField<int?>(
                      initialValue: _deckId,
                      decoration: const InputDecoration(
                        labelText: '牌组',
                        isDense: true,
                      ),
                      items: [
                        const DropdownMenuItem<int?>(
                          value: null,
                          child: Text('全部牌组'),
                        ),
                        for (final entry in _deckOptions.entries)
                          DropdownMenuItem<int?>(
                            value: entry.key,
                            child: Text(entry.value),
                          ),
                      ],
                      onChanged: (value) {
                        setState(() => _deckId = value);
                        _load();
                      },
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextField(
                      controller: _tagController,
                      onChanged: _onSearchChanged,
                      decoration: const InputDecoration(
                        labelText: '标签',
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
                : _officialUnavailableReason != null
                    ? Center(
                        child: Text(
                          'Official 卡片浏览暂不可用\n$_officialUnavailableReason',
                          textAlign: TextAlign.center,
                        ),
                      )
                    : _officialSource
                        ? (_officialRows.isEmpty
                            ? const Center(child: Text('没有匹配的卡片'))
                            : ListView.builder(
                                padding:
                                    const EdgeInsets.fromLTRB(12, 0, 12, 20),
                                itemCount: _officialRows.length,
                                itemBuilder: (context, index) {
                                  final row = _officialRows[index];
                                  return Card(
                                    child: ListTile(
                                      leading: _FlagIcon(flag: row.flag),
                                      title: Text(
                                        row.frontPreview,
                                        maxLines: 2,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                      subtitle: Text(
                                        'Official #${row.cardId} · note #${row.noteId}'
                                        '${row.suspended ? ' · 已暂停' : ''}'
                                        '${row.buried ? ' · 已埋藏' : ''}'
                                        '${row.marked ? ' · 已标记' : ''}',
                                        style: TextStyle(
                                          color:
                                              TurnaTheme.textHintColor(context),
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
                                          const PopupMenuItem(
                                            value: 'review',
                                            child: Text('去复习'),
                                          ),
                                          PopupMenuItem(
                                            value: 'suspend',
                                            child: Text(
                                              row.suspended ? '取消暂停' : '暂停',
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  );
                                },
                              ))
                        : _rows.isEmpty
                            ? const Center(child: Text('没有匹配的卡片'))
                            : ListView.builder(
                                padding:
                                    const EdgeInsets.fromLTRB(12, 0, 12, 20),
                                itemCount: _rows.length,
                                itemBuilder: (context, index) {
                                  final row = _rows[index];
                                  return Card(
                                    child: ListTile(
                                      onTap: () => _showDetails(row),
                                      leading: _FlagIcon(flag: row.card.flag),
                                      title: Text(
                                        _preview(row.note.fields),
                                        maxLines: 2,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                      subtitle: Text(
                                        '#${row.card.cardId}  ${row.card.suspended ? '已暂停' : ''}${row.card.marked ? ' · 已标记' : ''}',
                                        style: TextStyle(
                                          color:
                                              TurnaTheme.textHintColor(context),
                                        ),
                                      ),
                                      trailing: PopupMenuButton<String>(
                                        onSelected: (value) {
                                          if (value == 'mark') {
                                            _toggle(row,
                                                marked: !row.card.marked);
                                          } else if (value == 'suspend') {
                                            _toggle(row,
                                                suspended: !row.card.suspended);
                                          } else if (value == 'review') {
                                            _openFormalReview(context);
                                          }
                                        },
                                        itemBuilder: (context) => [
                                          PopupMenuItem(
                                              value: 'review',
                                              child: const Text('去复习')),
                                          PopupMenuItem(
                                              value: 'mark',
                                              child: Text(row.card.marked
                                                  ? '取消标记'
                                                  : '标记')),
                                          PopupMenuItem(
                                              value: 'suspend',
                                              child: Text(row.card.suspended
                                                  ? '恢复'
                                                  : '暂停')),
                                        ],
                                      ),
                                    ),
                                  );
                                },
                              ),
          ),
        ],
      ),
    );
  }

  String _preview(List<String> fields) {
    final value = fields.join(' / ');
    return value
        .replaceAll(RegExp(r'<br\s*/?>', caseSensitive: false), ' ')
        .replaceAll(RegExp(r'<[^>]+>'), '')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }
}

class _DiagnosticRow extends StatelessWidget {
  final String label;
  final String value;

  const _DiagnosticRow(this.label, this.value);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 92,
            child: Text(
              label,
              style: TextStyle(
                color: TurnaTheme.textHintColor(context),
              ),
            ),
          ),
          Expanded(child: SelectableText(value)),
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
      1 => Colors.red,
      2 => Colors.orange,
      3 => Colors.blue,
      4 => Colors.green,
      _ => TurnaTheme.brandTeal,
    };
    return Icon(Icons.flag, color: color);
  }
}

// Dart imports:
import 'dart:async';

// Flutter imports:
import 'package:flutter/material.dart';

// Package imports:
import 'package:auto_route/auto_route.dart';
import 'package:provider/provider.dart';

// Project imports:
import 'package:turna/data/anki_note_dao.dart';
import 'package:turna/application/srs_provider.dart';
import 'package:turna/di/injection.dart';
import 'package:turna/routing/routing.gr.dart';
import 'package:turna/views/theme.dart';

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
  final _dao = getIt<AnkiNoteDao>();
  Timer? _debounce;
  List<AnkiCardBrowserRecord> _rows = const [];
  bool _loading = true;
  int? _flag;
  bool? _marked;
  bool? _suspended;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final rows = await _dao.searchNotes(
      widget.importId,
      _searchController.text,
      flag: _flag,
      marked: _marked,
      suspended: _suspended,
    );
    if (!mounted) return;
    setState(() {
      _rows = rows;
      _loading = false;
    });
  }

  void _onSearchChanged(String _) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 250), _load);
  }

  Future<void> _toggle(AnkiCardBrowserRecord row,
      {bool? marked, bool? suspended}) async {
    await _dao.setCardState(
      row.card.importId,
      row.card.cardId,
      marked: marked,
      suspended: suspended,
    );
    if (suspended != null && mounted) {
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
            onPressed: () => context.router.push(
              AnkiReviewSessionRoute(sectionId: widget.sectionId),
            ),
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
                FilterChip(
                  label: const Text('已标记'),
                  selected: _marked == true,
                  onSelected: (value) {
                    setState(() => _marked = value ? true : null);
                    _load();
                  },
                ),
                const SizedBox(width: 8),
                FilterChip(
                  label: const Text('已暂停'),
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
                  FilterChip(
                    avatar: Icon(Icons.flag, color: entry.$2, size: 16),
                    label: Text('${entry.$1}'),
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
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _rows.isEmpty
                    ? const Center(child: Text('没有匹配的卡片'))
                    : ListView.builder(
                        padding: const EdgeInsets.fromLTRB(12, 0, 12, 20),
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
                                  color: TurnaTheme.textHintColor(context),
                                ),
                              ),
                              trailing: PopupMenuButton<String>(
                                onSelected: (value) {
                                  if (value == 'mark') {
                                    _toggle(row, marked: !row.card.marked);
                                  } else if (value == 'suspend') {
                                    _toggle(row,
                                        suspended: !row.card.suspended);
                                  } else if (value == 'review') {
                                    context.router.push(AnkiReviewSessionRoute(
                                        sectionId: widget.sectionId));
                                  }
                                },
                                itemBuilder: (context) => [
                                  PopupMenuItem(
                                      value: 'review',
                                      child: const Text('去复习')),
                                  PopupMenuItem(
                                      value: 'mark',
                                      child: Text(
                                          row.card.marked ? '取消标记' : '标记')),
                                  PopupMenuItem(
                                      value: 'suspend',
                                      child: Text(
                                          row.card.suspended ? '恢复' : '暂停')),
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
      return const Icon(Icons.style_outlined, color: TurnaTheme.peacockTeal);
    }
    final color = switch (flag) {
      1 => Colors.red,
      2 => Colors.orange,
      3 => Colors.blue,
      4 => Colors.green,
      _ => TurnaTheme.peacockTeal,
    };
    return Icon(Icons.flag, color: color);
  }
}

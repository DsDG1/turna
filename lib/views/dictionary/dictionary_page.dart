// Flutter imports:
import 'package:flutter/material.dart';

// Package imports:
import 'package:auto_route/annotations.dart';

// Project imports:
import 'package:varnamala/application/audio_controller.dart';
import 'package:varnamala/application/dictionary_search.dart';
import 'package:varnamala/di/injection.dart';
import 'package:varnamala/views/theme.dart';

@RoutePage()
class DictionaryPage extends StatefulWidget {
  const DictionaryPage({super.key});

  @override
  State<DictionaryPage> createState() => _DictionaryPageState();
}

class _DictionaryPageState extends State<DictionaryPage> {
  final _controller = TextEditingController();
  List<DictionaryHit> _hits = const [];

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _onQueryChanged(String value) {
    setState(() => _hits = searchDictionary(value));
  }

  Future<void> _speak(DictionaryHit hit) async {
    final audio = getIt<AudioController>();
    final wordId = hit.speakAsWordId;
    if (wordId != null && wordId.isNotEmpty) {
      await audio.speakWord(wordId);
      return;
    }
    final text = hit.speakText ?? hit.title;
    if (text.isNotEmpty) await audio.speak(text);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: VarnamalaTheme.scaffoldBg(context),
      appBar: AppBar(
        title: Text(
          'Dictionary',
          style: Theme.of(context).textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w700,
              ),
        ),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
            child: TextField(
              controller: _controller,
              onChanged: _onQueryChanged,
              decoration: InputDecoration(
                hintText: 'Search Turkish or English…',
                prefixIcon: const Icon(Icons.search_rounded),
                filled: true,
                fillColor: VarnamalaTheme.inputFillColor(context),
                border: OutlineInputBorder(
                  borderRadius:
                      BorderRadius.circular(VarnamalaTheme.radiusMedium),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
          ),
          Expanded(
            child: _hits.isEmpty
                ? Center(
                    child: Text(
                      _controller.text.trim().isEmpty
                          ? 'Search vocabulary, expressions, and grammar'
                          : 'No matches',
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            color: VarnamalaTheme.textHintColor(context),
                          ),
                      textAlign: TextAlign.center,
                    ),
                  )
                : ListView.separated(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                    itemCount: _hits.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 8),
                    itemBuilder: (context, index) {
                      final hit = _hits[index];
                      return _DictionaryTile(
                        hit: hit,
                        onSpeak: () => _speak(hit),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

class _DictionaryTile extends StatelessWidget {
  final DictionaryHit hit;
  final VoidCallback onSpeak;

  const _DictionaryTile({required this.hit, required this.onSpeak});

  String get _kindLabel {
    switch (hit.kind) {
      case DictionaryHitKind.vocab:
        return 'Word';
      case DictionaryHitKind.expression:
        return 'Phrase';
      case DictionaryHitKind.grammar:
        return 'Grammar';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      color: VarnamalaTheme.cardBg(context),
      borderRadius: BorderRadius.circular(VarnamalaTheme.radiusMedium),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _kindLabel,
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          color: VarnamalaTheme.peacockTeal,
                          fontWeight: FontWeight.w700,
                        ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    hit.title,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w800,
                        ),
                  ),
                  if (hit.pronunciation != null &&
                      hit.pronunciation!.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(
                      hit.pronunciation!,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: VarnamalaTheme.textHintColor(context),
                            fontStyle: FontStyle.italic,
                          ),
                    ),
                  ],
                  const SizedBox(height: 4),
                  Text(
                    hit.subtitle,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: VarnamalaTheme.textSecondaryColor(context),
                        ),
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            IconButton(
              tooltip: 'Play pronunciation',
              onPressed: onSpeak,
              icon: const Icon(
                Icons.volume_up_rounded,
                color: VarnamalaTheme.peacockTeal,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

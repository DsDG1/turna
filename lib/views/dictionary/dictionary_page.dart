// Flutter imports:
import 'package:flutter/material.dart';

// Package imports:
import 'package:auto_route/annotations.dart';

// Project imports:
import 'package:turna/application/audio_controller.dart';
import 'package:turna/application/dictionary_search.dart';
import 'package:turna/application/smart_speech.dart';
import 'package:turna/di/injection.dart';
import 'package:turna/l10n/app_strings.dart';
import 'package:turna/views/theme.dart';

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
    if (text.isNotEmpty) {
      // Auto-detect the language so translations are read in their own voice.
      await audio.speak(text, languageCode: detectSpeakLanguage(text));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: TurnaTheme.scaffoldBg(context),
      appBar: AppBar(
        title: Text(
          AppStrings.dictionaryTitle,
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
                hintText: AppStrings.dictionarySearchHint,
                prefixIcon: const Icon(Icons.search_rounded),
                filled: true,
                fillColor: TurnaTheme.inputFillColor(context),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(TurnaTheme.radiusMedium),
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
                          ? AppStrings.dictionarySearchEmpty
                          : AppStrings.dictionaryNoMatches,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            color: TurnaTheme.textHintColor(context),
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

  String _kindLabel(BuildContext context) {
    final l10n = AppStrings;
    switch (hit.kind) {
      case DictionaryHitKind.vocab:
        return AppStrings.dictionaryKindWord;
      case DictionaryHitKind.expression:
        return AppStrings.dictionaryKindPhrase;
      case DictionaryHitKind.grammar:
        return AppStrings.dictionaryKindGrammar;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      color: TurnaTheme.cardBg(context),
      borderRadius: BorderRadius.circular(TurnaTheme.radiusMedium),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _kindLabel(context),
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          color: TurnaTheme.brandTeal,
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
                            color: TurnaTheme.textHintColor(context),
                            fontStyle: FontStyle.italic,
                          ),
                    ),
                  ],
                  const SizedBox(height: 4),
                  Text(
                    hit.subtitle,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: TurnaTheme.textSecondaryColor(context),
                        ),
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            IconButton(
              tooltip: AppStrings.dictionaryPlayPronunciation,
              onPressed: onSpeak,
              icon: const Icon(
                Icons.volume_up_rounded,
                color: TurnaTheme.brandTeal,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

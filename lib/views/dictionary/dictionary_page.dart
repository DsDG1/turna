// Flutter imports:
import 'package:flutter/material.dart';

// Package imports:
import 'package:auto_route/annotations.dart';
import 'package:provider/provider.dart';

// Project imports:
import 'package:turna/application/ai/ai_explain_prefs.dart';
import 'package:turna/application/ai/dictionary_ai_provider.dart';
import 'package:turna/application/ai/engine/ai_engine_config_holder.dart';
import 'package:turna/application/ai/hint_genres.dart';
import 'package:turna/application/audio_controller.dart';
import 'package:turna/application/dictionary_search.dart';
import 'package:turna/application/smart_speech.dart';
import 'package:turna/di/injection.dart';
import 'package:turna/l10n/app_strings.dart';
import 'package:turna/views/ai/components/ai_not_configured_panel.dart';
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
                      return DictionaryHitTile(
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

/// Single dictionary hit row with speak + AI enrich actions.
/// Public so widget tests can pump the real shipped tile.
class DictionaryHitTile extends StatelessWidget {
  final DictionaryHit hit;
  final VoidCallback onSpeak;

  const DictionaryHitTile({
    super.key,
    required this.hit,
    required this.onSpeak,
  });

  String _kindLabel(BuildContext context) {
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
              tooltip: AppStrings.aiDictEnrich,
              onPressed: () => _openAiEnrich(context, hit),
              icon: const Icon(
                Icons.auto_awesome_rounded,
                color: TurnaTheme.amethystLeague,
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

  void _openAiEnrich(BuildContext context, DictionaryHit hit) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: TurnaTheme.cardBg(context),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(TurnaTheme.radiusXLarge),
        ),
      ),
      builder: (sheetCtx) {
        AiExplainPrefsStore? prefs;
        try {
          prefs = context.read<AiExplainPrefsStore>();
        } catch (_) {}
        return ChangeNotifierProvider(
          create: (_) => DictionaryAiProvider(prefs: prefs),
          child: _DictionaryAiSheet(hit: hit),
        );
      },
    );
  }
}

class _DictionaryAiSheet extends StatefulWidget {
  const _DictionaryAiSheet({required this.hit});
  final DictionaryHit hit;

  @override
  State<_DictionaryAiSheet> createState() => _DictionaryAiSheetState();
}

class _DictionaryAiSheetState extends State<_DictionaryAiSheet> {
  bool _started = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _run());
  }

  Future<void> _run() async {
    if (_started || !mounted) return;
    _started = true;
    final config = context.read<AiEngineConfigHolder>().config;
    if (!config.isComplete) return;
    await context.read<DictionaryAiProvider>().enrich(
          config: config,
          language: 'Turkish',
          term: widget.hit.title,
          translation: widget.hit.subtitle,
        );
  }

  @override
  Widget build(BuildContext context) {
    final config = context.watch<AiEngineConfigHolder>().config;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              '${AppStrings.aiDictEnrich} · ${widget.hit.title}',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
            ),
            const SizedBox(height: 12),
            if (!config.isComplete)
              const AiNotConfiguredPanel(compact: true)
            else
              Consumer<DictionaryAiProvider>(
                builder: (context, p, _) {
                  if (p.state == DictionaryAiState.loading) {
                    return Padding(
                      padding: const EdgeInsets.all(24),
                      child: Column(
                        children: [
                          const CircularProgressIndicator(
                              color: TurnaTheme.brandTeal),
                          const SizedBox(height: 12),
                          Text(AppStrings.aiDictEnriching),
                        ],
                      ),
                    );
                  }
                  if (p.error != null) {
                    return Column(
                      children: [
                        Text(p.error!,
                            style: const TextStyle(color: TurnaTheme.error)),
                        TextButton(
                          onPressed: () {
                            _started = false;
                            _run();
                          },
                          child: Text(AppStrings.aiRetry),
                        ),
                      ],
                    );
                  }
                  final e = p.enrichment;
                  if (e == null) {
                    return Text(AppStrings.aiDictEnriching);
                  }
                  return _enrichmentBody(e);
                },
              ),
          ],
        ),
      ),
    );
  }

  Widget _enrichmentBody(DictionaryEnrichment e) {
    return ConstrainedBox(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.5,
      ),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (e.expandedGloss.isNotEmpty) ...[
              Text(e.expandedGloss),
              const SizedBox(height: 12),
            ],
            if (e.examples.isNotEmpty) ...[
              Text(
                AppStrings.aiDictExamples,
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
              for (final x in e.examples) Text('· $x'),
              const SizedBox(height: 12),
            ],
            if (e.mnemonic.isNotEmpty) ...[
              Text(
                AppStrings.aiDictMnemonic,
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
              Text(e.mnemonic),
            ],
            const SizedBox(height: 8),
            Text(
              AppStrings.aiDisclaimer,
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: TurnaTheme.textHintColor(context),
                  ),
            ),
          ],
        ),
      ),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:turna/application/anki_official/contract/official_anki_dto.dart';
import 'package:turna/application/anki_official/engine/official_anki_engine.dart';
import 'package:turna/application/anki_official/engine/official_anki_review_session.dart';
import 'package:turna/application/anki_official/official_anki_feature_flags.dart';
import 'package:turna/application/anki_official/official_anki_paths.dart';
import 'package:turna/views/anki_official/official_anki_reviewer_error_view.dart';
import 'package:turna/views/anki_official/official_anki_reviewer_page.dart';

/// Formal Official Review. Separate from preview/`canonicalLink`.
class OfficialAnkiReviewPage extends StatefulWidget {
  const OfficialAnkiReviewPage({
    super.key,
    required this.engine,
    required this.paths,
    this.deckId = 1,
    this.flags,
    this.session,
  });

  static const routeName = '/official-anki/review';

  final OfficialAnkiEngine engine;
  final OfficialAnkiPaths paths;
  final int deckId;
  final OfficialAnkiFeatureFlags? flags;
  final OfficialReviewSession? session;

  @override
  State<OfficialAnkiReviewPage> createState() => _OfficialAnkiReviewPageState();
}

class _OfficialAnkiReviewPageState extends State<OfficialAnkiReviewPage> {
  late final OfficialReviewSession _session;
  var _busy = true;

  @override
  void initState() {
    super.initState();
    _session = widget.session ??
        OfficialReviewSession(
          engine: widget.engine,
          flags: widget.flags ?? OfficialAnkiFeatureFlags.current,
        );
    _open();
  }

  Future<void> _open() async {
    try {
      await _session.openDeck(widget.deckId);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _run(Future<void> Function() work) async {
    setState(() => _busy = true);
    try {
      await work();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final flags = widget.flags ?? OfficialAnkiFeatureFlags.current;
    if (!flags.allowsOfficialScheduler) {
      return const Scaffold(
        body: OfficialAnkiReviewerErrorView(
          key: Key('official-review-flag-fail-closed'),
          messageKey: 'official_anki.scheduler_flag_fail_closed',
        ),
      );
    }
    if (_busy && _session.current == null && _session.congrats == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    final card = _session.current;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Official Review'),
        actions: [
          IconButton(
            key: const Key('official-review-undo'),
            onPressed: _busy ? null : () => _run(_session.undo),
            icon: const Icon(Icons.undo),
          ),
          IconButton(
            key: const Key('official-review-redo'),
            onPressed: _busy ? null : () => _run(_session.redo),
            icon: const Icon(Icons.redo),
          ),
        ],
      ),
      body: card == null
          ? _CongratsView(info: _session.congrats)
          : Column(
              children: [
                Expanded(
                  child: OfficialAnkiReviewerPage(
                    sourceId: 'review',
                    cardId: card.cardId,
                    paths: widget.paths,
                  ),
                ),
                if (_session.phase == OfficialReviewPhase.showingQuestion)
                  FilledButton(
                    key: const Key('official-review-show-answer'),
                    onPressed: () => setState(_session.showAnswer),
                    child: const Text('Show Answer'),
                  ),
                if (_session.phase == OfficialReviewPhase.showingAnswer)
                  _RatingRow(
                    labels: card.labels,
                    enabled: !_busy,
                    onRate: (rating) => _run(() => _session.answer(rating)),
                  ),
                OverflowBar(
                  children: [
                    TextButton(
                      key: const Key('official-review-bury'),
                      onPressed: _busy
                          ? null
                          : () => _run(
                                () => _session.buryOrSuspend(
                                  OfficialBuryOrSuspendAction.buryCard,
                                ),
                              ),
                      child: const Text('Bury'),
                    ),
                    TextButton(
                      key: const Key('official-review-suspend'),
                      onPressed: _busy
                          ? null
                          : () => _run(
                                () => _session.buryOrSuspend(
                                  OfficialBuryOrSuspendAction.suspendCards,
                                ),
                              ),
                      child: const Text('Suspend'),
                    ),
                  ],
                ),
              ],
            ),
    );
  }
}

class _RatingRow extends StatelessWidget {
  const _RatingRow({
    required this.labels,
    required this.enabled,
    required this.onRate,
  });

  final OfficialReviewIntervalLabels labels;
  final bool enabled;
  final ValueChanged<String> onRate;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(8),
      child: Row(
        children: [
          for (final entry in [
            ('again', 'Again', labels.again),
            ('hard', 'Hard', labels.hard),
            ('good', 'Good', labels.good),
            ('easy', 'Easy', labels.easy),
          ])
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: FilledButton(
                  key: Key('official-review-${entry.$1}'),
                  onPressed: enabled ? () => onRate(entry.$1) : null,
                  child: Text('${entry.$2}\n${entry.$3}', textAlign: TextAlign.center),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _CongratsView extends StatelessWidget {
  const _CongratsView({this.info});

  final OfficialCongratsInfo? info;

  @override
  Widget build(BuildContext context) {
    final data = info;
    return Center(
      child: Text(
        key: const Key('official-review-congrats'),
        data == null
            ? 'Congrats'
            : 'Congrats · new=${data.newRemaining} review=${data.reviewRemaining}',
      ),
    );
  }
}

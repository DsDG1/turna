import 'package:auto_route/auto_route.dart';
import 'package:flutter/material.dart';
import 'package:turna/application/anki_official/official_anki_paths.dart';
import 'package:turna/application/anki_official/projection/official_anki_course_entry.dart';
import 'package:turna/application/anki_official/render/official_anki_reviewer_router.dart';
import 'package:turna/routing/platform_page_route.dart';
import 'package:turna/routing/routing.gr.dart';
import 'package:turna/views/anki_official/official_anki_reviewer_error_view.dart';

typedef OfficialAnkiCanonicalAck = Future<void> Function(
  OfficialAnkiCanonicalRef ref,
);

/// Real interaction path for official `canonicalLink` items.
///
/// Preview only: no Again/Hard/Good/Easy, official Scheduler writes stay 0.
class OfficialAnkiCanonicalLinkView extends StatefulWidget {
  const OfficialAnkiCanonicalLinkView({
    super.key,
    required this.contextToken,
    this.rendererAvailable = true,
    this.onOpenAndAcknowledge,
    this.onSubmit,
  });

  final String contextToken;
  final bool rendererAvailable;
  final OfficialAnkiCanonicalAck? onOpenAndAcknowledge;
  final void Function(bool correct)? onSubmit;

  @override
  State<OfficialAnkiCanonicalLinkView> createState() =>
      OfficialAnkiCanonicalLinkViewState();

  /// Shipped opener: resolve official paths and push the registered
  /// `OfficialAnkiReviewerRoute`.
  static Future<void> openOfficialReviewer(
    BuildContext context, {
    required String sourceId,
    required int cardId,
    OfficialAnkiPaths? paths,
  }) async {
    OfficialAnkiPaths resolved;
    try {
      resolved = paths ?? await OfficialAnkiCourseEntry.resolveDefaultPaths();
    } catch (suppressed) {
      debugPrint('[OfficialAnkiCanonicalLinkView] suppressed error: $suppressed');
      if (!context.mounted) return;
      // Runtime-assembled inline error page: goes through the central
      // platform route selector (plan D5), not a hand-written route.
      await Navigator.of(context).push(
        platformPageRoute<void>(
          context: context,
          builder: (_) => const Scaffold(
            body: OfficialAnkiReviewerErrorView(
              key: Key('official-canonical-path-failed'),
              messageKey: 'official_anki.renderer_flag_fail_closed',
            ),
          ),
        ),
      );
      return;
    }
    if (!context.mounted) return;
    await context.router.push(
      OfficialAnkiReviewerRoute(
        sourceId: sourceId,
        cardId: cardId,
        paths: resolved,
      ),
    );
  }
}

class OfficialAnkiCanonicalLinkViewState
    extends State<OfficialAnkiCanonicalLinkView> {
  var _submitted = false;
  var _viewed = false;
  var _opening = false;

  Future<void> _open() async {
    if (_submitted || _opening) return;
    final ref = OfficialAnkiCourseEntry.parseCanonicalLink(widget.contextToken);
    if (ref == null) return;
    _opening = true;
    try {
      final opener = widget.onOpenAndAcknowledge;
      if (opener != null) {
        await opener(ref);
      } else {
        if (!mounted) return;
        await OfficialAnkiCanonicalLinkView.openOfficialReviewer(
          context,
          sourceId: ref.sourceId,
          cardId: ref.cardId,
        );
      }
      if (!mounted) return;
      setState(() => _viewed = true);
      _acknowledge();
    } finally {
      _opening = false;
    }
  }

  void _acknowledge() {
    if (_submitted) return;
    _submitted = true;
    widget.onSubmit?.call(true);
  }

  @override
  Widget build(BuildContext context) {
    final target = OfficialAnkiCourseEntry.resolveCanonicalLink(
      context: widget.contextToken,
      rendererAvailable: widget.rendererAvailable,
    );
    final ref = OfficialAnkiCourseEntry.parseCanonicalLink(widget.contextToken);
    if (target != OfficialAnkiReviewTarget.officialReviewer || ref == null) {
      return const OfficialAnkiReviewerErrorView(
        key: Key('official-canonical-fail-closed'),
        messageKey: 'official_anki.renderer_flag_fail_closed',
      );
    }
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            FilledButton(
              key: const Key('official-canonical-open'),
              onPressed: _open,
              child: Text('打开原卡 ${ref.sourceId} #${ref.cardId}'),
            ),
            if (_viewed)
              const Padding(
                padding: EdgeInsets.only(top: 12),
                child: Text('已查看原卡'),
              ),
          ],
        ),
      ),
    );
  }
}

/// LessonViewModel-facing completion helper. Preview never writes Scheduler.
class OfficialAnkiCanonicalCompletion {
  OfficialAnkiCanonicalCompletion();

  var submitCount = 0;

  void acknowledgeOnce(void Function(bool correct) onSubmit) {
    if (submitCount > 0) return;
    submitCount += 1;
    onSubmit(true);
  }
}

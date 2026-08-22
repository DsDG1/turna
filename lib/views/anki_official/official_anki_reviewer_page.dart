import 'package:auto_route/auto_route.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:turna/application/anki_official/contract/official_anki_errors.dart';
import 'package:turna/application/anki_official/official_anki_paths.dart';
import 'package:turna/application/anki_official/render/official_anki_av_coordinator.dart';
import 'package:turna/application/anki_official/render/official_anki_av_player_adapter.dart';
import 'package:turna/application/anki_official/render/official_anki_media_resolver.dart';
import 'package:turna/application/anki_official/render/official_anki_render_facade.dart';
import 'package:turna/application/anki_official/render/official_anki_render_state.dart';
import 'package:turna/application/anki_official/render/official_anki_typed_answer_controller.dart';
import 'package:turna/application/audio_controller.dart';
import 'package:turna/di/injection.dart';
import 'package:turna/views/anki_official/official_anki_reviewer_error_view.dart';
import 'package:turna/views/anki_official/official_anki_reviewer_stage.dart';

Future<OfficialAnkiReviewerController> createOfficialAnkiReviewerController({
  required OfficialAnkiPaths paths,
  OfficialAnkiRenderFacade? facade,
  OfficialAnkiReviewerController? controller,
}) async {
  if (controller != null) return controller;
  final resolved = facade ?? await OfficialAnkiRenderFacade.fromWorker();
  return OfficialAnkiReviewerController(
    facade: resolved,
    av: OfficialAnkiAvCoordinator(
      resolver: OfficialAnkiMediaResolver(paths.mediaFolder),
      player: OfficialAnkiAvPlayerAdapter(audio: getIt<AudioController>()),
    ),
    typed: OfficialAnkiTypedAnswerController(resolved),
  );
}

/// Internal official card preview. Does not write grades or schedules.
@RoutePage()
class OfficialAnkiReviewerPage extends StatefulWidget {
  const OfficialAnkiReviewerPage({
    super.key,
    required this.sourceId,
    required this.cardId,
    required this.paths,
    this.facade,
    this.controller,
  });

  final String sourceId;
  final int cardId;
  final OfficialAnkiPaths paths;
  final OfficialAnkiRenderFacade? facade;
  final OfficialAnkiReviewerController? controller;

  @override
  State<OfficialAnkiReviewerPage> createState() =>
      _OfficialAnkiReviewerPageState();
}

class _OfficialAnkiReviewerPageState extends State<OfficialAnkiReviewerPage> {
  OfficialAnkiReviewerController? _controller;
  Object? _bootError;
  var _booting = true;

  @override
  void initState() {
    super.initState();
    _boot();
  }

  @override
  void didUpdateWidget(covariant OfficialAnkiReviewerPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.cardId == widget.cardId || _controller == null) return;
    _controller!.loadAndShowQuestion(widget.cardId);
  }

  Future<void> _boot() async {
    try {
      _controller = await createOfficialAnkiReviewerController(
        paths: widget.paths,
        facade: widget.facade,
        controller: widget.controller,
      );
      await _controller!.loadAndShowQuestion(widget.cardId);
    } catch (error, stack) {
      debugPrint('[OfficialAnkiReviewer] boot error $error\n$stack');
      _bootError = error;
    } finally {
      if (mounted) setState(() => _booting = false);
    }
  }

  @override
  void dispose() {
    if (widget.controller == null) {
      _controller?.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_booting) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    if (_bootError != null) {
      final error = _bootError;
      return Scaffold(
        appBar: AppBar(title: const Text('官方卡片预览')),
        body: OfficialAnkiReviewerErrorView(
          messageKey: error is OfficialAnkiException
              ? error.messageKey
              : 'official_anki.render_failed',
          debugDetails: kDebugMode ? error.toString() : null,
        ),
      );
    }
    return Scaffold(
      appBar: AppBar(title: const Text('官方卡片预览')),
      body: OfficialAnkiReviewerStage(
        controller: _controller!,
        paths: widget.paths,
        sourceId: widget.sourceId,
        showPreviewControls: true,
        onBack: () => Navigator.of(context).maybePop(),
      ),
    );
  }
}

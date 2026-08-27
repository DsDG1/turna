// Flutter imports:
import 'package:flutter/foundation.dart';

// Project imports:
import 'package:turna/application/ai/engine/ai_cancel_token.dart';
import 'package:turna/application/ai/stream_delta_coalescer.dart';

/// One generation of a streaming AI request.
///
/// Providers keep the returned handle locally and use [isCurrentSession]
/// before applying a terminal result. Network fragments themselves are
/// committed by [applyStreamingBatch] at UI cadence.
@immutable
class AiStreamingSession {
  const AiStreamingSession({
    required this.generation,
    required this.cancelToken,
  });

  final int generation;
  final AiCancelToken cancelToken;
}

/// Shared lifecycle for text-streaming providers.
///
/// It owns the generation gate, cancel token, 80 ms delta coalescer,
/// streaming revision and disposed guard. Subclasses only decide where a
/// committed batch is stored.
abstract class AiStreamingSessionBase extends ChangeNotifier {
  int _generation = 0;
  AiCancelToken? _cancelToken;
  StreamDeltaCoalescer? _coalescer;
  bool _disposed = false;
  int _streamingRevision = 0;

  int get streamingRevision => _streamingRevision;

  @protected
  bool get isSessionDisposed => _disposed;

  /// Starts a generation and discards any buffered fragment from an older
  /// request. Superseded callbacks become inert immediately.
  @protected
  AiStreamingSession beginStreamingSession() {
    _cancelToken?.cancel();
    _coalescer?.cancel();
    _generation++;
    final token = AiCancelToken();
    _cancelToken = token;
    _coalescer = StreamDeltaCoalescer(
      interval: const Duration(milliseconds: 80),
      onBatch: (batch) {
        if (_disposed || batch.isEmpty) return;
        applyStreamingBatch(batch);
        _streamingRevision++;
        notifyListeners();
      },
    );
    return AiStreamingSession(generation: _generation, cancelToken: token);
  }

  @protected
  bool isCurrentSession(AiStreamingSession session) =>
      !_disposed &&
      session.generation == _generation &&
      identical(_cancelToken, session.cancelToken);

  @protected
  void addStreamingDelta(AiStreamingSession session, String delta) {
    if (!isCurrentSession(session)) return;
    _coalescer?.add(delta);
  }

  /// Commits the pending tail without ending the generation.
  @protected
  void flushStreamingSession(AiStreamingSession session) {
    if (!isCurrentSession(session)) return;
    _coalescer?.flush();
  }

  /// Releases a completed request. The caller should flush first when its
  /// terminal result must retain the pending tail.
  @protected
  void finishStreamingSession(AiStreamingSession session) {
    if (!isCurrentSession(session)) return;
    _coalescer?.cancel();
    _coalescer = null;
    _cancelToken = null;
  }

  /// User cancellation keeps already received (including buffered) text.
  @protected
  void cancelStreamingSession({bool keepBufferedText = true}) {
    if (_disposed) return;
    if (keepBufferedText) _coalescer?.flush();
    _coalescer?.cancel();
    _coalescer = null;
    _cancelToken?.cancel();
    _cancelToken = null;
  }

  /// Reset/supersede invalidates all late work and discards buffered text.
  @protected
  void abandonStreamingSession() {
    if (_disposed) return;
    _generation++;
    _coalescer?.cancel();
    _coalescer = null;
    _cancelToken?.cancel();
    _cancelToken = null;
  }

  @protected
  void notifySessionListeners() {
    if (!_disposed) notifyListeners();
  }

  /// Store one coalesced fragment in provider-owned state.
  @protected
  void applyStreamingBatch(String batch);

  @override
  void dispose() {
    _disposed = true;
    _generation++;
    _coalescer?.cancel();
    _coalescer = null;
    _cancelToken?.cancel();
    _cancelToken = null;
    super.dispose();
  }
}

/// Base for providers that issue engine requests without `onChunk`.
///
/// They still get the generation gate, cancel token and disposed guard from
/// [AiStreamingSessionBase]; the delta coalescer simply stays idle because no
/// fragments are ever streamed, so [AiStreamingSessionBase.applyStreamingBatch]
/// never fires and can be a no-op.
abstract class AiRequestSessionBase extends AiStreamingSessionBase {
  @override
  @protected
  void applyStreamingBatch(String batch) {}
}

// Dart imports:
import 'dart:async';

// Flutter imports:
import 'package:flutter/foundation.dart';

/// Coalesces network stream fragments into UI-rate batches (Plan 3 §21.1).
///
/// SSE/chat streams can emit many tiny deltas per second; notifying listeners
/// per delta re-renders far faster than any human can perceive. The coalescer
/// buffers deltas in a [StringBuffer] (no intermediate full-message strings)
/// and emits **at most one batch per [interval]**. Stream completion, error
/// and cancellation all trigger an immediate [flush] so no content is lost;
/// [cancel] discards pending content and never emits again.
///
/// Guarantees (tested): deltas are never lost or reordered; a batch contains
/// everything buffered since the previous batch; after [cancel] no callback
/// fires.
class StreamDeltaCoalescer {
  StreamDeltaCoalescer({
    this.interval = const Duration(milliseconds: 80),
    required this.onBatch,
  });

  /// UI commit interval. 50–100 ms is visually smooth (10–20 Hz); reduce-
  /// motion consumers may construct with a longer interval instead of
  /// disabling streaming entirely.
  final Duration interval;

  /// Receives concatenated deltas. Called at most once per [interval] while
  /// streaming, plus once on [flush].
  final void Function(String batch) onBatch;

  final StringBuffer _buffer = StringBuffer();
  Timer? _timer;
  bool _cancelled = false;

  /// Whether a batch is currently pending (buffer non-empty or timer armed).
  bool get hasPending => _buffer.isNotEmpty || _timer != null;

  /// Total deltas accepted — for tests/diagnostics.
  int acceptedDeltas = 0;

  void add(String delta) {
    if (_cancelled || delta.isEmpty) return;
    acceptedDeltas++;
    _buffer.write(delta);
    _timer ??= Timer(interval, _emit);
  }

  /// Emit any pending content immediately (e.g. stream finished / final
  /// layout). Safe to call when nothing is pending.
  void flush() {
    if (_cancelled) return;
    _timer?.cancel();
    _timer = null;
    if (_buffer.isEmpty) return;
    final batch = _buffer.toString();
    _buffer.clear();
    onBatch(batch);
  }

  /// Discard pending content and stop emitting permanently.
  void cancel() {
    _cancelled = true;
    _timer?.cancel();
    _timer = null;
    _buffer.clear();
  }

  void _emit() {
    _timer = null;
    if (_cancelled || _buffer.isEmpty) return;
    final batch = _buffer.toString();
    _buffer.clear();
    onBatch(batch);
  }

  @visibleForTesting
  static Duration get testInterval => const Duration(milliseconds: 20);
}

import 'package:turna/service/read_aloud_backend.dart';

/// A scriptable [ReadAloudBackend] for renderer/widget tests.
///
/// Nothing is delivered automatically: the test starts a session through the
/// renderer's mic button and then drives results/errors with [emitPartial] /
/// [emitFinal] / [emitError], mirroring how the real recognizer calls back
/// from its own event loop.
class FakeReadAloudBackend implements ReadAloudBackend {
  FakeReadAloudBackend({
    this.supported = true,
    this.ready = true,
    this.readyFailure = ReadAloudFailure.permissionDenied,
  });

  /// When false, mimics [UnavailableReadAloudBackend] without its
  /// start-throwing behaviour (tests that want the throw use the real class).
  bool supported;

  /// Answer [ensureReady] gives: false = permission denied / no service.
  bool ready;
  ReadAloudFailure readyFailure;

  final List<String> startLocales = [];
  int stopCount = 0;

  ReadAloudResultListener? _onResult;
  ReadAloudErrorListener? _onError;

  @override
  bool get isSupported => supported;

  @override
  ReadAloudFailure? get lastFailure => ready ? null : readyFailure;

  @override
  Future<bool> ensureReady() async => ready;

  @override
  Future<void> start({
    required String locale,
    required ReadAloudResultListener onResult,
    required ReadAloudErrorListener onError,
  }) async {
    startLocales.add(locale);
    _onResult = onResult;
    _onError = onError;
  }

  @override
  Future<void> stop() async {
    stopCount++;
  }

  void emitPartial(String text) => _onResult?.call(text, false);
  void emitFinal(String text) => _onResult?.call(text, true);
  void emitError(ReadAloudFailure reason) => _onError?.call(reason);
}

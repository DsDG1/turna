/// Single-flight gate for work that must finish before the course tree loads
/// but must not block the first frame.
///
/// [body] runs at most once. Later [ensure] callers share that future,
/// including a failure, so a partial seed is not started twice.
class CourseDbReadyGate {
  CourseDbReadyGate(this._body);

  final Future<void> Function() _body;
  Future<void>? _inFlight;

  Future<void> ensure() => _inFlight ??= _body();
}

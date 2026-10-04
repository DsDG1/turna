// Recording stand-ins for the platform audio backends.
//
// `AudioController` talks to an `AudioBackend` rather than to `audioplayers`
// directly, so tests hand it one of these instead of a fake `AudioPlayer`. A
// fake that answers every call with null is not usable here: the interface
// returns `Future<void>` and a null return would not type-check, which is
// exactly the kind of test double that makes a test pass for the wrong reason.

// Project imports:
import 'package:turna/service/audio_backend.dart';

/// An [AudioBackend] that records what it was asked to do.
class FakeAudioBackend implements AudioBackend {
  FakeAudioBackend({this.name = 'fake'});

  /// Distinguishes the two slots in a failure message; a controller wired with
  /// two otherwise identical fakes otherwise reports the same name twice.
  final String name;

  final List<String> playedAssets = <String>[];
  final List<String> playedFiles = <String>[];
  int stopCount = 0;
  int releaseCount = 0;

  /// Set to make every call fail, for the paths that must fall back.
  Object? failure;

  void _maybeFail() {
    final error = failure;
    if (error != null) throw error;
  }

  @override
  Future<void> playAsset(String assetPath) async {
    _maybeFail();
    playedAssets.add(assetPath);
  }

  @override
  Future<void> playFile(String absolutePath) async {
    _maybeFail();
    playedFiles.add(absolutePath);
  }

  @override
  Future<void> stop() async {
    _maybeFail();
    stopCount++;
  }

  @override
  Future<void> release() async {
    _maybeFail();
    releaseCount++;
  }

  @override
  String toString() => 'FakeAudioBackend($name)';
}

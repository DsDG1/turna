import 'runtime_memory_platform_stub.dart'
    if (dart.library.io) 'runtime_memory_platform_io.dart' as platform;

class RuntimeMemorySnapshot {
  const RuntimeMemorySnapshot({
    required this.currentRssBytes,
    required this.dartHeapBytes,
    required this.sampledAt,
  });

  final int? currentRssBytes;
  final int? dartHeapBytes;
  final DateTime sampledAt;

  static Future<RuntimeMemorySnapshot> sample() async => RuntimeMemorySnapshot(
        currentRssBytes: platform.currentRssBytes(),
        // Stable public heap telemetry is not available on every Flutter
        // target. Null is honest; diagnostics must never infer it from RSS.
        dartHeapBytes: null,
        sampledAt: DateTime.now(),
      );
}

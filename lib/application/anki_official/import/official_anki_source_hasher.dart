import 'dart:io';

import 'package:crypto/crypto.dart';

class OfficialAnkiSourceDigest {
  const OfficialAnkiSourceDigest({required this.sha256, required this.bytes});

  final String sha256;
  final int bytes;
}

class OfficialAnkiSourceHasher {
  const OfficialAnkiSourceHasher();

  Future<OfficialAnkiSourceDigest> hashFile(String path) async {
    final file = File(path);
    final sink = _DigestSink();
    final input = sha256.startChunkedConversion(sink);
    var bytes = 0;
    await for (final chunk in file.openRead()) {
      bytes += chunk.length;
      input.add(chunk);
    }
    input.close();
    return OfficialAnkiSourceDigest(
      sha256: sink.events.single.toString(),
      bytes: bytes,
    );
  }
}

class _DigestSink implements Sink<Digest> {
  final List<Digest> events = <Digest>[];

  @override
  void add(Digest data) => events.add(data);

  @override
  void close() {}
}

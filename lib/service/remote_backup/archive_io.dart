// Dart imports:
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

// Package imports:
import 'package:archive/archive.dart';
import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;

/// Archive / hashing IO helpers shared by the remote backup pipeline.
///
/// Doc 35 L1: moved from the retired `application/anki/anki_import_platform_io.dart`
/// (Dart `.apkg` parser support) — these two primitives have no parser
/// dependency and stay the backbone of snapshot hashing and restore
/// extraction.

/// Computes the SHA-256 of [path] in fixed-size chunks so hashing a large
/// archive never holds the whole file in memory.
String archiveFileSha256(String path) {
  const chunkSize = 1024 * 1024;
  final digestSink = _DigestSink();
  final sink = sha256.startChunkedConversion(digestSink);
  final file = File(path).openSync();
  try {
    final buffer = Uint8List(chunkSize);
    while (true) {
      final read = file.readIntoSync(buffer, 0, chunkSize);
      if (read <= 0) break;
      sink.add(Uint8List.sublistView(buffer, 0, read));
    }
  } finally {
    file.closeSync();
  }
  sink.close();
  return digestSink.digest.toString();
}

/// Extracts a ZIP archive into [destDir] by streaming each entry straight to
/// disk, the same pattern `package:archive`'s own `extractFileToDisk` uses.
/// Neither the archive bytes nor any entry's content is fully held in memory,
/// so multi-hundred-megabyte snapshots restore with flat memory use.
///
/// [resolveEntryPath] maps an archive entry name to a path relative to
/// [destDir]; it may throw to abort extraction (unsafe-name rejection).
/// [onEntry] runs just before an entry is written, receiving the entry's
/// declared uncompressed size, so callers can enforce size caps before any
/// data is written to disk.
Future<void> extractArchiveToDisk(
  String archivePath,
  String destDir, {
  required String Function(String entryName) resolveEntryPath,
  required void Function(String entryName, int uncompressedSize) onEntry,
}) async {
  final input = InputFileStream(archivePath);
  try {
    final archive = ZipDecoder().decodeStream(input);
    for (final entry in archive) {
      if (!entry.isFile) continue;
      onEntry(entry.name, entry.size);
      final outputPath = p.join(destDir, resolveEntryPath(entry.name));
      Directory(p.dirname(outputPath)).createSync(recursive: true);
      final output = OutputFileStream(outputPath);
      try {
        entry.writeContent(output);
      } finally {
        await output.close();
      }
    }
  } finally {
    await input.close();
  }
}

/// Collects the single digest emitted by [Hash.startChunkedConversion].
class _DigestSink implements Sink<Digest> {
  Digest? _digest;

  Digest get digest => _digest ?? (throw StateError('no digest collected'));

  @override
  void add(Digest data) => _digest = data;

  @override
  void close() {}
}

/// Runs [archiveFileSha256] on a background isolate.
///
/// Hashing is pure path-in/digest-out, and the archives this guards reach
/// hundreds of megabytes — hashing them on the main isolate froze the UI for
/// the whole read. Static + pure so the [Isolate.run] closure captures nothing
/// but the path string (same pattern as the "crash-hunt PR1" isolate moves in
/// `course_repository.dart`).
Future<String> archiveFileSha256OffMainThread(String path) {
  return Isolate.run(() => archiveFileSha256(path));
}

/// Parses a `SHA256SUMS` manifest at [sumsPath] and re-hashes every listed
/// entry (resolved under [baseDir]), throwing [FormatException] on a missing
/// manifest, a malformed line, or a digest mismatch.
///
/// Single source of truth for the two historical copies of this loop — the
/// download-time check in `RemoteBackupService` and the boot-time re-check in
/// `RestoreApplier` — so their verification can never drift apart.
void verifySha256SumsFile(String sumsPath, String baseDir) {
  final sumsFile = File(sumsPath);
  if (!sumsFile.existsSync()) {
    throw const FormatException('备份包缺少 SHA256SUMS');
  }
  for (final line in sumsFile.readAsLinesSync()) {
    if (line.trim().isEmpty) continue;
    final match = RegExp(r'^([0-9a-f]{64})  (.+)$').firstMatch(line.trim());
    if (match == null) {
      throw FormatException('SHA256SUMS 行格式错误: $line');
    }
    final digest = archiveFileSha256(p.join(baseDir, match.group(2)!));
    if (digest != match.group(1)!) {
      throw FormatException('备份包文件校验失败: ${match.group(2)}');
    }
  }
}

/// Runs [verifySha256SumsFile] on a background isolate. The entries it
/// re-hashes include `course.db`, which can reach hundreds of megabytes —
/// see [archiveFileSha256OffMainThread] for why that must leave the main
/// isolate.
Future<void> verifySha256SumsFileOffMainThread(
  String sumsPath,
  String baseDir,
) {
  return Isolate.run(() => verifySha256SumsFile(sumsPath, baseDir));
}

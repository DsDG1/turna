import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:logger/logger.dart';
import 'package:turna/core/log_capture.dart';

void main() {
  // LogCapture.instance is a singleton shared across these tests: install
  // once against a temp file, and have every test start from `clear()`.
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory dir;
  late File file;
  final capture = LogCapture.instance;
  final emitter = Logger();

  setUpAll(() async {
    dir = await Directory.systemTemp.createTemp('turna_log_capture_');
    file = File('${dir.path}/transparency_log.jsonl');
    await capture.installWithFile(file);
  });

  tearDownAll(() async {
    await capture.dispose();
    await dir.delete(recursive: true);
  });

  Future<void> settle() =>
      Future<void>.delayed(const Duration(milliseconds: 250));

  test('buffer keeps the newest 200 entries, newest first', () async {
    await capture.clear();
    for (var i = 0; i < 260; i++) {
      emitter.i('msg-$i');
    }
    await settle();
    expect(capture.entries.value, hasLength(LogCapture.maxEntries));
    // Newest first: the last emitted message leads.
    expect(capture.entries.value.first.message, 'msg-259');
    expect(capture.entries.value.last.message, 'msg-60');
  });

  test('burst of logs publishes one coalesced notification', () async {
    await capture.clear();
    var notifications = 0;
    void listener() => notifications++;
    capture.entries.addListener(listener);
    for (var i = 0; i < 5; i++) {
      emitter.i('burst-$i');
    }
    await settle();
    capture.entries.removeListener(listener);
    expect(notifications, 1,
        reason: '5 events inside the 100ms window must publish once');
  });

  test('flushNow persists entries as JSONL and clear wipes everything',
      () async {
    await capture.clear();
    emitter.i('persist-me');
    emitter.w('warn-me');
    await settle();
    await capture.flushNow();

    final lines =
        file.readAsLinesSync().where((line) => line.trim().isNotEmpty).toList();
    expect(lines, hasLength(2));
    expect(lines.first, contains('persist-me'));
    expect(lines.first, contains('"level":"info"'));
    expect(lines.last, contains('"level":"warn"'));

    await capture.clear();
    expect(file.readAsStringSync(), '');
    expect(capture.entries.value, isEmpty);
  });

  test('clear during in-flight flush cannot resurrect old lines', () async {
    await capture.clear();
    for (var i = 0; i < 50; i++) {
      emitter.i('race-$i');
    }
    // Start a flush and immediately clear: the truncate is serialized on
    // the same disk chain, so it must run AFTER the flush completes.
    final flushing = capture.flushNow();
    await capture.clear();
    await flushing;
    expect(file.readAsStringSync(), '',
        reason: 'clear must win even against a concurrent flush');
    expect(capture.entries.value, isEmpty);
  });

  test('1MB active file rotates once and keeps history', () async {
    await capture.clear();
    final big = 'x' * 20 * 1024; // 20KB per message
    for (var i = 0; i < 60; i++) {
      // Emit through the listener path with a large payload.
      Logger().log(Level.info, '$big-$i');
    }
    await settle();
    await capture.flushNow();

    final rotated = File('${dir.path}/transparency_log.1.jsonl');
    expect(await rotated.exists(), isTrue,
        reason: 'active file must rotate once past 1MB');
    expect(await rotated.length(), greaterThan(1024 * 1024));

    // The 30s cooldown suppresses a second rotate on the next flush.
    emitter.i('after-rotate');
    await settle();
    await capture.flushNow();
    final second = File('${dir.path}/transparency_log.2.jsonl');
    expect(await second.exists(), isFalse,
        reason: 'rotate cooldown must suppress back-to-back rotates');
  }, timeout: const Timeout(Duration(minutes: 2)));
}

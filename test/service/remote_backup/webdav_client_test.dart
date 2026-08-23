// Dart imports:
import 'dart:io';

// Package imports:
import 'package:flutter_test/flutter_test.dart';

// Project imports:
import 'package:turna/service/remote_backup/webdav_client.dart';

// Test imports:
import 'mini_dav_server.dart';

void main() {
  late MiniDavServer server;
  late WebDavClient client;

  setUp(() async {
    server = MiniDavServer(username: 'alice', password: 'secret');
    await server.start();
    client = WebDavClient(
      baseUrl: server.baseUri,
      username: 'alice',
      password: 'secret',
    );
  });

  tearDown(() async {
    client.close();
    await server.stop();
  });

  test('probe succeeds against a reachable WebDAV server', () async {
    final result = await client.probe();
    expect(result.davHeader, contains('1'));
  });

  test('probe maps 401 to WebDavAuthException', () async {
    final bad = WebDavClient(
      baseUrl: server.baseUri,
      username: 'alice',
      password: 'wrong',
    );
    addTearDown(bad.close);
    await expectLater(bad.probe(), throwsA(isA<WebDavAuthException>()));
  });

  test('mkcolRecursive creates nested collections and is idempotent', () async {
    await client.mkcolRecursive('/TurnaBackup/backups/bk-1');
    await client.mkcolRecursive('/TurnaBackup/backups/bk-1');
    expect(await client.exists('/TurnaBackup'), isTrue);
    expect(await client.exists('/TurnaBackup/backups'), isTrue);
    expect(await client.exists('/TurnaBackup/backups/bk-1'), isTrue);
  });

  test('putBytes / getBytes roundtrip', () async {
    await client.mkcolRecursive('/TurnaBackup');
    await client.putBytes('/TurnaBackup/manifest.json', utf8Json);
    final back = await client.getBytes('/TurnaBackup/manifest.json');
    expect(String.fromCharCodes(back), '{"ok":true}');
  });

  test('putFile streams file content and reports progress', () async {
    final dir = await Directory.systemTemp.createTemp('webdav_put');
    addTearDown(() => dir.deleteSync(recursive: true));
    final payload = List<int>.generate(256 * 1024, (i) => i % 251);
    final file = File('${dir.path}/blob.bin');
    await file.writeAsBytes(payload, flush: true);

    await client.mkcolRecursive('/TurnaBackup/media');
    var lastReported = 0;
    await client.putFile('/TurnaBackup/media/blob', file,
        onProgress: (sent, total) => lastReported = sent);
    expect(lastReported, payload.length);
    expect(await client.exists('/TurnaBackup/media/blob'), isTrue);

    final dest = File('${dir.path}/download.bin');
    await client.getToFile('/TurnaBackup/media/blob', dest);
    expect(await dest.readAsBytes(), payload);
    expect(File('${dest.path}.download').existsSync(), isFalse,
        reason: 'temp download file must be renamed away');
  });

  test('getToFile maps 404 to WebDavNotFoundException', () async {
    final dest =
        File('${Directory.systemTemp.createTempSync('webdav_404').path}/x');
    await expectLater(
      client.getToFile('/missing', dest),
      throwsA(isA<WebDavNotFoundException>()),
    );
  });

  test('PUT into a missing parent fails with a status-carrying error',
      () async {
    await expectLater(
      client.putBytes('/no-parent/file.txt', utf8Json),
      throwsA(isA<WebDavException>().having(
        (e) => e.statusCode,
        'statusCode',
        409,
      )),
    );
  });

  test('delete removes a file and tolerates a missing one', () async {
    await client.mkcolRecursive('/TurnaBackup');
    await client.putBytes('/TurnaBackup/a.txt', utf8Json);
    await client.delete('/TurnaBackup/a.txt');
    expect(await client.exists('/TurnaBackup/a.txt'), isFalse);
    await client.delete('/TurnaBackup/a.txt');
  });

  test('move renames with overwrite for atomic manifest publish', () async {
    await client.mkcolRecursive('/TurnaBackup');
    await client.putBytes('/TurnaBackup/manifest.json.tmp', utf8Json);
    // Pre-existing target proves the Overwrite: T header path.
    await client.putBytes('/TurnaBackup/manifest.json', <int>[1, 2, 3]);
    await client.move(
        '/TurnaBackup/manifest.json.tmp', '/TurnaBackup/manifest.json');
    expect(await client.exists('/TurnaBackup/manifest.json.tmp'), isFalse);
    final back = await client.getBytes('/TurnaBackup/manifest.json');
    expect(String.fromCharCodes(back), '{"ok":true}');
  });
}

const utf8Json = [
  123,
  34,
  111,
  107,
  34,
  58,
  116,
  114,
  117,
  101,
  125
]; // {"ok":true}

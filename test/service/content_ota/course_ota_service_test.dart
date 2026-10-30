import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:turna/application/course_provider.dart';
import 'package:turna/courses/course_content_source.dart';
import 'package:turna/service/content_ota/course_ota_service.dart';

import '../../helpers/in_memory_course_db.dart';

void main() {
  late Directory sandbox;
  late Directory updatesRoot;
  late HttpServer server;
  late Map<String, List<int>> courseFiles;
  late List<int> packageBytes;

  setUp(() async {
    sandbox = await Directory.systemTemp.createTemp('course-ota-test-');
    updatesRoot = Directory(p.join(sandbox.path, 'content_updates'));
    courseFiles = await _readCourseFiles();
    _setIndexVersion(courseFiles, 3);
    packageBytes = _zip(courseFiles);
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
  });

  tearDown(() async {
    await server.close(force: true);
    if (await sandbox.exists()) await sandbox.delete(recursive: true);
  });

  CourseOtaService service({
    CourseContentVersion current = const (index: 1, expressions: 1),
    void Function(String)? invalidate,
    CourseOtaRename? rename,
  }) {
    final value = CourseOtaService(
      updatesDirectory: () async => updatesRoot,
      currentVersion: (_) async => current,
      invalidateSource: invalidate ?? (_) {},
      renameDirectory: rename,
      allowInsecureHttp: true,
    );
    addTearDown(value.close);
    return value;
  }

  Uri url(String path) => Uri.parse('http://127.0.0.1:${server.port}$path');

  test('feed relative URL installs a complete newer course', () async {
    _serveFiles(server, {
      '/course-feed.json': utf8.encode(_feed(packageBytes)),
      '/nouveau-turkish-3.zip': packageBytes,
    });
    await _writeOldCourse(updatesRoot);
    final invalidated = <String>[];

    final result = await service(invalidate: invalidated.add).updateFromUrl(
      url('/course-feed.json').toString(),
    );

    expect(result.version, const (index: 3, expressions: 1));
    expect(result.notes, '测试更新');
    expect(invalidated, ['tr']);
    final installed = jsonDecode(
      await File(p.join(updatesRoot.path, 'tr', 'index.json')).readAsString(),
    ) as Map<String, dynamic>;
    expect(installed['version'], 3);
    expect(
      await File(p.join(updatesRoot.path, 'tr', 'vocab.json')).exists(),
      isTrue,
    );
    await _expectNoWorkDirs(updatesRoot);
  });

  test('SHA-256 mismatch rejects the package and preserves old content',
      () async {
    final feed = jsonDecode(_feed(packageBytes)) as Map<String, dynamic>;
    (feed['latest'] as Map<String, dynamic>)['sha256'] = '0' * 64;
    _serveFiles(server, {
      '/course-feed.json': utf8.encode(jsonEncode(feed)),
      '/nouveau-turkish-3.zip': packageBytes,
    });
    await _writeOldCourse(updatesRoot);

    await expectLater(
      service().updateFromUrl(url('/course-feed.json').toString()),
      throwsA(isA<CourseOtaException>().having(
        (error) => error.message,
        'message',
        contains('SHA-256'),
      )),
    );

    expect(await _oldCourseMarker(updatesRoot), 'old');
    await _expectNoWorkDirs(updatesRoot);
  });

  test('zip-slip entry is rejected without escaping or replacing old content',
      () async {
    final malicious = Map<String, List<int>>.of(courseFiles)
      ..['../escaped.json'] = utf8.encode('{}');
    _serveFiles(server, {'/course.zip': _zip(malicious)});
    await _writeOldCourse(updatesRoot);

    await expectLater(
      service().updateFromUrl(url('/course.zip').toString()),
      throwsA(isA<CourseOtaException>().having(
        (error) => error.message,
        'message',
        contains('不安全路径'),
      )),
    );

    expect(
        await File(p.join(updatesRoot.path, 'escaped.json')).exists(), isFalse);
    expect(await _oldCourseMarker(updatesRoot), 'old');
    await _expectNoWorkDirs(updatesRoot);
  });

  test('interrupted download leaves no partial package or staging directory',
      () async {
    server.listen((request) async {
      final socket = await request.response.detachSocket(writeHeaders: false);
      socket.write(
        'HTTP/1.1 200 OK\r\n'
        'Content-Length: ${packageBytes.length}\r\n'
        'Connection: close\r\n\r\n',
      );
      socket.add(packageBytes.sublist(0, packageBytes.length ~/ 2));
      await socket.flush();
      socket.destroy();
    });
    await _writeOldCourse(updatesRoot);

    await expectLater(
      service().updateFromUrl(url('/course.zip').toString()),
      throwsA(isA<CourseOtaException>()),
    );

    expect(await _oldCourseMarker(updatesRoot), 'old');
    await _expectNoWorkDirs(updatesRoot);
  });

  test('same or older feed version is rejected before package download',
      () async {
    final requested = <String>[];
    server.listen((request) async {
      requested.add(request.uri.path);
      if (request.uri.path == '/course-feed.json') {
        request.response.add(utf8.encode(_feed(packageBytes)));
      } else {
        request.response.statusCode = HttpStatus.notFound;
      }
      await request.response.close();
    });

    await expectLater(
      service(current: const (index: 3, expressions: 1))
          .updateFromUrl(url('/course-feed.json').toString()),
      throwsA(isA<CourseOtaException>().having(
        (error) => error.message,
        'message',
        contains('版本不高于'),
      )),
    );

    expect(requested, ['/course-feed.json']);
    await _expectNoWorkDirs(updatesRoot);
  });

  test('failed target switch rolls back to the previous directory', () async {
    _serveFiles(server, {'/course.zip': packageBytes});
    await _writeOldCourse(updatesRoot);
    final target = Directory(p.join(updatesRoot.path, 'tr'));

    Future<void> rename(Directory from, Directory to) async {
      if (p.basename(from.path) == 'content' && to.path == target.path) {
        throw const FileSystemException('injected switch failure');
      }
      await from.rename(to.path);
    }

    await expectLater(
      service(rename: rename).updateFromUrl(url('/course.zip').toString()),
      throwsA(isA<CourseOtaException>().having(
        (error) => error.message,
        'message',
        contains('旧版本已保留'),
      )),
    );

    expect(await _oldCourseMarker(updatesRoot), 'old');
    expect(
      await Directory(p.join(updatesRoot.path, 'tr.backup')).exists(),
      isFalse,
    );
    await _expectNoWorkDirs(updatesRoot);
  });

  test('recovery restores an interrupted backup and removes stale temp dirs',
      () async {
    final backup = Directory(p.join(updatesRoot.path, 'tr.backup'));
    await backup.create(recursive: true);
    await File(p.join(backup.path, 'marker.txt')).writeAsString('old');
    final stale = Directory(p.join(updatesRoot.path, 'tr.tmp-stale'));
    await stale.create();
    await File(p.join(stale.path, 'partial.zip')).writeAsBytes([1, 2, 3]);
    server.listen((request) async {
      request.response.statusCode = HttpStatus.serviceUnavailable;
      await request.response.close();
    });

    await expectLater(
      service().updateFromUrl(url('/course.zip').toString()),
      throwsA(isA<CourseOtaException>()),
    );

    expect(await _oldCourseMarker(updatesRoot), 'old');
    expect(await backup.exists(), isFalse);
    expect(await stale.exists(), isFalse);
  });

  test('installed package reseeds into the visible course tree', () async {
    final previousPathProvider = PathProviderPlatform.instance;
    PathProviderPlatform.instance = _DocumentsPathProvider(sandbox.path);
    CourseContentSource.instance.invalidate();
    addTearDown(() {
      CourseContentSource.instance.invalidate();
      PathProviderPlatform.instance = previousPathProvider;
    });

    final updatedFiles = Map<String, List<int>>.of(courseFiles);
    final section =
        jsonDecode(utf8.decode(updatedFiles['sections/section1.json']!))
            as Map<String, dynamic>;
    section['name'] = '云端新课';
    updatedFiles['sections/section1.json'] = utf8.encode(jsonEncode(section));
    _serveFiles(server, {'/course.zip': _zip(updatedFiles)});

    final db = await seedInMemoryCourseDb();
    addTearDown(db.close);
    final provider = CourseProvider();
    await provider.load();
    final initialRevision = provider.contentRevision;
    // The widget-test binding installs mock HTTP overrides; this last test
    // deliberately uses the real loopback server for the full OTA chain.
    HttpOverrides.global = null;
    final ota = CourseOtaService(allowInsecureHttp: true);
    addTearDown(ota.close);

    await ota.updateFromUrl(url('/course.zip').toString());
    final changed = await provider.refreshBuiltinContent('tr');

    expect(changed, isTrue);
    expect(provider.contentRevision, initialRevision + 1);
    expect(
      provider.sections.firstWhere((section) => section.id == 'nt-s1').name,
      '云端新课',
    );
  });

  test('clearInstalledContent removes the package, backup and temp dirs',
      () async {
    await _writeOldCourse(updatesRoot);
    await Directory(p.join(updatesRoot.path, 'tr.backup')).create();
    await Directory(p.join(updatesRoot.path, 'tr.tmp-stale')).create();
    final invalidated = <String>[];

    final removed =
        await service(invalidate: invalidated.add).clearInstalledContent();

    expect(removed, isTrue);
    expect(invalidated, ['tr']);
    final names = await updatesRoot
        .list()
        .map((entity) => p.basename(entity.path))
        .toList();
    expect(names, isEmpty);
    await _expectNoWorkDirs(updatesRoot);
  });

  test('clearInstalledContent removes a leftover backup on its own', () async {
    final backup = Directory(p.join(updatesRoot.path, 'tr.backup'));
    await backup.create(recursive: true);
    await File(p.join(backup.path, 'index.json')).writeAsString('{}');

    final removed = await service().clearInstalledContent();

    expect(removed, isTrue);
    expect(await backup.exists(), isFalse);
  });

  test('clearInstalledContent reports nothing to remove', () async {
    final invalidated = <String>[];

    final removed =
        await service(invalidate: invalidated.add).clearInstalledContent();

    expect(removed, isFalse);
    expect(invalidated, isEmpty);
  });

  test('clearInstalledContent rejects an unsafe language code', () async {
    await _writeOldCourse(updatesRoot);

    expect(
      () => service().clearInstalledContent('../tr'),
      throwsA(isA<CourseOtaException>().having(
        (error) => error.message,
        'message',
        contains('课程语言代码无效'),
      )),
    );

    expect(await _oldCourseMarker(updatesRoot), 'old');
  });

  test('restore reseeds bundled content after clearing the package', () async {
    final previousPathProvider = PathProviderPlatform.instance;
    PathProviderPlatform.instance = _DocumentsPathProvider(sandbox.path);
    CourseContentSource.instance.invalidate();
    addTearDown(() {
      CourseContentSource.instance.invalidate();
      PathProviderPlatform.instance = previousPathProvider;
    });

    final bundledVersion = await CourseContentSource.instance.versionFor('tr');
    final originalName = (jsonDecode(
      utf8.decode(courseFiles['sections/section1.json']!),
    ) as Map<String, dynamic>)['name'] as String;

    final updatedFiles = Map<String, List<int>>.of(courseFiles);
    final section =
        jsonDecode(utf8.decode(updatedFiles['sections/section1.json']!))
            as Map<String, dynamic>;
    section['name'] = '云端新课';
    updatedFiles['sections/section1.json'] = utf8.encode(jsonEncode(section));
    _serveFiles(server, {'/course.zip': _zip(updatedFiles)});

    final db = await seedInMemoryCourseDb();
    addTearDown(db.close);
    final provider = CourseProvider();
    await provider.load();
    HttpOverrides.global = null;
    final ota = CourseOtaService(allowInsecureHttp: true);
    addTearDown(ota.close);

    await ota.updateFromUrl(url('/course.zip').toString());
    await provider.refreshBuiltinContent('tr');
    expect(
      provider.sections.firstWhere((section) => section.id == 'nt-s1').name,
      '云端新课',
    );

    expect(await ota.clearInstalledContent(), isTrue);
    expect(await CourseContentSource.instance.versionFor('tr'), bundledVersion);
    expect(await provider.refreshBuiltinContent('tr'), isTrue);
    expect(
      provider.sections.firstWhere((section) => section.id == 'nt-s1').name,
      originalName,
    );
  });
}

class _DocumentsPathProvider extends PathProviderPlatform {
  _DocumentsPathProvider(this.documentsPath);

  final String documentsPath;

  @override
  Future<String?> getApplicationDocumentsPath() async => documentsPath;
}

Future<Map<String, List<int>>> _readCourseFiles() async {
  final root = Directory('assets/courses/nouveau-turkish');
  final files = <String, List<int>>{};
  await for (final entity in root.list(recursive: true)) {
    if (entity is! File) continue;
    final relative =
        p.relative(entity.path, from: root.path).replaceAll('\\', '/');
    files[relative] = await entity.readAsBytes();
  }
  return files;
}

void _setIndexVersion(Map<String, List<int>> files, int version) {
  final index =
      jsonDecode(utf8.decode(files['index.json']!)) as Map<String, dynamic>;
  index['version'] = version;
  files['index.json'] = utf8.encode(jsonEncode(index));
}

List<int> _zip(Map<String, List<int>> files) {
  final archive = Archive();
  for (final entry in files.entries) {
    archive.addFile(ArchiveFile(entry.key, entry.value.length, entry.value));
  }
  return ZipEncoder().encode(archive);
}

String _feed(List<int> bytes) => jsonEncode({
      'format': 'turna-course-feed/1',
      'language': 'tr',
      'latest': {
        'version': 3,
        'expressionsVersion': 1,
        'url': 'nouveau-turkish-3.zip',
        'sha256': sha256.convert(bytes).toString(),
        'sizeBytes': bytes.length,
        'releasedAt': '2026-10-30T12:00:00Z',
        'notes': '测试更新',
      },
      'history': <dynamic>[],
    });

void _serveFiles(HttpServer server, Map<String, List<int>> files) {
  server.listen((request) async {
    final bytes = files[request.uri.path];
    if (bytes == null) {
      request.response.statusCode = HttpStatus.notFound;
    } else {
      request.response.contentLength = bytes.length;
      request.response.add(bytes);
    }
    await request.response.close();
  });
}

Future<void> _writeOldCourse(Directory root) async {
  final target = Directory(p.join(root.path, 'tr'));
  await target.create(recursive: true);
  await File(p.join(target.path, 'marker.txt')).writeAsString('old');
}

Future<String> _oldCourseMarker(Directory root) =>
    File(p.join(root.path, 'tr', 'marker.txt')).readAsString();

Future<void> _expectNoWorkDirs(Directory root) async {
  if (!await root.exists()) return;
  final names =
      await root.list().map((entity) => p.basename(entity.path)).toList();
  expect(names.any((name) => name.startsWith('tr.tmp-')), isFalse);
  expect(names, isNot(contains('tr.backup')));
}

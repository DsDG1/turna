import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:turna/core/logger.dart';
import 'package:turna/courses/course_content_source.dart';
import 'package:turna/domain/course/language_codes.dart';
import 'package:turna/service/content_ota/course_ota_models.dart';
import 'package:turna/service/remote_backup/archive_io.dart';

export 'course_ota_models.dart';

typedef CourseOtaProgress = void Function(int receivedBytes, int totalBytes);
typedef CourseOtaPhaseCallback = void Function(CourseOtaPhase phase);
typedef CourseOtaRename = Future<void> Function(
  Directory from,
  Directory to,
);

/// Downloads and installs a complete builtin-course content package.
///
/// The service stops before the application-layer reseed: after a successful
/// install it invalidates the content-source snapshot, and the caller invokes
/// `CourseProvider.refreshBuiltinContent` so the existing progress policy and
/// study/backup gates remain authoritative.
class CourseOtaService {
  CourseOtaService({
    http.Client? client,
    Future<Directory> Function()? updatesDirectory,
    Future<CourseContentVersion> Function(String languageCode)? currentVersion,
    void Function(String languageCode)? invalidateSource,
    CourseOtaRename? renameDirectory,
    this.allowInsecureHttp = false,
  })  : _client = client ?? http.Client(),
        _ownsClient = client == null,
        _updatesDirectory = updatesDirectory ?? _defaultUpdatesDirectory,
        _currentVersion =
            currentVersion ?? CourseContentSource.instance.versionFor,
        _invalidateSource = invalidateSource ??
            ((code) => CourseContentSource.instance.invalidate(code)),
        _renameDirectory = renameDirectory ?? _defaultRename;

  static const int maxFeedBytes = 1024 * 1024;
  static const int maxPackageBytes = 80 * 1024 * 1024;
  static const int maxUncompressedBytes = 200 * 1024 * 1024;
  static const Duration _connectTimeout = Duration(seconds: 30);

  /// Explicit opt-in for debug/LAN use. HTTPS is always required otherwise.
  final bool allowInsecureHttp;

  final http.Client _client;
  final bool _ownsClient;
  final Future<Directory> Function() _updatesDirectory;
  final Future<CourseContentVersion> Function(String) _currentVersion;
  final void Function(String) _invalidateSource;
  final CourseOtaRename _renameDirectory;
  final Map<String, Future<void>> _operations = {};

  Future<CourseOtaResult> updateFromUrl(
    String rawUrl, {
    String languageCode = 'tr',
    CourseOtaPhaseCallback? onPhase,
    CourseOtaProgress? onProgress,
  }) {
    final code = LanguageCodes.canonicalize(languageCode);
    if (!RegExp(r'^[a-zA-Z0-9_-]+$').hasMatch(code)) {
      throw const CourseOtaException('课程语言代码无效');
    }
    return _serialize(
      code,
      () => _update(
        rawUrl,
        code,
        onPhase ?? (_) {},
        onProgress ?? (received, total) {},
      ),
    );
  }

  /// Deletes the installed package for [languageCode] so the content source
  /// falls back to bundled assets. Returns whether anything was removed.
  ///
  /// Serialized with installs of the same language; the settings entry is
  /// modal, so two instances never run at once. The backup directory goes
  /// first: [_recoverInterruptedInstall] would restore a backup when the
  /// target is missing, resurrecting a package the user just removed.
  Future<bool> clearInstalledContent([String languageCode = 'tr']) {
    final code = LanguageCodes.canonicalize(languageCode);
    if (!RegExp(r'^[a-zA-Z0-9_-]+$').hasMatch(code)) {
      throw const CourseOtaException('课程语言代码无效');
    }
    return _serialize(code, () => _clearInstalled(code));
  }

  Future<bool> _clearInstalled(String code) async {
    final root = await _updatesDirectory();
    if (!await root.exists()) return false;
    var removed = false;
    final backup = Directory(p.join(root.path, '$code.backup'));
    if (await backup.exists()) {
      await backup.delete(recursive: true);
      removed = true;
    }
    final target = Directory(p.join(root.path, code));
    if (await target.exists()) {
      await target.delete(recursive: true);
      removed = true;
    }
    await for (final entity in root.list(followLinks: false)) {
      if (!p.basename(entity.path).startsWith('$code.tmp-')) continue;
      try {
        await entity.delete(recursive: true);
      } catch (error) {
        // Staging leftovers never shadow installed content; recovery wipes them.
        logger.w('Failed to remove stale course OTA temp directory',
            error: error);
      }
    }
    if (removed) _invalidateSource(code);
    return removed;
  }

  void close() {
    if (_ownsClient) _client.close();
  }

  Future<T> _serialize<T>(String code, Future<T> Function() action) async {
    final previous = _operations[code] ?? Future<void>.value();
    final current = Completer<void>();
    _operations[code] = current.future;
    await previous;
    try {
      return await action();
    } finally {
      current.complete();
      if (identical(_operations[code], current.future)) {
        final _ = _operations.remove(code);
      }
    }
  }

  Future<CourseOtaResult> _update(
    String rawUrl,
    String code,
    CourseOtaPhaseCallback onPhase,
    CourseOtaProgress onProgress,
  ) async {
    Directory? work;
    try {
      onPhase(CourseOtaPhase.checking);
      final inputUri = _resolveUrl(rawUrl);
      final root = await _updatesDirectory();
      await root.create(recursive: true);
      await _recoverInterruptedInstall(root, code);
      final currentVersion = await _currentVersion(code);

      CourseFeedRelease? release;
      var packageUri = inputUri;
      if (inputUri.path.toLowerCase().endsWith('.zip')) {
        onPhase(CourseOtaPhase.downloadingPackage);
      } else {
        onPhase(CourseOtaPhase.downloadingFeed);
        final feedResponse = await _getBytes(inputUri, maxFeedBytes);
        final String rawFeed;
        try {
          rawFeed = utf8.decode(feedResponse.bytes);
        } on FormatException catch (error) {
          throw CourseOtaException('课程清单不是有效 UTF-8', cause: error);
        }
        release = parseCourseFeed(rawFeed, code);
        if (CourseContentSource.compareVersions(
                release.version, currentVersion) <=
            0) {
          throw const CourseOtaException('课程包版本不高于当前版本，未安装');
        }
        if (release.sizeBytes > maxPackageBytes) {
          throw const CourseOtaException('课程包超过 80 MB 限制');
        }
        packageUri = _resolveUrl(release.url, base: feedResponse.uri);
        onPhase(CourseOtaPhase.downloadingPackage);
      }

      work = await root.createTemp('$code.tmp-');
      final package = File(p.join(work.path, 'course.zip'));
      final expectedTotal = release?.sizeBytes ?? 0;
      await _downloadToFile(
        packageUri,
        package,
        expectedTotal: expectedTotal,
        onProgress: onProgress,
      );
      final actualSize = await package.length();
      if (release != null && actualSize != release.sizeBytes) {
        throw const CourseOtaException('课程包大小与清单不一致');
      }
      final actualSha256 = archiveFileSha256(package.path);
      if (release != null && actualSha256 != release.sha256) {
        throw const CourseOtaException('课程包 SHA-256 校验失败');
      }

      onPhase(CourseOtaPhase.validating);
      final content = Directory(p.join(work.path, 'content'));
      await content.create();
      await _extractJsonPackage(package, content);
      final packageVersion =
          await CourseContentSource.validateDownloadedDirectory(content, code);
      if (release != null &&
          CourseContentSource.compareVersions(
                  packageVersion, release.version) !=
              0) {
        throw const CourseOtaException('包内版本与课程清单不一致');
      }
      if (CourseContentSource.compareVersions(packageVersion, currentVersion) <=
          0) {
        throw const CourseOtaException('课程包版本不高于当前版本，未安装');
      }

      onPhase(CourseOtaPhase.installing);
      final target = Directory(p.join(root.path, code));
      await _installAtomically(content, target, root, code);
      _invalidateSource(code);
      return CourseOtaResult(
        languageCode: code,
        version: packageVersion,
        packageSha256: actualSha256,
        directory: target,
        notes: release?.notes ?? '',
      );
    } on CourseOtaException {
      rethrow;
    } catch (error) {
      throw CourseOtaException('课程下载或安装失败', cause: error);
    } finally {
      if (work != null && await work.exists()) {
        try {
          await work.delete(recursive: true);
        } catch (error) {
          // A stale temp directory is recovered on the next update attempt.
          logger.w('Failed to clean course OTA temp directory', error: error);
        }
      }
    }
  }

  Future<void> _extractJsonPackage(File package, Directory destination) async {
    final Archive archive;
    try {
      archive = ZipDecoder().decodeBytes(await package.readAsBytes());
    } catch (error) {
      throw CourseOtaException('课程包不是有效 ZIP', cause: error);
    }
    final names = <String>{};
    var totalBytes = 0;
    for (final entry in archive) {
      if (!entry.isFile) continue;
      final name = entry.name;
      _validateZipEntryName(name);
      if (!name.toLowerCase().endsWith('.json')) {
        throw CourseOtaException('课程包只能包含 JSON 文件: $name');
      }
      if (!names.add(name.toLowerCase())) {
        throw CourseOtaException('课程包包含重复路径: $name');
      }
      final content = entry.content as List<int>;
      totalBytes += content.length;
      if (totalBytes > maxUncompressedBytes) {
        throw const CourseOtaException('课程包解压后超过 200 MB 限制');
      }
      final output = File(p.joinAll([destination.path, ...name.split('/')]));
      if (!p.isWithin(destination.path, output.path)) {
        throw const CourseOtaException('课程包路径越界');
      }
      await output.parent.create(recursive: true);
      await output.writeAsBytes(content, flush: true);
    }
  }

  static void _validateZipEntryName(String name) {
    if (name.isEmpty ||
        name.startsWith('/') ||
        name.contains('\\') ||
        name.contains(':') ||
        name.codeUnits.any((unit) => unit < 32) ||
        name
            .split('/')
            .any((part) => part.isEmpty || part == '.' || part == '..')) {
      throw CourseOtaException('课程包包含不安全路径: $name');
    }
  }

  Future<void> _installAtomically(
    Directory content,
    Directory target,
    Directory root,
    String code,
  ) async {
    final backup = Directory(p.join(root.path, '$code.backup'));
    if (await backup.exists()) {
      throw const CourseOtaException('存在未恢复的课程备份，请先重试更新');
    }
    var oldMoved = false;
    if (await target.exists()) {
      await _renameDirectory(target, backup);
      oldMoved = true;
    }
    try {
      await _renameDirectory(content, target);
    } catch (error) {
      if (oldMoved && await backup.exists() && !await target.exists()) {
        try {
          await _renameDirectory(backup, target);
        } catch (rollbackError, stackTrace) {
          // Keep the backup for boot/next-update recovery; never delete it.
          logger.w(
            'Course OTA rollback failed; backup retained',
            error: rollbackError,
            stackTrace: stackTrace,
          );
        }
      }
      throw CourseOtaException('课程目录切换失败，旧版本已保留', cause: error);
    }
    if (await backup.exists()) {
      try {
        await backup.delete(recursive: true);
      } catch (error) {
        // Both directories are valid; recovery keeps the new target next time.
        logger.w('Failed to remove old course backup', error: error);
      }
    }
  }

  Future<void> _recoverInterruptedInstall(Directory root, String code) async {
    final target = Directory(p.join(root.path, code));
    final backup = Directory(p.join(root.path, '$code.backup'));
    if (await backup.exists()) {
      if (await target.exists()) {
        await backup.delete(recursive: true);
      } else {
        await _renameDirectory(backup, target);
      }
    }
    await for (final entity in root.list(followLinks: false)) {
      if (p.basename(entity.path).startsWith('$code.tmp-')) {
        await entity.delete(recursive: true);
      }
    }
  }

  Future<({List<int> bytes, Uri uri})> _getBytes(Uri uri, int limit) async {
    final fetched = await _send(uri);
    final response = fetched.response;
    if (response.contentLength != null && response.contentLength! > limit) {
      await response.stream.drain<void>();
      throw const CourseOtaException('课程清单过大');
    }
    final bytes = BytesBuilder(copy: false);
    await for (final chunk in response.stream) {
      bytes.add(chunk);
      if (bytes.length > limit) {
        throw const CourseOtaException('课程清单过大');
      }
    }
    return (bytes: bytes.takeBytes(), uri: fetched.uri);
  }

  Future<void> _downloadToFile(
    Uri uri,
    File destination, {
    required int expectedTotal,
    required CourseOtaProgress onProgress,
  }) async {
    final fetched = await _send(uri);
    final response = fetched.response;
    final contentLength = response.contentLength;
    final total = expectedTotal > 0
        ? expectedTotal
        : (contentLength != null && contentLength > 0 ? contentLength : 0);
    if (total > maxPackageBytes ||
        (expectedTotal > 0 &&
            contentLength != null &&
            contentLength >= 0 &&
            contentLength != expectedTotal)) {
      await response.stream.drain<void>();
      throw const CourseOtaException('课程包大小与清单或下载限制不一致');
    }
    final sink = destination.openWrite();
    var received = 0;
    try {
      await for (final chunk in response.stream) {
        received += chunk.length;
        if (received > maxPackageBytes ||
            (expectedTotal > 0 && received > expectedTotal)) {
          throw const CourseOtaException('课程包超过清单声明的大小');
        }
        sink.add(chunk);
        onProgress(received, total);
      }
      await sink.flush();
      await sink.close();
    } catch (_) {
      try {
        await sink.close();
      } catch (_) {
        // Best-effort cleanup after the original transport failure.
      }
      rethrow;
    }
    if (expectedTotal > 0 && received != expectedTotal) {
      throw const CourseOtaException('课程包下载不完整');
    }
    if (contentLength != null &&
        contentLength >= 0 &&
        received != contentLength) {
      throw const CourseOtaException('课程包下载不完整');
    }
  }

  Future<({http.StreamedResponse response, Uri uri})> _send(Uri initial) async {
    var uri = initial;
    for (var redirects = 0; redirects <= 5; redirects++) {
      uri = _resolveUrl(uri.toString());
      final request = http.Request('GET', uri)..followRedirects = false;
      final response = await _client.send(request).timeout(_connectTimeout);
      if (_isRedirect(response.statusCode)) {
        if (redirects == 5) {
          await response.stream.drain<void>();
          throw const CourseOtaException('课程下载重定向次数过多');
        }
        final location = response.headers[HttpHeaders.locationHeader];
        if (location == null) {
          await response.stream.drain<void>();
          throw const CourseOtaException('课程下载重定向缺少目标地址');
        }
        await response.stream.drain<void>();
        uri = _resolveUrl(location, base: uri);
        continue;
      }
      if (response.statusCode < 200 || response.statusCode >= 300) {
        await response.stream.drain<void>();
        throw CourseOtaException('课程下载失败（HTTP ${response.statusCode}）');
      }
      return (response: response, uri: uri);
    }
    throw StateError('unreachable');
  }

  Uri _resolveUrl(String raw, {Uri? base}) {
    if (raw.isEmpty ||
        raw.contains('\\') ||
        raw.codeUnits.any((unit) => unit <= 32 || unit == 127)) {
      throw const CourseOtaException('课程下载地址无效');
    }
    final Uri parsed;
    final Uri uri;
    try {
      parsed = Uri.parse(raw);
      uri = base == null ? parsed : base.resolveUri(parsed);
      // Accessing port also validates malformed/overflowing port values.
      final _ = uri.port;
    } on FormatException catch (error) {
      throw CourseOtaException('课程下载地址无效', cause: error);
    } on UnsupportedError catch (error) {
      throw CourseOtaException('课程下载地址无效', cause: error);
    }
    if ((uri.scheme != 'https' && uri.scheme != 'http') ||
        uri.host.isEmpty ||
        uri.userInfo.isNotEmpty ||
        uri.hasQuery ||
        uri.hasFragment) {
      throw const CourseOtaException('课程下载地址必须为无凭据、无查询参数的 HTTPS URL');
    }
    if (uri.scheme == 'http' &&
        (!allowInsecureHttp || !_isLoopbackOrPrivateHost(uri.host))) {
      throw const CourseOtaException('HTTP 仅允许显式启用并用于回环或局域网地址');
    }
    return uri;
  }

  static bool _isRedirect(int statusCode) =>
      statusCode == 301 ||
      statusCode == 302 ||
      statusCode == 303 ||
      statusCode == 307 ||
      statusCode == 308;

  static bool _isLoopbackOrPrivateHost(String host) {
    final normalized = host.toLowerCase();
    if (normalized == 'localhost' || normalized.endsWith('.local')) return true;
    final address = InternetAddress.tryParse(normalized);
    if (address == null || address.isLoopback || address.isLinkLocal) {
      return address != null;
    }
    if (address.type == InternetAddressType.IPv4) {
      final parts = normalized.split('.').map(int.parse).toList();
      return parts[0] == 10 ||
          (parts[0] == 172 && parts[1] >= 16 && parts[1] <= 31) ||
          (parts[0] == 192 && parts[1] == 168);
    }
    final firstByte = int.tryParse(normalized.split(':').first, radix: 16);
    return firstByte != null && firstByte & 0xfe00 == 0xfc00;
  }

  static Future<Directory> _defaultUpdatesDirectory() async {
    final documents = await getApplicationDocumentsDirectory();
    return Directory(p.join(documents.path, 'content_updates'));
  }

  static Future<void> _defaultRename(Directory from, Directory to) async {
    await from.rename(to.path);
  }
}

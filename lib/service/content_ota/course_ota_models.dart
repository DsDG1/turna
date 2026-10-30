import 'dart:convert';
import 'dart:io';

import 'package:turna/courses/course_content_source.dart';

/// Coarse progress states for the manual course-update entry.
enum CourseOtaPhase {
  checking,
  downloadingFeed,
  downloadingPackage,
  validating,
  installing,
}

class CourseOtaException implements Exception {
  const CourseOtaException(this.message, {this.cause});

  final String message;
  final Object? cause;

  @override
  String toString() => cause == null
      ? 'CourseOtaException: $message'
      : 'CourseOtaException: $message ($cause)';
}

/// The single release consumed by the phase-one updater.
class CourseFeedRelease {
  const CourseFeedRelease({
    required this.version,
    required this.url,
    required this.sha256,
    required this.sizeBytes,
    required this.releasedAt,
    required this.notes,
  });

  final CourseContentVersion version;
  final String url;
  final String sha256;
  final int sizeBytes;
  final String releasedAt;
  final String notes;
}

class CourseOtaResult {
  const CourseOtaResult({
    required this.languageCode,
    required this.version,
    required this.packageSha256,
    required this.directory,
    this.notes = '',
  });

  final String languageCode;
  final CourseContentVersion version;
  final String packageSha256;
  final Directory directory;
  final String notes;
}

CourseFeedRelease parseCourseFeed(String raw, String expectedLanguage) {
  final Object? decoded;
  try {
    decoded = jsonDecode(raw);
  } on FormatException catch (error) {
    throw CourseOtaException('课程清单不是有效 JSON', cause: error);
  }
  if (decoded
      case {
        'format': 'turna-course-feed/1',
        'language': String language,
        'latest': Map<String, dynamic> latest,
      }) {
    if (language != expectedLanguage) {
      throw const CourseOtaException('课程清单与目标语言不一致');
    }
    final version = _feedVersion(latest['version'], 'version');
    final expressionsVersion =
        _feedVersion(latest['expressionsVersion'], 'expressionsVersion');
    final url = latest['url'];
    final sha256 = latest['sha256'];
    final sizeBytes = latest['sizeBytes'];
    final releasedAt = latest['releasedAt'];
    final notes = latest['notes'];
    if (url is! String || url.isEmpty) {
      throw const CourseOtaException('课程清单缺少有效的下载地址');
    }
    if (sha256 is! String || !RegExp(r'^[0-9a-f]{64}$').hasMatch(sha256)) {
      throw const CourseOtaException('课程清单的 SHA-256 无效');
    }
    if (sizeBytes is! int || sizeBytes <= 0) {
      throw const CourseOtaException('课程清单的包大小无效');
    }
    if (releasedAt is! String || notes is! String) {
      throw const CourseOtaException('课程清单的发布信息无效');
    }
    final parsedDate = DateTime.tryParse(releasedAt);
    if (parsedDate == null ||
        (!releasedAt.endsWith('Z') &&
            !RegExp(r'[+-]\d\d:\d\d$').hasMatch(releasedAt))) {
      throw const CourseOtaException('课程清单的发布时间必须包含时区');
    }
    return CourseFeedRelease(
      version: (index: version, expressions: expressionsVersion),
      url: url,
      sha256: sha256,
      sizeBytes: sizeBytes,
      releasedAt: releasedAt,
      notes: notes,
    );
  }
  throw const CourseOtaException('不支持的课程清单格式');
}

int _feedVersion(Object? value, String field) {
  if (value is! int || value < 0) {
    throw CourseOtaException('课程清单的 $field 无效');
  }
  return value;
}

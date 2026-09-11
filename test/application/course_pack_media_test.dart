import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:turna/application/course_pack/course_pack.dart';
import 'package:turna/application/course_pack/course_pack_media.dart';

void main() {
  group('CoursePackMedia', () {
    test('rewrite turns media/ paths into turnapack URIs', () {
      expect(
        CoursePackMedia.rewrite('media/dog1.jpg', 'es'),
        'turnapack://es/dog1.jpg',
      );
      expect(
        CoursePackMedia.rewrite('turnapack://es/dog1.jpg', 'es'),
        'turnapack://es/dog1.jpg',
      );
      expect(CoursePackMedia.rewrite('ll-es-w-hola', 'es'), 'll-es-w-hola');
    });

    test('rejects path traversal in relative names', () {
      expect(CoursePackMedia.isAllowedMediaName('../x.jpg'), isFalse);
      expect(CoursePackMedia.isAllowedMediaName('dog1.jpg'), isTrue);
      expect(CoursePackMedia.isAllowedMediaName('nested/dog1.png'), isTrue);
      expect(CoursePackMedia.isAllowedMediaName('notes.txt'), isFalse);
    });

    test('resolveFile only returns files inside the language media dir', () async {
      final root = await Directory.systemTemp.createTemp('pack-media-');
      addTearDown(() {
        if (root.existsSync()) root.deleteSync(recursive: true);
        CoursePackMedia.debugPersistRoot = null;
      });
      CoursePackMedia.debugPersistRoot = root;
      final media = Directory(p.join(root.path, 'es', 'media'))
        ..createSync(recursive: true);
      final dog = File(p.join(media.path, 'dog1.jpg'))
        ..writeAsBytesSync(const [1, 2, 3]);
      expect(
        await CoursePackMedia.resolveFile('turnapack://es/dog1.jpg'),
        dog.path,
      );
      expect(await CoursePackMedia.resolveFile('turnapack://es/../dog1.jpg'), isNull);
      expect(await CoursePackMedia.resolveFile('turnapack://es/missing.jpg'), isNull);
    });
  });

  group('CoursePack media rewrite', () {
    test('rewrites known media fields in nested JSON files', () {
      final pack = CoursePack.parse('''
{
  "format": "turnapack/2",
  "packVersion": 1,
  "language": {
    "code": "es",
    "displayName": "Spanish",
    "ttsLocale": "es-ES",
    "nativeLabel": "es"
  },
  "license": {"name": "CC", "attribution": "x", "link": "https://example.com"},
  "files": {
    "index.json": {"version": 1, "language": "es", "sections": []},
    "vocab.json": {
      "words": [{"id": "ll-es-w-a", "audioAsset": "media/a.mp3"}]
    }
  }
}
''');
      expect(pack.mediaRelativeRefs(), {'a.mp3'});
      final rewritten = pack.withRewrittenMediaRefs();
      expect(rewritten.files['vocab.json'], contains('turnapack://es/a.mp3'));
      expect(rewritten.mediaRelativeRefs(), isEmpty);
    });
  });
}

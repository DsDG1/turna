import 'package:flutter_test/flutter_test.dart';
import 'package:turna/courses/bundled_media_paths.dart';

void main() {
  const dir = 'assets/courses/turkish';

  test('media/ refs become bundled asset paths', () {
    expect(
      rewriteBundledMediaRef('media/a.png', dir),
      'assets/courses/turkish/media/a.png',
    );
    expect(
      rewriteBundledMediaRef(r'media\a.png', '$dir/'),
      'assets/courses/turkish/media/a.png',
    );
  });

  test('unsafe refs, word ids, and external schemes stay unchanged', () {
    expect(rewriteBundledMediaRef('media/../a.png', dir), 'media/../a.png');
    expect(rewriteBundledMediaRef('media/', dir), 'media/');
    expect(rewriteBundledMediaRef('media/C:/a.png', dir), 'media/C:/a.png');
    expect(rewriteBundledMediaRef('media//a.png', dir), 'media//a.png');
    expect(rewriteBundledMediaRef('w1', dir), 'w1');
    expect(rewriteBundledMediaRef('anki://x', dir), 'anki://x');
    expect(
      rewriteBundledMediaRef('turnapack://es/a.png', dir),
      'turnapack://es/a.png',
    );
    expect(rewriteBundledMediaRef(null, dir), isNull);
  });

  test('trees rewrite media fields and lists only', () {
    final rewritten = rewriteBundledMediaTree(
      {
        'audioAsset': 'media/a.mp3',
        'imageAssets': ['media/a.png', 'anki://keep'],
        'wordId': 'media/not-a-media-key',
        'nested': {
          'imageAsset': 'media/b.png',
        },
      },
      dir,
    ) as Map<String, dynamic>;
    expect(rewritten['audioAsset'], 'assets/courses/turkish/media/a.mp3');
    expect(rewritten['imageAssets'], [
      'assets/courses/turkish/media/a.png',
      'anki://keep',
    ]);
    expect(rewritten['wordId'], 'media/not-a-media-key');
    expect(
      (rewritten['nested'] as Map)['imageAsset'],
      'assets/courses/turkish/media/b.png',
    );
  });
}

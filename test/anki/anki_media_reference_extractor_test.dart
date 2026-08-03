import 'package:flutter_test/flutter_test.dart';
import 'package:varnamala/application/anki/anki_media_reference_extractor.dart';

void main() {
  const extractor = AnkiMediaReferenceExtractor();

  test('extracts sound, audio and nested source references case-insensitively',
      () {
    final result = extractor.extract(
      '[SOUND:first.mp3]'
          '<AUDIO src="second.ogg"></AUDIO>'
          "<audio><source src='third.m4a'></audio>",
      'imp',
    );

    expect(result.audios, [
      'anki://imp/second.ogg',
      'anki://imp/third.m4a',
      'anki://imp/first.mp3',
    ]);
  });

  test('normalizes HTML entities, percent encoding and Unicode filenames', () {
    final result = extractor.extract(
      '<audio src="语音%20一&amp;二.mp3?cache=1"></audio>'
          '[sound:%E8%AF%AD%E9%9F%B3%20%E4%B8%80%26%E4%BA%8C.mp3]',
      '中文牌组',
    );

    expect(result.audios, ['anki://中文牌组/语音 一&二.mp3']);
  });

  test('deduplicates references shared by front and back HTML', () {
    final result = extractor.extract(
      '[sound:same.mp3]<audio src="same.mp3"></audio>',
      'imp',
    );

    expect(result.audios, ['anki://imp/same.mp3']);
  });

  test('rejects network, absolute, schemed and traversal references', () {
    final result = extractor.extract(
      '<audio src="https://example.com/a.mp3"></audio>'
          '<audio src="//example.com/b.mp3"></audio>'
          '<audio src="file:///tmp/c.mp3"></audio>'
          '<audio src="../d.mp3"></audio>'
          '<audio src="safe/%2e%2e/e.mp3"></audio>'
          '<audio src="/absolute/f.mp3"></audio>',
      'imp',
    );

    expect(result.audios, isEmpty);
  });

  test('keeps safe nested local paths and separates image references', () {
    final result = extractor.extract(
      '<img src="images/pic.png">'
          '<video><source src="video/clip.mp4"></video>'
          '<audio><source src="audio/clip.wav"></audio>'
          '<div style="background:url(bg/card.png)"></div>',
      'imp',
    );

    expect(result.audios, ['anki://imp/audio/clip.wav']);
    expect(result.images, [
      'anki://imp/images/pic.png',
      'anki://imp/video/clip.mp4',
      'anki://imp/bg/card.png',
    ]);
  });
}

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:turna/views/anki/anki_webview_sizing.dart';

void main() {
  AnkiWebViewSizingResult resolve({
    Size viewport = const Size(412, 915),
    Orientation orientation = Orientation.portrait,
    AnkiWebViewScene scene = AnkiWebViewScene.lesson,
    double keyboardBottom = 0,
  }) {
    return resolveAnkiWebViewSizing(
      AnkiWebViewSizingInput(
        viewport: viewport,
        orientation: orientation,
        scene: scene,
        keyboardBottom: keyboardBottom,
      ),
    );
  }

  group('lesson scene', () {
    test('portrait phone: large initial window within [320, 720]', () {
      final r = resolve();
      expect(r.fillRemainingSpace, isFalse);
      expect(r.initialCardHeight, greaterThanOrEqualTo(320));
      expect(r.initialCardHeight, lessThanOrEqualTo(720));
      // ~52% of a 915 tall viewport, clamped.
      expect(r.initialCardHeight, closeTo(476, 1));
      expect(r.minCardHeight, 320);
      expect(r.maxCardHeight, 720);
    });

    test('short screens clamp the initial window to the minimum', () {
      // 52% of 580 is below 320 -> the floor wins.
      final r = resolve(viewport: const Size(360, 580));
      expect(r.initialCardHeight, 320);
    });

    test('landscape: min 240 and content height stays bounded', () {
      final r = resolve(
        viewport: const Size(915, 412),
        orientation: Orientation.landscape,
      );
      expect(r.minCardHeight, 240);
      expect(r.initialCardHeight, greaterThanOrEqualTo(240));
      expect(r.maxCardHeight, lessThanOrEqualTo(720));
      expect(
        r.maxCardHeight,
        lessThanOrEqualTo(412 * 0.9 + 0.5),
        reason: 'landscape cap keeps bottom actions visible',
      );
    });

    test('keyboard open lowers the floor so inputs stay reachable', () {
      // The shrunk viewport (keyboard consumes the bottom) keeps the window
      // small instead of forcing the 320dp portrait minimum.
      final r = resolve(viewport: const Size(412, 500), keyboardBottom: 280);
      expect(r.minCardHeight, 200);
      expect(r.initialCardHeight, 260);
    });
  });

  group('review and preview scenes fill remaining space', () {
    test('unified review', () {
      final r = resolve(scene: AnkiWebViewScene.review);
      expect(r.fillRemainingSpace, isTrue);
    });

    test('official preview', () {
      final r = resolve(scene: AnkiWebViewScene.officialPreview);
      expect(r.fillRemainingSpace, isTrue);
    });
  });

  group('page chrome', () {
    test('phone keeps 20dp padding, narrow phones 16dp', () {
      expect(resolve().horizontalPadding, 20);
      expect(
        resolve(viewport: const Size(360, 640)).horizontalPadding,
        16,
      );
    });

    test('tablet centers content within 760dp', () {
      final r = resolve(viewport: const Size(800, 1280));
      expect(r.maxContentWidth, 760);
      expect(r.horizontalPadding, closeTo((800 - 760) / 2, 0.5));
      expect(
        resolve(viewport: const Size(1280, 800), scene: AnkiWebViewScene.review)
            .maxContentWidth,
        760,
      );
    });

    test('bottom gap shrinks on short screens but never below 8dp', () {
      expect(resolve().bottomGap, lessThanOrEqualTo(24));
      final short = resolve(viewport: const Size(360, 250));
      expect(short.bottomGap, 8);
    });
  });

  group('content height merging', () {
    test('long content is clamped to the max', () {
      final sizing = resolve();
      final next = resolveLessonCardHeight(
        currentHeight: sizing.initialCardHeight,
        contentHeight: 5000,
        sizing: sizing,
      );
      expect(next, 720);
    });

    test('short content never shrinks below the minimum', () {
      final sizing = resolve();
      final next = resolveLessonCardHeight(
        currentHeight: sizing.initialCardHeight,
        contentHeight: 40,
        sizing: sizing,
      );
      expect(next, 320);
    });

    test('jitter under the 2dp epsilon keeps the current height', () {
      final sizing = resolve();
      final jittered = resolveLessonCardHeight(
        currentHeight: 400,
        contentHeight: 401,
        sizing: sizing,
      );
      expect(jittered, 400);
      final applied = resolveLessonCardHeight(
        currentHeight: 400,
        contentHeight: 420,
        sizing: sizing,
      );
      expect(applied, 420);
    });

    test('invalid reported heights are ignored', () {
      final sizing = resolve();
      for (final bad in <double?>[-5, 0, double.nan, double.infinity, null]) {
        expect(
          resolveLessonCardHeight(
            currentHeight: 400,
            contentHeight: bad,
            sizing: sizing,
          ),
          400,
        );
      }
    });
  });
}

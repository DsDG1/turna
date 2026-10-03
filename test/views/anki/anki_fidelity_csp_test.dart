import 'package:flutter_test/flutter_test.dart';
import 'package:turna/views/anki/anki_fidelity_csp.dart';

/// Security contract for the fidelity Anki WebView.
///
/// The card HTML reaching that WebView is attacker-controlled (imported
/// decks) and the `NavigationDelegate` only intercepts top-level
/// navigations. This policy is the layer that denies subresource egress, so
/// every directive below is asserted individually: losing one directive
/// silently reopens a channel (a remote `<img>` is itself an exfiltration
/// path because its query string can carry card data).
void main() {
  /// Directives that must never contain a remote origin, and must not be
  /// omitted (an omitted directive falls back to `default-src`).
  const networkBound = {
    'script-src': "'unsafe-inline'",
    'connect-src': "'none'",
    'object-src': "'none'",
    'form-action': "'none'",
    'frame-src': "'none'",
  };

  group('policy shape', () {
    test('denies everything by default', () {
      expect(AnkiFidelityCsp.policy, contains("default-src 'none'"));
    });

    test('keeps inline script and style for template fidelity', () {
      expect(AnkiFidelityCsp.policy, contains("script-src 'unsafe-inline'"));
      expect(AnkiFidelityCsp.policy, contains("style-src 'unsafe-inline'"));
    });

    test('every egress-capable directive is present and remote-free', () {
      for (final entry in networkBound.entries) {
        final match = RegExp('${entry.key}\\s+([^;]+);')
            .firstMatch(AnkiFidelityCsp.policy);
        expect(match, isNotNull,
            reason: '${entry.key} must be declared explicitly, not inherited '
                'from default-src');
        expect(match!.group(1)!.trim(), entry.value,
            reason: '${entry.key} drifted from the approved value');
        expect(match.group(1)!, isNot(contains('http')),
            reason: '${entry.key} must not name a remote origin');
        expect(match.group(1)!, isNot(contains('*')),
            reason: '${entry.key} must not be a wildcard');
      }
    });

    test('media, fonts and images are local-only', () {
      for (final directive in ['img-src', 'media-src', 'font-src']) {
        final match =
            RegExp('$directive\\s+([^;]+);').firstMatch(AnkiFidelityCsp.policy);
        expect(match, isNotNull, reason: '$directive must be declared');
        final value = match!.group(1)!;
        expect(value, contains('file:'));
        expect(value, contains('data:'));
        expect(value, isNot(contains('http')),
            reason: '$directive must not load remote media');
      }
    });
  });

  group('inject', () {
    test('places the policy as the first child of <head>', () {
      const html = '<html><head><title>t</title>'
          '<style>.card{}</style></head><body>hi</body></html>';
      final out = AnkiFidelityCsp.inject(html);

      expect(out, startsWith('<html><head>${AnkiFidelityCsp.metaTag}'));
      // The policy must precede every author resource to govern all of them.
      expect(out.indexOf('Content-Security-Policy'),
          lessThan(out.indexOf('<style>')));
    });

    test('handles a <head> carrying attributes', () {
      const html = '<html><head profile="x"><style></style></head></html>';
      final out = AnkiFidelityCsp.inject(html);

      expect(out, contains('<head profile="x">${AnkiFidelityCsp.metaTag}'));
    });

    test('is case-insensitive on the head tags', () {
      final out = AnkiFidelityCsp.inject('<HTML><HEAD></HEAD></HTML>');

      expect(out, contains(AnkiFidelityCsp.metaTag));
    });

    test('falls back to a closing </head> when the opener is missing', () {
      const html = '<style>.card{}</style></head><body>hi</body>';
      final out = AnkiFidelityCsp.inject(html);

      expect(out, contains('${AnkiFidelityCsp.metaTag}</head>'));
    });

    test('wraps a headless fragment, because meta in body is ignored', () {
      const html = '<div class="card">hi</div>';
      final out = AnkiFidelityCsp.inject(html);

      expect(out, startsWith('<!DOCTYPE html>'));
      expect(out, contains('<head>${AnkiFidelityCsp.metaTag}'));
      expect(out, contains('<div class="card">hi</div>'));
    });

    test('preserves author content byte for byte', () {
      const html = '<html><head><style>.a{color:red}</style></head>'
          '<body><p>Merhaba &amp; hoş geldin</p>'
          '<script>window.x=1</script></body></html>';
      final out = AnkiFidelityCsp.inject(html);

      // Only an insertion happened: stripping the policy yields the input.
      expect(out.replaceFirst(AnkiFidelityCsp.metaTag, ''), html);
    });

    test('does not stack a second policy when the card declares its own', () {
      const authored = '<html><head>'
          '<meta http-equiv="Content-Security-Policy" content="default-src \'none\'">'
          '</head><body>hi</body></html>';
      final out = AnkiFidelityCsp.inject(authored);

      expect(AnkiFidelityCsp.hasCspMeta(out), isTrue);
      expect(RegExp('Content-Security-Policy').allMatches(out).length, 1);
    });

    test('detects a report-only policy as already present', () {
      const authored = '<head><meta http-equiv="Content-Security-Policy-'
          'Report-Only" content="default-src \'none\'"></head>';

      expect(AnkiFidelityCsp.hasCspMeta(authored), isTrue);
      expect(AnkiFidelityCsp.inject(authored), authored);
    });

    test('a card cannot smuggle the tag past the detector', () {
      // Without the quote/space/bracket terminator in the pattern a crafted
      // deck could satisfy the naive substring check and suppress our policy.
      const crafted = '<head><meta name="x" http-equiv='
          '"Content-Security-Policyevil"></head>';

      expect(AnkiFidelityCsp.hasCspMeta(crafted), isFalse);
      expect(
          AnkiFidelityCsp.inject(crafted), contains(AnkiFidelityCsp.metaTag));
    });

    test('is a pure function: repeated injection is idempotent', () {
      const html = '<html><head><style></style></head><body></body></html>';
      final once = AnkiFidelityCsp.inject(html);

      expect(AnkiFidelityCsp.inject(once), once);
    });
  });
}

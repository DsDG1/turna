import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final root = Directory('assets/anki_reviewer');

  test('reviewer assets exist, are hashed, and never load a CDN', () {
    final manifestFile = File('${root.path}/manifest.json');
    expect(manifestFile.existsSync(), isTrue);
    final manifest = jsonDecode(manifestFile.readAsStringSync()) as Map<String, dynamic>;
    expect(manifest['mathjaxVersion'], '3.2.2');
    expect(manifest['backendCommit'], '967aa0d578fc75181e292e95326f9b58698da25c');
    final files = (manifest['files'] as List).cast<Map<String, dynamic>>();
    expect(files.map((f) => f['path']), containsAll([
      'reviewer.html',
      'reviewer.js',
      'reviewer.css',
      'card-frame.html',
      'card-frame.js',
      'mathjax-config.js',
      'mathjax/tex-svg-full.js',
    ]));
    for (final entry in files) {
      final file = File('${root.path}/${entry['path']}');
      expect(file.existsSync(), isTrue, reason: entry['path'] as String);
      final digest = sha256.convert(file.readAsBytesSync()).toString();
      expect(digest, entry['sha256'], reason: entry['path'] as String);
    }
    final html = File('${root.path}/reviewer.html').readAsStringSync();
    final js = File('${root.path}/reviewer.js').readAsStringSync();
    final frameHtml = File('${root.path}/card-frame.html').readAsStringSync();
    final frameJs = File('${root.path}/card-frame.js').readAsStringSync();
    final config = File('${root.path}/mathjax-config.js').readAsStringSync();
    for (final text in [html, js, frameHtml, frameJs, config]) {
      expect(text.contains('cdn.jsdelivr'), isFalse);
      expect(text.contains('cdnjs'), isFalse);
      expect(RegExp(r'(^|[^s])http://').hasMatch(text), isFalse);
    }
    expect(html.contains('<base href="https://anki.local/media/">'), isTrue);
    expect(html.contains('https://anki.local/assets/reviewer.js'), isTrue);
    expect(html.contains('https://anki.local/assets/reviewer.css'), isTrue);
    expect(frameHtml.contains('<base href="https://anki.local/media/">'), isTrue);
    expect(frameHtml.contains('https://anki.local/assets/card-frame.js'), isTrue);
    expect(js.contains('OfficialReviewer'), isTrue);
    expect(js.contains('present:'), isTrue);
    expect(js.contains('opacity = "0"'), isFalse);
    expect(js.contains('loadHtmlString'), isFalse);
    expect(js.contains('addJavascriptInterface'), isFalse);
    expect(js.contains('setAttribute("sandbox", "allow-scripts")'), isTrue);
    expect(js.contains('allow-same-origin'), isFalse);
    expect(js.contains('testSnapshot'), isFalse);
    expect(frameJs.contains('testSnapshot'), isTrue);
    expect(frameJs.contains('testSnapshotResult'), isTrue);
    expect(RegExp(r'sandbox"\s*,\s*"allow-scripts allow-').hasMatch(js), isFalse);
    expect(frameJs.contains('MATHJAX_ASSET_MISSING'), isTrue);
    expect(frameJs.contains('renderComplete'), isTrue);
    expect(frameJs.contains('scrollHeight'), isTrue);
    expect(frameJs.contains('applyBodyClass'), isTrue);
    final instrumented = File(
      'android/app/src/androidTest/kotlin/me/dsdogs/turna/anki/reviewer/OfficialAnkiReviewerFlipPathTest.kt',
    ).readAsStringSync();
    expect(instrumented.contains('contentDocument'), isFalse);
    expect(instrumented.contains('testSnapshot'), isTrue);
    expect(instrumented.contains('allow-same-origin'), isFalse);
  });

  test('Android reviewer source hardens WebView and has no JS bridge', () {
    final files = [
      'android/app/src/main/kotlin/me/dsdogs/turna/anki/reviewer/OfficialAnkiWebPolicy.kt',
      'android/app/src/main/kotlin/me/dsdogs/turna/anki/reviewer/OfficialAnkiMediaHandler.kt',
      'android/app/src/main/kotlin/me/dsdogs/turna/anki/reviewer/OfficialAnkiReviewerClient.kt',
      'android/app/src/main/kotlin/me/dsdogs/turna/anki/reviewer/OfficialAnkiReviewerPlatformView.kt',
      'android/app/src/main/kotlin/me/dsdogs/turna/anki/reviewer/OfficialAnkiReviewerPlugin.kt',
      'android/app/src/main/kotlin/me/dsdogs/turna/MainActivity.kt',
    ];
    for (final path in files) {
      expect(File(path).existsSync(), isTrue, reason: path);
    }
    final policy = File(files[0]).readAsStringSync();
    expect(policy.contains('allowFileAccess = false'), isTrue);
    expect(policy.contains('allowContentAccess = false'), isTrue);
    expect(policy.contains('MIXED_CONTENT_NEVER_ALLOW'), isTrue);
    expect(policy.contains('setSupportMultipleWindows(false)'), isTrue);
    expect(policy.contains('setGeolocationEnabled(false)'), isTrue);
    final csp = File(
      'android/app/src/main/kotlin/me/dsdogs/turna/anki/reviewer/OfficialAnkiCsp.kt',
    ).readAsStringSync();
    expect(csp.contains('frame-src https://anki.local'), isTrue);
    final view = File(files[3]).readAsStringSync();
    expect(view.contains('addJavascriptInterface'), isFalse);
    expect(view.contains('onPermissionRequest'), isTrue);
    expect(view.contains('request.deny()'), isTrue);
    expect(view.contains('onJsConfirm'), isTrue);
    expect(view.contains('onJsPrompt'), isTrue);
    expect(view.contains('onShowFileChooser'), isTrue);
    expect(view.contains('if (disposed) return'), isTrue);
    expect(view.contains('pollCompletion'), isTrue);
    final main = File(files[5]).readAsStringSync();
    expect(main.contains('OfficialAnkiReviewerPlugin.register'), isTrue);
    final client = File(files[2]).readAsStringSync();
    expect(client.contains('shouldInterceptRequest'), isTrue);
    expect(client.contains('onReceivedClientCertRequest'), isTrue);
    final plugin = File(files[4]).readAsStringSync();
    expect(plugin.contains('MATHJAX_ASSET_MISSING'), isTrue);
  });
}

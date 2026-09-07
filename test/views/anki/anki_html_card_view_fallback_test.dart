import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:turna/core/html_stripper.dart';
import 'package:turna/views/anki/anki_html_card_view.dart';

/// Contract for the desktop/web text fallback: it must render exactly what
/// [stripHtml] produces (the same function the TTS pipeline uses), so TTS
/// reads the text the user sees. This pins the stripHtml ↔ fallback mirror
/// that previously lived as two hand-synced implementations.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const cardHtml = '''
<html><head><meta charset="utf-8"><style>.card{font-size:20px}</style></head>
<body>
<script>decrypt("payload")</script>
<p>Merhaba&nbsp;dünya &amp; arkadaşlar</p>
<p>ışıksız<br/>gölge</p>
</body></html>
''';

  Future<void> pumpCard(WidgetTester tester, {bool typeAnswer = false}) {
    return tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AnkiHtmlCardView(
            html: cardHtml,
            typeAnswerEnabled: typeAnswer,
          ),
        ),
      ),
    );
  }

  testWidgets('renders exactly stripHtml output for the same card',
      (tester) async {
    await pumpCard(tester);

    final rendered =
        tester.widget<SelectableText>(find.byType(SelectableText)).data!;
    expect(rendered, stripHtml(cardHtml));
  }, variant: TargetPlatformVariant.only(TargetPlatform.windows));

  testWidgets('visible card text survives; style/script text does not',
      (tester) async {
    await pumpCard(tester);

    final rendered =
        tester.widget<SelectableText>(find.byType(SelectableText)).data!;
    expect(rendered, contains('Merhaba dünya & arkadaşlar'));
    // <br> becomes whitespace instead of gluing the words together.
    expect(rendered, contains('ışıksız gölge'));
    expect(rendered, isNot(contains('font-size')));
    expect(rendered, isNot(contains('decrypt')));
  }, variant: TargetPlatformVariant.only(TargetPlatform.windows));

  testWidgets('typing cards offer a native input in the fallback',
      (tester) async {
    await pumpCard(tester, typeAnswer: true);

    expect(find.byType(TextField), findsOneWidget);
  }, variant: TargetPlatformVariant.only(TargetPlatform.windows));
}

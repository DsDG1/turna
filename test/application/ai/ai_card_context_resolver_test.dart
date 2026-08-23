// Unit tests for [AiCardContextResolver] (Plan 3 §20 / test matrix §26.2):
// reveal policy, HTML/JS/path sanitization, official-template plaintext
// (never raw scheduling ids), and the unsupported state.

import 'package:flutter_test/flutter_test.dart';
import 'package:turna/application/ai/ai_card_context_resolver.dart';
import 'package:turna/application/review_dashboard/review_dashboard_models.dart';
import 'package:turna/domain/course/interaction.dart';
import 'package:turna/domain/review/review_capabilities.dart';
import 'package:turna/domain/review/review_item.dart';
import 'package:turna/domain/review/review_source.dart';

ReviewItem _item(
  ReviewContentBodyData content, {
  ReviewSource source = const TurnaCourseSource(),
  String rawId = 'card-1',
}) =>
    ReviewItem(
      sessionItemId: 's-$rawId',
      source: source,
      content: content,
      capabilities: const ReviewCapabilities(),
      schedulingKey: ReviewSchedulingKey(rawId: rawId, source: source),
    );

void main() {
  const resolver = AiCardContextResolver();

  test('standard card: question always, answer only after reveal', () {
    const content = StandardCourseCardContent(
      frontText: 'Merhaba',
      backText: '你好',
    );

    final hidden = resolver.resolve(_item(content), answerRevealed: false);
    expect(hidden.questionPlainText, 'Merhaba');
    expect(hidden.answerPlainText, isNull,
        reason: '未揭示时答案不得进入 prompt（§20.3）');
    expect(hidden.supported, isTrue);
    expect(
        hidden.toPromptBlock().contains('你好'), isFalse,
        reason: 'prompt digest must not leak the hidden answer');

    final revealed = resolver.resolve(_item(content), answerRevealed: true);
    expect(revealed.answerPlainText, '你好');
    expect(revealed.toPromptBlock().contains('你好'), isTrue);
  });

  test('official template card uses sanitized HTML, never the raw id', () {
    const content = OfficialTemplateContent(
      frontHtml:
          '<div class="card"><script>steal()</script>{{Field}}<img src="/data/media/x.png">ev</div>',
      backHtml: '<b>answer</b><style>.x{}</style>',
    );

    final ctx = resolver.resolve(
      _item(content,
          source: OfficialAnkiSource(
              sourceId: 'official-1', deckId: 3, cardId: 99),
          rawId: '1699999999999'),
      answerRevealed: true,
    );

    expect(ctx.presentationKind, 'officialTemplate');
    // Real card text survives, script/style/tags/paths/directives don't.
    expect(ctx.questionPlainText, contains('ev'));
    expect(ctx.questionPlainText, isNot(contains('steal')));
    expect(ctx.questionPlainText, isNot(contains('<')));
    expect(ctx.questionPlainText, isNot(contains('/data/media')));
    expect(ctx.questionPlainText, isNot(contains('{{')));
    expect(ctx.answerPlainText, 'answer');
    // The raw scheduling id must not impersonate learning content.
    expect(ctx.questionPlainText, isNot(contains('1699999999999')));
    expect(ctx.source.kind, LearningSourceKind.ankiOfficial);
  });

  test('legacy AnkiCard interaction prefers adapted plain fields', () {
    const content = StandardCourseCardContent(
      frontText: '',
      backText: '',
      interaction: Interaction.ankiCard(
        front: 'ev',
        back: '_house',
        audioAssets: ['anki://imp1/a.mp3'],
      ),
    );
    final ctx = resolver.resolve(
      _item(content, source: const LegacyAnkiSource(importId: 'imp1')),
      answerRevealed: true,
    );
    expect(ctx.presentationKind, 'ankiLegacy');
    expect(ctx.questionPlainText, 'ev');
    expect(ctx.answerPlainText, '_house');
    expect(ctx.media, isNotEmpty,
        reason: 'media presence is described, not the files');
  });

  test('empty question plaintext becomes unsupported, sending nothing',
      () async {
    const content = OfficialTemplateContent(
      frontHtml: '<script>only script</script>',
      backHtml: 'x',
    );
    final ctx = resolver.resolve(_item(content), answerRevealed: true);
    expect(ctx.supported, isFalse);
    expect(ctx.questionPlainText, isEmpty);
    expect(ctx.toPromptBlock(), contains('unavailable'));
  });

  test('entities decode and whitespace collapses', () {
    const content = OfficialTemplateContent(
      frontHtml: '<p>a&nbsp;&amp;&nbsp;b</p><br/><p>c</p>',
      backHtml: 'x',
    );
    final ctx = resolver.resolve(_item(content), answerRevealed: false);
    expect(ctx.questionPlainText, 'a & b c');
  });

  test('oversized text is clamped', () {
    final big = 'x' * 9000;
    final content =
        StandardCourseCardContent(frontText: big, backText: big);
    final ctx = resolver.resolve(_item(content), answerRevealed: true);
    expect(ctx.questionPlainText.length, lessThan(4100));
    expect(ctx.answerPlainText!.length, lessThan(4100));
  });
}

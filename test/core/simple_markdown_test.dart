import 'package:flutter_test/flutter_test.dart';
import 'package:turna/core/simple_markdown.dart';

void main() {
  test('parses headings, lists, and fenced code', () {
    final blocks = parseSimpleMarkdown('''
# Title
- one
2. two

```
final x = 1;
```
''');
    expect(blocks.map((b) => b.kind), [
      MarkdownBlockKind.heading,
      MarkdownBlockKind.bullet,
      MarkdownBlockKind.numbered,
      MarkdownBlockKind.code,
    ]);
    expect(blocks.first.level, 1);
    expect(blocks[2].level, 2);
    expect(blocks.last.code, 'final x = 1;');
  });

  test('parses inline bold, italic, and code', () {
    final spans = parseMarkdownInlines('say **merhaba** and *iyi* plus `var`');
    expect(spans.map((s) => s.text),
        ['say ', 'merhaba', ' and ', 'iyi', ' plus ', 'var']);
    expect(spans[1].bold, isTrue);
    expect(spans[3].italic, isTrue);
    expect(spans[5].code, isTrue);
  });

  test('plain text stays one paragraph', () {
    final blocks = parseSimpleMarkdown('hello');
    expect(blocks, hasLength(1));
    expect(blocks.single.kind, MarkdownBlockKind.paragraph);
    expect(blocks.single.spans.single.text, 'hello');
  });
}

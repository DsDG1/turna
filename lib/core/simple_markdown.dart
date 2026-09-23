// Lightweight Markdown subset for AI chat bubbles.
//
// Covers the shapes model replies actually use: headings, fenced code,
// bullets, numbered items, and inline bold / italic / code. No new package:
// flutter_markdown is unmaintained, and a full renderer is more than these
// bubbles need.

enum MarkdownBlockKind { paragraph, heading, code, bullet, numbered }

class MarkdownSpan {
  const MarkdownSpan(
    this.text, {
    this.bold = false,
    this.italic = false,
    this.code = false,
  });

  final String text;
  final bool bold;
  final bool italic;
  final bool code;
}

class MarkdownBlock {
  const MarkdownBlock({
    required this.kind,
    this.spans = const [],
    this.level = 0,
    this.code = '',
  });

  final MarkdownBlockKind kind;
  final List<MarkdownSpan> spans;
  final int level;
  final String code;
}

List<MarkdownBlock> parseSimpleMarkdown(String source) {
  final lines = source.replaceAll('\r\n', '\n').split('\n');
  final blocks = <MarkdownBlock>[];
  final paragraph = <String>[];
  var inCode = false;
  final code = StringBuffer();

  void flushParagraph() {
    if (paragraph.isEmpty) return;
    final text = paragraph.join('\n').trim();
    paragraph.clear();
    if (text.isEmpty) return;
    blocks.add(MarkdownBlock(
      kind: MarkdownBlockKind.paragraph,
      spans: parseMarkdownInlines(text),
    ));
  }

  for (final raw in lines) {
    final line = raw.trimRight();
    final trimmed = line.trim();
    if (trimmed.startsWith('```')) {
      if (inCode) {
        blocks.add(MarkdownBlock(
          kind: MarkdownBlockKind.code,
          code: code.toString().trimRight(),
        ));
        code.clear();
        inCode = false;
      } else {
        flushParagraph();
        inCode = true;
      }
      continue;
    }
    if (inCode) {
      if (code.isNotEmpty) code.writeln();
      code.write(raw);
      continue;
    }
    if (trimmed.isEmpty) {
      flushParagraph();
      continue;
    }
    final heading = RegExp(r'^(#{1,3})\s+(.*)$').firstMatch(trimmed);
    if (heading != null) {
      flushParagraph();
      blocks.add(MarkdownBlock(
        kind: MarkdownBlockKind.heading,
        level: heading.group(1)!.length,
        spans: parseMarkdownInlines(heading.group(2)!.trim()),
      ));
      continue;
    }
    final bullet = RegExp(r'^[-*]\s+(.*)$').firstMatch(trimmed);
    if (bullet != null) {
      flushParagraph();
      blocks.add(MarkdownBlock(
        kind: MarkdownBlockKind.bullet,
        spans: parseMarkdownInlines(bullet.group(1)!.trim()),
      ));
      continue;
    }
    final numbered = RegExp(r'^(\d+)\.\s+(.*)$').firstMatch(trimmed);
    if (numbered != null) {
      flushParagraph();
      blocks.add(MarkdownBlock(
        kind: MarkdownBlockKind.numbered,
        level: int.tryParse(numbered.group(1)!) ?? 1,
        spans: parseMarkdownInlines(numbered.group(2)!.trim()),
      ));
      continue;
    }
    paragraph.add(trimmed);
  }
  if (inCode) {
    blocks.add(MarkdownBlock(
      kind: MarkdownBlockKind.code,
      code: code.toString().trimRight(),
    ));
  }
  flushParagraph();
  return blocks;
}

List<MarkdownSpan> parseMarkdownInlines(String input) {
  final spans = <MarkdownSpan>[];
  final buffer = StringBuffer();
  var i = 0;

  void flushPlain() {
    if (buffer.isEmpty) return;
    spans.add(MarkdownSpan(buffer.toString()));
    buffer.clear();
  }

  // CommonMark-ish flanking rules (simplified): an opening `*`/`**` must be
  // followed by a non-space, a closing one must be preceded by a non-space.
  // Without them `2 * 3 * 4` renders " 3 " as italic — the model replies
  // that motivated this parser do contain bare arithmetic.
  bool isSpace(int index) =>
      index < 0 ||
      index >= input.length ||
      _whitespace.hasMatch(input[index]);

  while (i < input.length) {
    if (input.startsWith('**', i)) {
      final end = input.indexOf('**', i + 2);
      if (end > i + 2 && !isSpace(i + 2) && !isSpace(end - 1)) {
        flushPlain();
        spans.add(MarkdownSpan(input.substring(i + 2, end), bold: true));
        i = end + 2;
        continue;
      }
    }
    if (input.startsWith('`', i)) {
      final end = input.indexOf('`', i + 1);
      if (end > i + 1) {
        flushPlain();
        spans.add(MarkdownSpan(input.substring(i + 1, end), code: true));
        i = end + 1;
        continue;
      }
    }
    if (input.startsWith('*', i) && !input.startsWith('**', i)) {
      final end = input.indexOf('*', i + 1);
      if (end > i + 1 &&
          !input.startsWith('**', end) &&
          !isSpace(i + 1) &&
          !isSpace(end - 1)) {
        flushPlain();
        spans.add(MarkdownSpan(input.substring(i + 1, end), italic: true));
        i = end + 1;
        continue;
      }
    }
    buffer.write(input[i]);
    i++;
  }
  flushPlain();
  return spans;
}

final RegExp _whitespace = RegExp(r'\s');

// Project imports:
import 'package:varnamala/application/ai/textbook/knowledge_schema.dart';

/// Splits a markdown document into chapters by headings.
///
/// Mirrors `tool/gui/src/backend/markdown_chopper.py`.
class MarkdownChopper {
  const MarkdownChopper();

  /// Splits [markdown] into chapters. Prefers H1 (`# `) boundaries; if no H1
  /// headings are found, falls back to H2 (`## `). A chapter without an explicit
  /// title is named "Chapter N".
  List<TextbookChapter> splitChapters(String markdown) {
    final lines = markdown.split('\n');
    var headings = _collectHeadings(lines, 1);
    if (headings.length < 2) {
      headings = _collectHeadings(lines, 2);
    }
    if (headings.isEmpty) {
      // No headings at all — treat the whole document as one chapter.
      return [
        TextbookChapter(
          title: 'Chapter 1',
          markdown: markdown.trim(),
          slug: 'chapter-1',
        ),
      ];
    }

    final chapters = <TextbookChapter>[];
    for (var i = 0; i < headings.length; i++) {
      final start = headings[i];
      final end = i + 1 < headings.length ? headings[i + 1].line : lines.length;
      final buffer = StringBuffer();
      buffer.writeln(lines[start.line]);
      for (var j = start.line + 1; j < end; j++) {
        buffer.writeln(lines[j]);
      }
      final title = _headingTitle(lines[start.line], start.level);
      chapters.add(
        TextbookChapter(
          title: title,
          markdown: buffer.toString().trim(),
          slug: _slugify(title),
        ),
      );
    }
    return chapters;
  }

  List<_Heading> _collectHeadings(List<String> lines, int level) {
    final prefix = '#' * level + ' ';
    final headings = <_Heading>[];
    for (var i = 0; i < lines.length; i++) {
      final line = lines[i];
      if (line.startsWith(prefix) && !line.startsWith('$prefix#')) {
        headings.add(_Heading(line: i, level: level));
      }
    }
    return headings;
  }

  String _headingTitle(String line, int level) {
    final prefix = '#' * level + ' ';
    return line.startsWith(prefix) ? line.substring(prefix.length).trim() : line.trim();
  }

  String _slugify(String title) {
    final buffer = StringBuffer();
    for (var i = 0; i < title.length; i++) {
      final c = title[i];
      if (c.isWhitespace) {
        buffer.write('-');
      } else if (_isAlphanumeric(c)) {
        buffer.write(c.toLowerCase());
      }
    }
    var slug = buffer.toString();
    while (slug.contains('--')) {
      slug = slug.replaceAll('--', '-');
    }
    return slug.isEmpty ? 'chapter' : slug;
  }

  bool _isAlphanumeric(String c) =>
      (c.codeUnitAt(0) >= 48 && c.codeUnitAt(0) <= 57) ||
      (c.codeUnitAt(0) >= 65 && c.codeUnitAt(0) <= 90) ||
      (c.codeUnitAt(0) >= 97 && c.codeUnitAt(0) <= 122);
}

class _Heading {
  const _Heading({required this.line, required this.level});
  final int line;
  final int level;
}

extension _StringX on String {
  bool get isWhitespace => this == ' ' || this == '\t' || this == '\n' || this == '\r';
}

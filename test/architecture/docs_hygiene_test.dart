// Docs hygiene gate: the invariants that keep the doc tree from rotting
// again. A failure here means the documentation structure broke — not that a
// sentence is worded badly.
//
// The doc tree is split into four genres that must not mix (AGENTS.md §10):
//   behaviour spec  -> AGENTS.md
//   current status  -> docs/status.md
//   architecture    -> docs/project-guide.md
//   decision record -> docs/decisions/
//
// The failures this file exists to stop, in order of how often they happened:
//   1. an ADR number got reused, so a pointer became ambiguous;
//   2. a document was added and never indexed, so it was an orphan;
//   3. a stale fact was "corrected" by appending a correction next to it,
//      which is why live documents may not carry revocation markers;
//   4. a document was deleted and the pointer to it stayed behind;
//   5. a dated status snapshot leaked into AGENTS.md, where it silently
//      goes stale;
//   6. a sentence was cut in half, leaving an unbalanced code span behind.
//
// Scanning is done on file text, so it is intentionally cheap and has no
// dependency on the app itself.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

const _docsDir = 'docs';
const _decisionsDir = 'docs/decisions';
const _agentsFile = 'AGENTS.md';
const _docsIndex = 'docs/README.md';
const _statusFile = 'docs/status.md';

/// Live documents that must not carry a revocation marker. `docs/decisions/`
/// is included: an ADR may discuss that a clause was superseded, but it must
/// phrase it as a pointer to the newer ADR rather than keeping the old
/// conclusion with a strike-through.
const _revocationMarkers = <String>['已作废', '已撤除', '已废弃'];

/// AGENTS.md is a behaviour spec. A date there is a status snapshot, and
/// status snapshots rot: the file itself says so in §0 ("事实性数字一律现场
/// 查证，不写死在本文件"). Dates belong in docs/status.md or in git history.
final _dateStamp = RegExp(r'\b20\d{2}-\d{2}-\d{2}\b');

/// Markdown link target: `[label](target)`.
final _mdLink = RegExp(r'\]\(([^)\s]+\.md)\s*\)');

String _posix(String path) => path.replaceAll('\\', '/');

/// Resolve a markdown link target relative to the file that contains it.
/// Returns null for targets that are not local file references.
String? _resolveTarget(String containingFile, String target) {
  if (target.startsWith('http://') ||
      target.startsWith('https://') ||
      target.startsWith('mailto:') ||
      target.startsWith('#')) {
    return null;
  }
  // Strip an anchor / query suffix if present.
  var clean = target.split('#').first.split('?').first;
  if (clean.isEmpty) return null;
  if (clean.startsWith('/')) return clean;
  final base = _posix(File(containingFile).parent.path);
  final segments = <String>[if (base != '.' && base.isNotEmpty) ...base.split('/')];
  for (final segment in clean.split('/')) {
    if (segment == '.') continue;
    if (segment == '..') {
      if (segments.isNotEmpty) segments.removeLast();
      continue;
    }
    segments.add(segment);
  }
  return segments.join('/');
}

List<File> _markdownUnder(String root) {
  final dir = Directory(root);
  if (!dir.existsSync()) return const [];
  return dir
      .listSync(recursive: true)
      .whereType<File>()
      .where((f) => f.path.toLowerCase().endsWith('.md'))
      .toList()
    ..sort((a, b) => a.path.compareTo(b.path));
}

String _read(File file) => file.readAsStringSync();

void main() {
  group('docs hygiene', () {
    test('ADR numbers are unique', () {
      final seen = <String, File>{};
      final duplicates = <String>[];

      for (final file in _markdownUnder(_decisionsDir)) {
        final name = _posix(file.path).split('/').last;
        final match = RegExp(r'^(\d{4})-').firstMatch(name);
        if (match == null) {
          fail('${_posix(file.path)} does not start with a 4-digit ADR number');
        }
        final number = match.group(1)!;
        if (seen.containsKey(number)) {
          duplicates.add(
            '$number -> ${_posix(seen[number]!.path)} and ${_posix(file.path)}',
          );
        } else {
          seen[number] = file;
        }
      }

      expect(
        duplicates,
        isEmpty,
        reason: 'ADR numbers must never be reused; renumber instead:\n'
            '${duplicates.join('\n')}',
      );
    });

    test('ADR title number matches its filename', () {
      final mismatches = <String>[];

      for (final file in _markdownUnder(_decisionsDir)) {
        final name = _posix(file.path).split('/').last;
        final fromName = RegExp(r'^(\d{4})-').firstMatch(name)?.group(1);
        if (fromName == null) continue;
        final heading = RegExp(
          r'^#\s+(?:ADR\s+)?(\d{4})\b',
          multiLine: true,
        ).firstMatch(_read(file))?.group(1);
        if (heading == null) continue;
        if (heading != fromName) {
          mismatches.add('${_posix(file.path)}: title says $heading');
        }
      }

      expect(
        mismatches,
        isEmpty,
        reason: 'An ADR whose title number differs from its filename is a '
            'renumbering leftover; a reader cannot tell which record it is:\n'
            '${mismatches.join('\n')}',
      );
    });

    test('every document under docs/ is listed in docs/README.md', () {
      final index = _read(File(_docsIndex));
      final orphans = <String>[];

      for (final file in _markdownUnder(_docsDir)) {
        final rel = _posix(file.path).substring(_docsDir.length + 1);
        if (rel == 'README.md') continue;
        // The index may name the file by path or by bare filename.
        if (index.contains(rel) || index.contains(rel.split('/').last)) {
          continue;
        }
        orphans.add(rel);
      }

      expect(
        orphans,
        isEmpty,
        reason: 'These documents are not in docs/README.md:\n'
            '${orphans.join('\n')}',
      );
    });

    test('live documents carry no revocation markers', () {
      final violations = <String>[];
      final scanned = <File>[
        File(_agentsFile),
        ..._markdownUnder(_docsDir),
      ];

      for (final file in scanned) {
        if (!file.existsSync()) continue;
        final content = _read(file);
        for (final marker in _revocationMarkers) {
          if (content.contains(marker)) {
            violations.add('${_posix(file.path)} -> $marker');
          }
        }
      }

      expect(
        violations,
        isEmpty,
        reason: 'A revoked fact must be deleted, not annotated in place. '
            'Revocation history belongs in git and in the superseding ADR:\n'
            '${violations.join('\n')}',
      );
    });

    test('AGENTS.md carries no dated status snapshot', () {
      final file = File(_agentsFile);
      expect(file.existsSync(), isTrue, reason: 'AGENTS.md must exist');

      final hits = _dateStamp
          .allMatches(_read(file))
          .map((m) => m.group(0)!)
          .toSet()
          .toList()
        ..sort();

      expect(
        hits,
        isEmpty,
        reason: 'AGENTS.md is a behaviour spec; dated facts go to '
            'docs/status.md or to git history. Offending stamps: '
            '${hits.join(', ')}',
      );
    });

    test('no markdown link points at a missing file', () {
      final broken = <String>[];
      final sources = <File>[
        File(_agentsFile),
        File('README.md'),
        ..._markdownUnder(_docsDir),
      ];

      for (final source in sources) {
        if (!source.existsSync()) continue;
        final content = _read(source);
        for (final match in _mdLink.allMatches(content)) {
          final target = match.group(1)!;
          final resolved = _resolveTarget(_posix(source.path), target);
          if (resolved == null) continue;
          if (!File(resolved).existsSync()) {
            broken.add('${_posix(source.path)} -> $target');
          }
        }
      }

      expect(
        broken,
        isEmpty,
        reason: 'These links point at files that no longer exist:\n'
            '${broken.join('\n')}',
      );
    });

    test('headings are well-formed', () {
      // A heading with no text (`#` on its own) is what a section split
      // leaves behind when the heading itself is dropped. A second H1 in a
      // file is the same defect wearing a different hat: it restarts the
      // document outline in the middle of the body.
      final emptyHeadings = <String>[];
      final extraH1 = <String>[];
      final sources = <File>[
        File(_agentsFile),
        File('README.md'),
        ..._markdownUnder(_docsDir),
      ];

      for (final source in sources) {
        if (!source.existsSync()) continue;
        var h1Seen = false;
        var inFence = false;
        final lines = _read(source).split('\n');
        for (var i = 0; i < lines.length; i++) {
          final line = lines[i];
          if (line.trimLeft().startsWith('```')) {
            inFence = !inFence;
            continue;
          }
          // A `#` inside a fenced code block is a shell comment, not a heading.
          if (inFence) continue;
          final match = RegExp(r'^(#{1,6})\s*(.*)$').firstMatch(line);
          if (match == null) continue;
          final hashes = match.group(1)!;
          final text = match.group(2)!.trim();
          if (text.isEmpty) {
            emptyHeadings.add('${_posix(source.path)}:${i + 1}');
            continue;
          }
          if (hashes.length == 1) {
            if (h1Seen) {
              extraH1.add('${_posix(source.path)}:${i + 1}');
            }
            h1Seen = true;
          }
        }
      }

      expect(
        emptyHeadings,
        isEmpty,
        reason: 'Headings with no text are leftovers from a section split:\n'
            '${emptyHeadings.join('\n')}',
      );
      expect(
        extraH1,
        isEmpty,
        reason: 'Only the first H1 may be a document title:\n'
            '${extraH1.join('\n')}',
      );
    });

    test('every ADR mentioned by number still exists', () {
      // A mention of a deleted ADR is only allowed when the same line says
      // so explicitly ("（已删）"). Otherwise the reader is sent to a record
      // that cannot be opened — the failure mode that produced dead pointers
      // to ADR 0041 / 0046 after the docs cleanup removed them.
      final existing = <String>{};
      for (final file in _markdownUnder(_decisionsDir)) {
        final name = _posix(file.path).split('/').last;
        final match = RegExp(r'^(\d{4})-').firstMatch(name);
        if (match != null) existing.add(match.group(1)!);
      }

      final dangling = <String>[];
      final sources = <File>[
        File(_agentsFile),
        File('README.md'),
        ..._markdownUnder(_docsDir),
      ];

      for (final source in sources) {
        if (!source.existsSync()) continue;
        final lines = _read(source).split('\n');
        for (var i = 0; i < lines.length; i++) {
          final line = lines[i];
          final mentions = RegExp(r'\bADR\s(\d{4})\b')
              .allMatches(line)
              .map((m) => m.group(1)!)
              .toSet();
          for (final number in mentions) {
            if (existing.contains(number)) continue;
            if (line.contains('已删') ||
                line.contains('已随文档精简删除') ||
                line.contains('retired')) {
              continue;
            }
            dangling.add(
              '${_posix(source.path)}:${i + 1} -> ADR $number',
            );
          }
        }
      }

      expect(
        dangling,
        isEmpty,
        reason: 'These mention an ADR number that no longer exists. Point '
            'them at the surviving record, or mark them as removed:\n'
            '${dangling.join('\n')}',
      );
    });

    test('every markdown file named in prose still exists', () {
      // A filename in backticks that no longer resolves is a dead pointer the
      // link checker cannot see, because it is prose, not a link.
      //
      // A prose mention must resolve as a path: relative to the file that
      // mentions it, or relative to the repository root. Matching on the bare
      // filename is deliberately not allowed. "project-guide.md" pointing at
      // whichever document happens to carry that name elsewhere in the tree
      // is a pointer that rots the moment the other copy moves — which is
      // exactly how `CLAUDE.md` kept pointing at a file that had been gone
      // since 2026-09-29.
      //
      // Exempt: files explicitly out of repo, and files explicitly removed.
      const exemptMarkers = <String>[
        '不在本仓库内',
        '仓库外',
        '已删',
        '已移除',
        '已随文档精简删除',
      ];

      final dangling = <String>[];
      final sources = <File>[
        File(_agentsFile),
        File('README.md'),
        ..._markdownUnder(_docsDir),
      ];

      final namePattern = RegExp(r'`([A-Za-z0-9_\-./]+\.md)`');
      final linkSyntax = RegExp(r'\[[^\]]*\]\([^)]*\)');

      for (final source in sources) {
        if (!source.existsSync()) continue;
        final lines = _read(source).split('\n');
        for (var i = 0; i < lines.length; i++) {
          final line = lines[i];
          if (exemptMarkers.any(line.contains)) continue;
          // A markdown link is checked by its target in the link test; its
          // label is not a pointer.
          final prose = line.replaceAll(linkSyntax, '');
          for (final match in namePattern.allMatches(prose)) {
            final name = match.group(1)!;
            final relative = _resolveTarget(_posix(source.path), name);
            if (relative != null && File(relative).existsSync()) continue;
            if (File(name).existsSync()) continue;
            dangling.add('${_posix(source.path)}:${i + 1} -> $name');
          }
        }
      }

      expect(
        dangling,
        isEmpty,
        reason: 'These name a markdown file that no longer exists. Write the '
            'path relative to the mentioning file or to the repository root:\n'
            '${dangling.join('\n')}',
      );
    });

    test('no markdown file ends with an unbalanced code span', () {
      // A sentence cut in half leaves an unclosed delimiter behind. The
      // cheapest structural witness is the backtick count: a file whose
      // inline code spans do not pair up was edited mid-sentence.
      //
      // This caught real damage that every other check here missed — a
      // compressed ADR ended its line at `lib/service/secure_credential_s`,
      // and nobody noticed because the surrounding words were still English-
      // looking prose. No wording rule catches that; a delimiter count does.
      //
      // Fenced blocks are skipped: their markers are not inline code.
      final unbalanced = <String>[];

      final sources = <File>[
        File(_agentsFile),
        File('README.md'),
        ..._markdownUnder(_docsDir),
      ];

      for (final source in sources) {
        if (!source.existsSync()) continue;
        final lines = _read(source).split('\n');
        var inFence = false;
        var backticks = 0;
        for (final raw in lines) {
          final line = raw.trimRight();
          if (RegExp(r'^\s*(>\s*)*```').hasMatch(line)) {
            inFence = !inFence;
            continue;
          }
          if (inFence) continue;
          backticks += '`'.allMatches(line).length;
        }
        if (backticks.isOdd) {
          unbalanced.add('${_posix(source.path)} ($backticks backticks)');
        }
      }

      expect(
        unbalanced,
        isEmpty,
        reason: 'These files have an odd number of backticks, so an inline '
            'code span is left open — a sentence was cut in half:\n'
            '${unbalanced.join('\n')}',
      );
    });

    test('docs/status.md is the single status source and is referenced', () {
      final status = File(_statusFile);
      expect(
        status.existsSync(),
        isTrue,
        reason: 'docs/status.md is the single source of current state',
      );
      expect(
        _read(File(_agentsFile)).contains(_statusFile),
        isTrue,
        reason: 'AGENTS.md must point readers at the status source',
      );
    });
  });
}

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('dashboard and insights production readers do not parse card prefixes',
      () {
    final files = [
      'lib/application/review_dashboard/review_dashboard_repository.dart',
      'lib/application/review_progress_provider.dart',
      'lib/data/review_history_dao.dart',
    ];
    final source =
        files.map((path) => File(path).readAsStringSync()).join('\n');
    expect(source, isNot(contains('importIdFromWordId')));
    expect(source, isNot(contains("card_id LIKE 'anki-")));
    expect(source, isNot(contains("wordId.startsWith('anki-")));
    expect(source, contains('source_kind'));
    expect(source, contains('sourceId'));
  });
}

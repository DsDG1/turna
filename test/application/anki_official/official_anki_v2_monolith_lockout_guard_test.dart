import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:turna/application/anki_official/storage/official_anki_database.dart';

void main() {
  group('Official Anki v2 Monolith Lockout Guard', () {
    test('Catalog 严格仅保留 5 张核心表', () {
      final db = OfficialAnkiDatabase.memory();
      try {
        final tables = db.handle
            .select("SELECT name FROM sqlite_master WHERE type='table' AND name NOT LIKE 'sqlite_%'")
            .map((row) => row['name'] as String)
            .toSet();

        const expectedTables = {
          'anki_sources',
          'anki_source_cards',
          'anki_import_attempts',
          'anki_maintenance_jobs',
          'anki_maintenance_leases',
        };

        expect(tables, equals(expectedTables),
            reason: 'Catalog 表集合必须严格收敛至 5 张表，不得存在废弃表或悬挂表');
      } finally {
        db.close();
      }
    });

    test('禁止在源码树中重新引入已退役的 v1 类与符号', () {
      const forbiddenSymbols = [
        'OfficialAnkiProjectionProjector',
        'OfficialAnkiProjectionService',
        'OfficialAnkiProjectionStore',
        'OfficialAnkiSourceReconciler',
        'OfficialLegacySourceMigrationSaga',
        'OfficialAnkiProductionRouter',
        'OfficialAnkiMutationReceiptStore',
        'anki_projection_mappings',
        'anki_course_placement_overrides',
        'official_anki_projection_index',
        'official_anki_projection_manifest',
        'anki_scheduler_mutations',
        'legacy_pending_migrations',
      ];

      final roots = ['lib/application/anki_official', 'lib/views/anki'];
      final violations = <String>[];

      for (final root in roots) {
        final dir = Directory(root);
        if (!dir.existsSync()) continue;

        for (final file in dir.listSync(recursive: true).whereType<File>()) {
          if (!file.path.endsWith('.dart')) continue;
          final content = file.readAsStringSync();
          for (final symbol in forbiddenSymbols) {
            if (content.contains(symbol)) {
              violations.add('${file.path} 包含了已退役符号: $symbol');
            }
          }
        }
      }

      expect(violations, isEmpty,
          reason: '生产代码不得重新引入已退役的 v1 投影/对账/旧表符号:\n${violations.join('\n')}');
    });

    test('v2 导入与读取不再依赖双轨 Flag 门禁', () {
      final file = File('lib/application/anki_official/official_anki_feature_flags.dart');
      expect(file.existsSync(), isTrue);
      final text = file.readAsStringSync();
      expect(text.contains('v2ImportChain'), isFalse,
          reason: 'v2ImportChain flag 必须退役，v2 成为常驻唯一路径');
    });
  });
}

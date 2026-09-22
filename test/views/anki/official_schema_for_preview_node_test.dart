import 'package:flutter_test/flutter_test.dart';
import 'package:turna/application/anki_official/contract/official_anki_dto.dart';
import 'package:turna/views/anki/import_wizard/modern_anki_import_preview.dart';

void main() {
  OfficialAnkiProjectionSchema schema(int id, String name) {
    return OfficialAnkiProjectionSchema(
      notetypeId: id,
      name: name,
      kind: 'normal',
      fieldNames: const ['Front', 'Back'],
      templateNames: const ['Card 1'],
      schemaFingerprint: '$id',
    );
  }

  test('inspects matching schema for a named deck, not schemas.first', () {
    final schemas = [schema(1, 'Basic'), schema(2, 'Cloze')];
    expect(
      officialSchemaForPreviewNode(
        schemas: schemas,
        notetypeId: 2,
      )?.notetypeId,
      2,
    );
    expect(
      officialSchemaForPreviewNode(
        schemas: schemas,
        notetypeId: 99,
      ),
      isNull,
    );
  });
}

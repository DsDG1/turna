import 'package:turna/application/anki_official/migration/official_anki_write_owner.dart';

class OfficialAnkiAuditEvent {
  const OfficialAnkiAuditEvent({
    required this.owner,
    required this.operation,
    required this.requestId,
    required this.atMillis,
    this.sourceId,
    this.cardId,
  });

  final AnkiWriteOwner owner;
  final String operation;
  final String requestId;
  final int atMillis;
  final String? sourceId;
  final int? cardId;

  Map<String, Object?> toJson() => <String, Object?>{
        'owner': owner.name,
        'operation': operation,
        'requestId': requestId,
        'atMillis': atMillis,
        'sourceId': sourceId,
        'cardId': cardId,
      };
}

/// Main isolate only displays aggregates. Events never include card text.
class OfficialAnkiAuditLog {
  final events = <OfficialAnkiAuditEvent>[];

  void record({
    required AnkiWriteOwner owner,
    required String operation,
    required String requestId,
    int? cardId,
    String? sourceId,
    int? nowMillis,
  }) {
    events.add(
      OfficialAnkiAuditEvent(
        owner: owner,
        operation: operation,
        requestId: requestId,
        atMillis: nowMillis ?? DateTime.now().millisecondsSinceEpoch,
        sourceId: sourceId,
        cardId: cardId,
      ),
    );
  }

  Map<String, int> aggregate() {
    final counts = <String, int>{};
    for (final event in events) {
      final key = '${event.owner.name}.${event.operation}';
      counts[key] = (counts[key] ?? 0) + 1;
    }
    return counts;
  }
}

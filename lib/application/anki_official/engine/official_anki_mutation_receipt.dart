import 'package:sqlite3/sqlite3.dart';
import 'package:turna/application/anki_official/storage/official_anki_database.dart';

enum OfficialAnkiMutationReceiptState { prepared, committed, unknown }

class OfficialAnkiMutationReceipt {
  const OfficialAnkiMutationReceipt({
    required this.mutationId,
    required this.profileId,
    required this.cardId,
    required this.queueEpoch,
    required this.state,
    required this.createdAtMillis,
    required this.updatedAtMillis,
    this.rating,
  });

  final String mutationId;
  final String profileId;
  final int cardId;
  final int queueEpoch;
  final String? rating;
  final OfficialAnkiMutationReceiptState state;
  final int createdAtMillis;
  final int updatedAtMillis;

  bool get blocksCard =>
      state == OfficialAnkiMutationReceiptState.prepared ||
      state == OfficialAnkiMutationReceiptState.unknown;
}

/// Persistent at-most-once receipts. Unknown rows are never compacted away.
class OfficialAnkiMutationReceiptStore {
  OfficialAnkiMutationReceiptStore(this._database, {required this.profileId});

  final OfficialAnkiDatabase _database;
  final String profileId;
  Database get _db => _database.handle;

  static const compactionTtlMillis = 7 * 24 * 60 * 60 * 1000;

  void prepare({
    required String mutationId,
    required int cardId,
    required int queueEpoch,
    required String rating,
    required int nowMillis,
  }) {
    _db.execute(
      '''
INSERT INTO anki_scheduler_mutations (
  mutation_id, profile_id, card_id, queue_epoch, rating, state,
  created_at_millis, updated_at_millis
) VALUES (?, ?, ?, ?, ?, ?, ?, ?)
''',
      [
        mutationId,
        profileId,
        cardId,
        queueEpoch,
        rating,
        OfficialAnkiMutationReceiptState.prepared.name,
        nowMillis,
        nowMillis,
      ],
    );
  }

  void markCommitted(String mutationId, int nowMillis) {
    _setState(mutationId, OfficialAnkiMutationReceiptState.committed, nowMillis);
  }

  void markUnknown(String mutationId, int nowMillis) {
    _setState(mutationId, OfficialAnkiMutationReceiptState.unknown, nowMillis);
  }

  void _setState(
    String mutationId,
    OfficialAnkiMutationReceiptState state,
    int nowMillis,
  ) {
    _db.execute(
      'UPDATE anki_scheduler_mutations SET state = ?, updated_at_millis = ? '
      'WHERE mutation_id = ? AND profile_id = ?',
      [state.name, nowMillis, mutationId, profileId],
    );
  }

  OfficialAnkiMutationReceipt? find(String mutationId) {
    final rows = _db.select(
      'SELECT * FROM anki_scheduler_mutations '
      'WHERE mutation_id = ? AND profile_id = ?',
      [mutationId, profileId],
    );
    if (rows.isEmpty) return null;
    return _row(rows.first);
  }

  bool hasBlocking(int cardId) {
    final rows = _db.select(
      'SELECT 1 FROM anki_scheduler_mutations '
      "WHERE profile_id = ? AND card_id = ? AND state IN ('prepared','unknown') "
      'LIMIT 1',
      [profileId, cardId],
    );
    return rows.isNotEmpty;
  }

  void compact({required int nowMillis, int? ttlMillis}) {
    final ttl = ttlMillis ?? compactionTtlMillis;
    _db.execute(
      'DELETE FROM anki_scheduler_mutations '
      "WHERE profile_id = ? AND state IN ('prepared','committed') "
      'AND updated_at_millis < ?',
      [profileId, nowMillis - ttl],
    );
  }

  OfficialAnkiMutationReceipt _row(Row row) {
    return OfficialAnkiMutationReceipt(
      mutationId: row['mutation_id'] as String,
      profileId: row['profile_id'] as String,
      cardId: (row['card_id'] as num).toInt(),
      queueEpoch: (row['queue_epoch'] as num).toInt(),
      rating: row['rating'] as String?,
      state: OfficialAnkiMutationReceiptState.values.firstWhere(
        (item) => item.name == row['state'],
      ),
      createdAtMillis: (row['created_at_millis'] as num).toInt(),
      updatedAtMillis: (row['updated_at_millis'] as num).toInt(),
    );
  }
}

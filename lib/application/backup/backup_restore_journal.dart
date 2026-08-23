// Dart imports:
import 'dart:convert';

// Project imports:
import 'package:turna/service/locator.dart';

/// Application-level restore journal for SharedPreferences. SharedPreferences
/// is not a transactional store, so multi-key restores record a before-image
/// here: the journal marker is written before the first key changes and
/// removed only after every step commits. If the app dies mid-restore, the
/// next boot finds the marker and rolls the affected keys back to the
/// before-image — a half-applied backup never survives a restart.
///
/// The journal lives under the `restore.` prefs prefix, which the backup
/// manifest policy structurally excludes from ever leaving the device.
abstract final class BackupRestoreJournal {
  static const String markerKey = 'restore.inProgress';

  /// Records the before-image and arms the journal. [beforeImage] maps every
  /// prefs key the restore is about to touch to its current raw value (or
  /// null when the key does not exist yet).
  static Future<void> begin(
    AppPrefs prefs,
    String restoreId,
    Map<String, Object?> beforeImage,
  ) async {
    final payload = jsonEncode(<String, dynamic>{
      'id': restoreId,
      'startedAtUtc': DateTime.now().toUtc().toIso8601String(),
      'beforeImage': beforeImage,
    });
    await prefs.preferences.setString(markerKey, payload);
  }

  /// True when a previous restore was interrupted before committing.
  static bool hasPending(AppPrefs prefs) => prefs.preferences
      .getString(markerKey, defaultValue: '')
      .getValue()
      .isNotEmpty;

  /// Removes the journal marker. Call only after every restore step has
  /// committed successfully.
  static Future<void> commit(AppPrefs prefs) async {
    await prefs.preferences.remove(markerKey);
  }

  /// Rolls every journaled key back to its before-image and clears the
  /// marker. Keys that did not exist before the restore are removed. Safe to
  /// call repeatedly; a second call is a no-op because the marker is gone.
  static Future<bool> rollbackPending(AppPrefs prefs) async {
    final raw =
        prefs.preferences.getString(markerKey, defaultValue: '').getValue();
    if (raw.isEmpty) return false;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map<String, dynamic>) {
        final beforeImage = decoded['beforeImage'];
        if (beforeImage is Map<String, dynamic>) {
          await _applyBeforeImage(prefs, beforeImage);
        }
      }
    } catch (_) {
      // A corrupt journal cannot be rolled back precisely. Clearing it is
      // still better than retrying the rollback on every boot forever.
    }
    await prefs.preferences.remove(markerKey);
    return true;
  }

  static Future<void> _applyBeforeImage(
    AppPrefs prefs,
    Map<String, dynamic> beforeImage,
  ) async {
    for (final entry in beforeImage.entries) {
      final value = entry.value;
      if (value == null) {
        await prefs.preferences.remove(entry.key);
      } else if (value is bool) {
        await prefs.preferences.setBool(entry.key, value);
      } else if (value is int) {
        await prefs.preferences.setInt(entry.key, value);
      } else if (value is double) {
        await prefs.preferences.setDouble(entry.key, value);
      } else if (value is String) {
        await prefs.preferences.setString(entry.key, value);
      } else if (value is List) {
        await prefs.preferences.setStringList(
          entry.key,
          value.whereType<String>().toList(),
        );
      }
    }
  }
}

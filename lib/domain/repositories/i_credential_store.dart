abstract interface class ICredentialStore {
  Future<void> write(String id, String value);
  Future<String?> read(String id);
  Future<void> delete(String id);
  Future<void> deleteAll();

  /// False on session-only fallbacks such as web without a secure origin or
  /// a platform for which the native plugin is unavailable.
  bool get isPersistent;
}

/// Optional capability for stores that can *prove* persistence instead of
/// assuming it.
///
/// [ICredentialStore.isPersistent] is synchronous, so a store that has not been
/// exercised yet cannot answer honestly — before the first read/write it can
/// only guess. Guessing `true` is what made the AI settings page claim the key
/// was saved while the plug-in was missing and the key lived only in memory.
/// Implementations round-trip a sentinel value and latch the real answer.
abstract interface class IPersistentCredentialProbe {
  /// Whether values written through [write] survive a process restart.
  /// Never throws: an unusable store returns `false`.
  Future<bool> probePersistence();
}

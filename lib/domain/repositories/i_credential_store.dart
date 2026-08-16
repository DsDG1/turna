abstract interface class ICredentialStore {
  Future<void> write(String id, String value);
  Future<String?> read(String id);
  Future<void> delete(String id);
  Future<void> deleteAll();

  /// False on session-only fallbacks such as web without a secure origin or
  /// a platform for which the native plugin is unavailable.
  bool get isPersistent;
}

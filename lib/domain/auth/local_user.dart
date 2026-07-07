/// Local user model for offline mode.
///
/// Replaces the Firebase-shaped [SerializableFirebaseUser]. The shape is kept
/// identical so that widgets using [PreferenceBuilder] continue to compile
/// without changes. There is no remote source of truth — a default
/// [LocalUser.local] instance is seeded on first launch.
class SerializableFirebaseUser {
  final String? uid;
  final String? email;
  final String? displayName;
  final String? photoUrl;

  const SerializableFirebaseUser({
    required this.uid,
    required this.email,
    required this.displayName,
    required this.photoUrl,
  });

  /// Default user for offline mode. No login required.
  static const SerializableFirebaseUser local = SerializableFirebaseUser(
    uid: 'local',
    email: '',
    displayName: 'Learner',
    photoUrl: '',
  );

  // Convert SerializableFirebaseUser to JSON
  Map<String, dynamic> toJson() {
    return {
      'uid': uid,
      'email': email,
      'displayName': displayName,
      'photoUrl': photoUrl,
    };
  }

  // Convert JSON back to SerializableFirebaseUser
  factory SerializableFirebaseUser.fromJson(Map<String, dynamic> json) {
    return SerializableFirebaseUser(
      uid: json['uid'] as String?,
      email: json['email'] as String?,
      displayName: json['displayName'] as String?,
      photoUrl: json['photoUrl'] as String?,
    );
  }
}

/// Backwards-compatible alias for callers that prefer the new name.
typedef LocalUser = SerializableFirebaseUser;
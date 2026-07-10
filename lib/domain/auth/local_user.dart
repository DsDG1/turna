/// Local offline user model. No remote auth — a default [LocalUser.local]
/// instance is seeded on first launch and stored in prefs.
class LocalUser {
  final String? uid;
  final String? email;
  final String? displayName;
  final String? photoUrl;

  const LocalUser({
    required this.uid,
    required this.email,
    required this.displayName,
    required this.photoUrl,
  });

  /// Default user for offline mode. No login required.
  static const LocalUser local = LocalUser(
    uid: 'local',
    email: '',
    displayName: 'Learner',
    photoUrl: '',
  );

  Map<String, dynamic> toJson() {
    return {
      'uid': uid,
      'email': email,
      'displayName': displayName,
      'photoUrl': photoUrl,
    };
  }

  factory LocalUser.fromJson(Map<String, dynamic> json) {
    return LocalUser(
      uid: json['uid'] as String?,
      email: json['email'] as String?,
      displayName: json['displayName'] as String?,
      photoUrl: json['photoUrl'] as String?,
    );
  }
}

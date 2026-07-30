/// Local offline user model. No remote auth — a default [LocalUser.local]
/// instance is seeded on first launch and stored in prefs.
class LocalUser {
  final String? uid;
  final String? email;
  final String? displayName;
  final String? photoUrl;

  /// Personal motto / bio shown below the display name.
  final String? bio;

  /// Index into a preset avatar color palette (0-7). Null = default (teal).
  final int? avatarColorIndex;

  /// Daily XP goal (default 100).
  final int? dailyXpGoal;

  /// Daily study time goal in minutes (default 30).
  final int? dailyStudyMinutesGoal;

  /// Daily lesson completion goal (default 5).
  final int? dailyLessonGoal;

  const LocalUser({
    required this.uid,
    required this.email,
    required this.displayName,
    required this.photoUrl,
    this.bio,
    this.avatarColorIndex,
    this.dailyXpGoal,
    this.dailyStudyMinutesGoal,
    this.dailyLessonGoal,
  });

  /// Default user for offline mode. No login required.
  static const LocalUser local = LocalUser(
    uid: 'local',
    email: '',
    displayName: 'Learner',
    photoUrl: '',
    bio: null,
    avatarColorIndex: null,
    dailyXpGoal: 100,
    dailyStudyMinutesGoal: 30,
    dailyLessonGoal: 5,
  );

  Map<String, dynamic> toJson() {
    return {
      'uid': uid,
      'email': email,
      'displayName': displayName,
      'photoUrl': photoUrl,
      'bio': bio,
      'avatarColorIndex': avatarColorIndex,
      'dailyXpGoal': dailyXpGoal,
      'dailyStudyMinutesGoal': dailyStudyMinutesGoal,
      'dailyLessonGoal': dailyLessonGoal,
    };
  }

  factory LocalUser.fromJson(Map<String, dynamic> json) {
    return LocalUser(
      uid: json['uid'] as String?,
      email: json['email'] as String?,
      displayName: json['displayName'] as String?,
      photoUrl: json['photoUrl'] as String?,
      bio: json['bio'] as String?,
      avatarColorIndex: json['avatarColorIndex'] as int?,
      dailyXpGoal: json['dailyXpGoal'] as int?,
      dailyStudyMinutesGoal: json['dailyStudyMinutesGoal'] as int?,
      dailyLessonGoal: json['dailyLessonGoal'] as int?,
    );
  }

  /// Returns a copy with the given fields replaced.
  LocalUser copyWith({
    String? uid,
    String? email,
    String? displayName,
    String? photoUrl,
    String? bio,
    int? avatarColorIndex,
    int? dailyXpGoal,
    int? dailyStudyMinutesGoal,
    int? dailyLessonGoal,
  }) {
    return LocalUser(
      uid: uid ?? this.uid,
      email: email ?? this.email,
      displayName: displayName ?? this.displayName,
      photoUrl: photoUrl ?? this.photoUrl,
      bio: bio ?? this.bio,
      avatarColorIndex: avatarColorIndex ?? this.avatarColorIndex,
      dailyXpGoal: dailyXpGoal ?? this.dailyXpGoal,
      dailyStudyMinutesGoal: dailyStudyMinutesGoal ?? this.dailyStudyMinutesGoal,
      dailyLessonGoal: dailyLessonGoal ?? this.dailyLessonGoal,
    );
  }
}

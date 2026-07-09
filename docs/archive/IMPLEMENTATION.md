# Gamification Implementation Plan

## Current State

| Feature | Status | What Exists |
|---------|--------|-------------|
| **XP (Score)** | ✅ Partial | `GameProvider.incrementScore()`, stored in Firestore `users/{uid}/score` |
| **Streaks** | ✅ Partial | `getUserStreakStream()`, `lastStreakDate` tracking, auto-increment on consecutive days |
| **Leaderboard** | ✅ Basic | Top 30 users by total XP, no league filtering |
| **Shop UI** | ✅ UI Only | Streak freeze, power-ups, outfits displayed, **no purchase logic** |
| **Hearts** | ❌ None | Not implemented |
| **Gems** | ❌ None | Not implemented |
| **Leagues** | ❌ None | Not implemented |
| **Achievements** | ❌ None | Not implemented |

---

## Firestore Schema Extension

```
users/{userId}/
├── score: int              // ✅ EXISTS - Total XP
├── streak: int             // ✅ EXISTS
├── lastStreakDate: string  // ✅ EXISTS
├── name, email, profileImage, languages  // ✅ EXISTS
│
├── gems: int               // 🆕 ADD - Currency
├── hearts: int             // 🆕 ADD - Lives (max 5)
├── heartsRefillAt: timestamp  // 🆕 ADD - Next heart refill time
├── streakFreezes: int      // 🆕 ADD - Owned streak freezes (max 2)
├── streakFreezeActive: bool   // 🆕 ADD - Is freeze equipped today?
│
├── league: string          // 🆕 ADD - 'bronze'|'silver'|'gold'|'amethyst'|'pearl'|'ruby'|'emerald'|'diamond'
├── leagueXp: int           // 🆕 ADD - XP earned this week (resets Sunday)
├── leagueJoinedAt: timestamp  // 🆕 ADD - When joined current league
│
└── achievements: array<string>  // 🆕 ADD - ['first_lesson', 'streak_7', ...]

leagues/{leagueId}/
├── name: string            // 'Diamond League'
├── tier: int               // 1-8
├── weekStart: timestamp    // Current week start
└── participants: subcollection  // Cache of top 50 this week
```

---

## Plan 1: XP System Enhancement

### Changes to `GameProvider`

```dart
// XP earning events with multipliers
enum XPEvent {
  lessonComplete(base: 10),
  perfectLesson(base: 15),      // No mistakes
  dailyGoalComplete(base: 20),
  streakBonus(base: 5),         // Per streak day (capped)
  challengeWin(base: 25);
  
  final int base;
  const XPEvent({required this.base});
}

// New method
Future<void> awardXP(XPEvent event, {double multiplier = 1.0}) async {
  final xp = (event.base * multiplier).round();
  await incrementScore(xp);
  await _updateLeagueXp(xp);  // NEW: Also update weekly league XP
  await _checkXPAchievements(); // NEW: Check milestone achievements
}
```

### Daily XP Goal
```dart
// Add to user document
'dailyXpGoal': 50,        // Configurable
'dailyXpEarned': 0,       // Reset at midnight
'lastDailyReset': timestamp
```

---

## Plan 2: Hearts/Lives System

### New Provider: `HeartsProvider`

```dart
@injectable
class HeartsProvider extends ChangeNotifier {
  static const int maxHearts = 5;
  static const Duration refillInterval = Duration(minutes: 30);
  
  Stream<HeartsState> getHeartsStream();
  
  Future<void> loseHeart() async {
    // Decrement hearts
    // If hearts < max and no refill timer, start timer
    // Update Firestore
  }
  
  Future<void> refillHeart() async {
    // Called by timer or on app resume
    // Check if enough time passed
    // Increment hearts (max 5)
  }
  
  Future<bool> useGemsForHearts(int gems) async {
    // Cost: 350 gems for full refill
    // Deduct gems, set hearts to 5
  }
}
```

### Integration Points
- Lesson start: Check `hearts > 0` or show "Out of hearts" modal
- Wrong answer: Call `loseHeart()`
- Show heart count + timer in app bar

---

## Plan 3: Gems/Currency System

### New Provider: `GemsProvider`

```dart
@injectable
class GemsProvider extends ChangeNotifier {
  Stream<int> getGemsStream();
  
  Future<void> earnGems(GemEvent event) async {
    // Add gems to user
    // Show celebration animation
  }
  
  Future<bool> spendGems(GemPurchase purchase) async {
    // Check sufficient balance
    // Deduct gems
    // Apply purchase effect
    return success;
  }
}

enum GemEvent {
  lessonComplete(5),
  perfectLesson(10),
  streakMilestone7(50),
  streakMilestone30(200),
  streakMilestone100(500),
  achievementUnlock(25),
  leaguePromotion(100);
}

enum GemPurchase {
  streakFreeze(200),
  heartRefill(350),
  doubleXp(100);      // 30 min boost
}
```

### Shop Integration
- Update `ShopPage` to read user's gem balance
- Add purchase buttons with `spendGems()` calls
- Show success/failure feedback

---

## Plan 4: Streak System Enhancement

### Changes to `GameProvider`

```dart
Future<void> checkStreakOnAppOpen() async {
  final user = await getUserDoc();
  final lastDate = user['lastStreakDate'];
  final daysMissed = calculateDaysMissed(lastDate);
  
  if (daysMissed == 1 && user['streakFreezeActive']) {
    // Streak freeze saved the day
    await _consumeStreakFreeze();
  } else if (daysMissed == 1 && user['streakFreezes'] > 0) {
    // Auto-apply streak freeze
    await _applyStreakFreeze();
  } else if (daysMissed > 1) {
    // Streak lost
    await _resetStreak();
    // Offer streak repair for gems?
  }
}

Future<void> purchaseStreakFreeze() async {
  // Cost: 200 gems
  // Max 2 owned
}

// Milestone rewards
void _checkStreakMilestones(int streak) {
  if (streak == 7) earnGems(GemEvent.streakMilestone7);
  if (streak == 30) earnGems(GemEvent.streakMilestone30);
  if (streak == 100) earnGems(GemEvent.streakMilestone100);
  // Also unlock achievements
}
```

---

## Plan 5: Leagues System

### New Provider: `LeagueProvider`

```dart
@injectable
class LeagueProvider extends ChangeNotifier {
  static const leagues = [
    'bronze', 'silver', 'gold', 'amethyst', 
    'pearl', 'ruby', 'emerald', 'diamond'
  ];
  
  Stream<LeagueState> getLeagueStream();
  
  Stream<List<LeaderboardEntry>> getLeagueLeaderboard(String league) {
    return _firestore
      .collection('users')
      .where('league', isEqualTo: league)
      .orderBy('leagueXp', descending: true)
      .limit(30)
      .snapshots();
  }
  
  // Called weekly by Cloud Function
  // Top 10 → promote
  // Bottom 5 → demote
  // Everyone's leagueXp → 0
}
```

### Cloud Function (Weekly)
```javascript
exports.weeklyLeagueUpdate = functions.pubsub
  .schedule('every sunday 23:59')
  .timeZone('Asia/Kolkata')
  .onRun(async (context) => {
    for (const league of leagues) {
      const users = await getLeagueUsers(league);
      const sorted = sortByLeagueXp(users);
      
      // Promote top 10
      await promoteUsers(sorted.slice(0, 10));
      
      // Demote bottom 5 (if not bronze)
      if (league !== 'bronze') {
        await demoteUsers(sorted.slice(-5));
      }
      
      // Reset all leagueXp
      await resetLeagueXp(users);
    }
  });
```

### UI Changes
- Update `LeaderboardPage` to show league tabs
- Add league badge/icon next to user names
- Show promotion/demotion zone indicators

---

## Plan 6: Achievements System

### New Provider: `AchievementsProvider`

```dart
@injectable
class AchievementsProvider extends ChangeNotifier {
  static final allAchievements = [
    // Lesson milestones
    Achievement('first_lesson', 'First Steps', 'Complete your first lesson', 10),
    Achievement('lessons_10', 'Getting Started', 'Complete 10 lessons', 25),
    Achievement('lessons_50', 'Dedicated Learner', 'Complete 50 lessons', 50),
    Achievement('lessons_100', 'Century', 'Complete 100 lessons', 100),
    
    // Streak milestones
    Achievement('streak_3', 'On a Roll', '3-day streak', 15),
    Achievement('streak_7', 'Week Warrior', '7-day streak', 50),
    Achievement('streak_30', 'Monthly Master', '30-day streak', 200),
    Achievement('streak_100', 'Unstoppable', '100-day streak', 500),
    Achievement('streak_365', 'Year of Learning', '365-day streak', 1000),
    
    // XP milestones
    Achievement('xp_1000', 'XP Explorer', 'Earn 1,000 XP', 25),
    Achievement('xp_10000', 'XP Champion', 'Earn 10,000 XP', 100),
    Achievement('xp_50000', 'XP Legend', 'Earn 50,000 XP', 250),
    
    // Perfect lessons
    Achievement('perfect_1', 'Flawless', 'Complete a lesson with no mistakes', 10),
    Achievement('perfect_10', 'Perfectionist', '10 perfect lessons', 50),
    
    // League achievements
    Achievement('league_silver', 'Rising Star', 'Reach Silver league', 25),
    Achievement('league_gold', 'Golden Touch', 'Reach Gold league', 50),
    Achievement('league_diamond', 'Diamond Elite', 'Reach Diamond league', 200),
    
    // Language achievements
    Achievement('learn_2_langs', 'Bilingual', 'Study 2 languages', 50),
    Achievement('learn_4_langs', 'Polyglot', 'Study all 4 languages', 200),
  ];
  
  Stream<List<String>> getUnlockedAchievements();
  
  Future<void> checkAndUnlock(String achievementId) async {
    if (!isUnlocked(achievementId)) {
      await _unlockAchievement(achievementId);
      await _awardGems(achievement.gems);
      // Show celebration modal
    }
  }
}
```

### Integration Points
- After lesson complete → check lesson/perfect achievements
- After XP award → check XP milestones
- After streak update → check streak milestones
- After league change → check league achievements

---

## Implementation Priority

| Phase | Features | Effort |
|-------|----------|--------|
| **Phase 1** | Gems + Shop purchases | 2 days |
| **Phase 2** | Hearts system | 2 days |
| **Phase 3** | Streak freeze (functional) | 1 day |
| **Phase 4** | Achievements | 3 days |
| **Phase 5** | Leagues + Cloud Function | 4 days |
| **Phase 6** | Push notifications | 2 days |

---

## Files to Create/Modify

```
lib/
├── application/
│   ├── game_provider.dart      # MODIFY - Add XP events, streak freeze
│   ├── gems_provider.dart      # CREATE
│   ├── hearts_provider.dart    # CREATE
│   ├── league_provider.dart    # CREATE
│   └── achievements_provider.dart  # CREATE
├── domain/
│   ├── achievement.dart        # CREATE - Freezed model
│   └── league.dart             # CREATE - Freezed model
├── views/
│   ├── leaderboard/
│   │   └── leaderboard_page.dart  # MODIFY - Add league tabs
│   ├── shop/
│   │   └── shop_screen.dart    # MODIFY - Add purchase logic
│   └── widgets/
│       ├── hearts_display.dart # CREATE
│       └── gems_display.dart   # CREATE
functions/
└── index.js                    # CREATE - Weekly league update
```

---

## Firebase Security Rules Update

```javascript
rules_version = '2';
service cloud.firestore {
  match /databases/{database}/documents {
    match /users/{userId} {
      // Users can read/write their own data
      allow read, write: if request.auth != null && request.auth.uid == userId;
      
      // Validate gems can't go negative
      allow update: if request.resource.data.gems >= 0;
      
      // Validate hearts 0-5
      allow update: if request.resource.data.hearts >= 0 
                    && request.resource.data.hearts <= 5;
      
      // Validate streak freezes 0-2
      allow update: if request.resource.data.streakFreezes >= 0 
                    && request.resource.data.streakFreezes <= 2;
    }
    
    // All authenticated users can read leaderboard
    match /users/{userId} {
      allow read: if request.auth != null;
    }
    
    // Leagues collection - read only for users
    match /leagues/{leagueId} {
      allow read: if request.auth != null;
      allow write: if false; // Only Cloud Functions
    }
  }
}
```

---

## Testing Checklist

### XP System
- [ ] XP awarded on lesson complete
- [ ] XP multiplier works (double XP)
- [ ] Daily XP goal tracking
- [ ] League XP updates separately

### Hearts
- [ ] Heart lost on wrong answer
- [ ] Timer starts when hearts < 5
- [ ] Heart refills after 30 min
- [ ] Gem purchase refills all hearts
- [ ] Lesson blocked when hearts = 0

### Gems
- [ ] Gems earned on lesson complete
- [ ] Gems earned on achievements
- [ ] Shop purchase deducts gems
- [ ] Cannot go negative

### Streaks
- [ ] Streak increments on consecutive days
- [ ] Streak freeze prevents loss
- [ ] Streak resets after missing days
- [ ] Milestone rewards awarded

### Leagues
- [ ] Users placed in correct league
- [ ] Weekly XP tracked separately
- [ ] Promotion on Sunday
- [ ] Demotion on Sunday
- [ ] XP reset after cycle

### Achievements
- [ ] First lesson achievement
- [ ] Streak milestones
- [ ] XP milestones
- [ ] League achievements
- [ ] Gem rewards on unlock

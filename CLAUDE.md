# Varnamala - Duolingo-Style Language Learning App

## Project Overview

**Varnamala** is a Flutter-based language learning app inspired by Duolingo. Originally focused on Indian languages (Kannada, Tamil, Telugu, Malayalam), the app is currently repositioning around **Swahili** as the primary target language while keeping the existing Kannada course data as a temporary placeholder. The app uses Firebase for backend services and follows a clean architecture pattern.

For the long-term scaling vision (11,000 lessons, sub-lessons, listening phases, SRS, mistake tracking, external CMS), see [`dreamplan.md`](./dreamplan.md).

---

## Architecture

### Layer Structure
```
lib/
├── application/       # State management (Providers)
│   ├── srs_provider.dart        # SM-2 spaced repetition
│   ├── mistake_provider.dart    # FIFO mistake log
│   └── ...
├── core/              # Enums, extensions, utilities
├── courses/           # Language course data
│   ├── alphabets/     # Alphabet learning content
│   ├── course_loader.dart
│   ├── course_validator.dart
│   └── languages/     # Language-specific course files
├── di/                # Dependency injection (GetIt + Injectable)
├── domain/            # Domain models (Course, User, etc.)
│   └── course/        # section, unit, lesson, stage, interaction,
│                      # sub_lesson, listening_phase, expression,
│                      # grammar_point, reading_passage, srs_word, mistake_entry
├── routing/           # Auto Route configuration
├── service/           # App services (Preferences, locator)
└── views/             # UI layer organized by feature
    ├── courses/       # Course tree
    ├── home/          # Bottom navigation / home shell
    ├── lesson/        # Lesson player + interaction renderers
    ├── play/          # Play hub (Match Madness, SRS Review, Mistakes)
    ├── profile/       # User profile
    ├── review/        # SRS review + mistake list
    ├── theme.dart       # VarnamalaTheme: light/dark ThemeData + semantic color helpers
```

### Key Patterns
- **State Management**: Provider + ChangeNotifier
- **Dependency Injection**: GetIt with Injectable annotations
- **Routing**: Auto Route with code generation
- **Models**: Freezed for immutable data classes with JSON serialization

---

## Firebase Services

| Service | Purpose | Status |
|---------|---------|--------|
| **Authentication** | Google Sign-In, user management | ✅ Implemented |
| **Firestore** | User data, scores, leaderboards | ✅ Implemented |
| **Analytics** | User behavior tracking | ✅ Implemented |
| **Crashlytics** | Error reporting | ✅ Implemented |
| **Messaging** | Push notifications | 🔧 Setup Done |
| **Storage** | Asset storage | 🔧 Setup Done |

### Firestore Collections
```
users/
├── {userId}/
│   ├── name: string
│   ├── email: string
│   ├── profileImage: string
│   ├── score: number (XP)
│   ├── streak: number
│   ├── lastStreakDate: timestamp
│   └── languages: array<string>
```

---

## Duolingo Features - Implementation Status

### ✅ Currently Implemented
- [x] Google Authentication
- [x] Course tree with progressive levels
- [x] Multiple choice questions
- [x] Translation exercises  
- [x] Fill-in-the-blank
- [x] Listening exercises (ListenAndPick / TypeTheWord using TTS)
- [x] Reading exercises (ReadingMCQ / ReadingTrueFalse / ReadingShortAnswer)
- [x] XP scoring system
- [x] Basic streak tracking
- [x] Leaderboard (top 30 users)
- [x] SRS engine (SM-2) + review UI
- [x] Mistake tracking with FIFO log + review list
- [x] Match Madness word-matching mini-game
- [x] Shop UI (streak freeze, power-ups, outfits)
- [x] Multi-language support (Kannada content presented as Swahili for now)
- [x] Content model extended for sub-lessons, listening phases, expressions, grammar points, reading passages
- [x] **Dark Mode** — full light/dark/system theme support with persistent preference, semantic color helpers, and theme-aware widget backgrounds
- [x] **Learning Statistics Dashboard** — daily/weekly XP trends, study time tracking, accuracy metrics, weak-word analysis (Profile page)

### 🔴 Features Needed (Firebase-Based)

#### Gamification System
- [ ] **Leagues/Tiers** - Amethyst, Pearl, Ruby, Emerald, Diamond, etc.
  - Weekly league progression
  - Top 10 promotion, bottom 5 demotion
  - League-specific leaderboards
  
- [ ] **XP System Enhancement**
  - XP boost multipliers
  - Daily XP goals
  - XP for completing lessons, streaks, challenges

- [ ] **Streak System**
  - Streak freeze purchase/activation
  - Weekend amulet
  - Streak repair with gems
  - Streak milestone rewards (7, 30, 100, 365 days)

- [ ] **Hearts/Lives System**
  - Limited hearts for mistakes
  - Heart refill timers
  - Unlimited hearts (premium)

- [ ] **Gems/Lingots Currency**
  - Earn from achievements
  - Purchase power-ups
  - Streak freezes

#### Notifications & Reminders
- [ ] **Daily Practice Reminders**
  - Customizable reminder times
  - Smart notifications based on user patterns
  - Streak-at-risk warnings

- [ ] **Push Notification Types**
  - Lesson reminders
  - Streak maintenance
  - Friend activity
  - Achievement unlocks
  - League updates

#### Social Features
- [ ] **Friends System**
  - Add friends by username/email
  - Friend activity feed
  - Challenge friends

- [ ] **Achievements/Badges**
  - Lesson milestones
  - Streak achievements
  - Social achievements
  - Language-specific badges

#### Course Features
- [ ] **Skill Levels**
  - Crown levels (0-5 per skill)
  - Legendary skill unlock
  - Skill degradation over time

- [ ] **Learning Modes**
  - Stories mode
  - Speaking exercises (using flutter_tts)
  - Listening exercises (model done, dedicated phase renderer pending)
  - Fill-in-the-blank
  - Word matching (Match Madness implemented)

- [ ] **Content Management**
  - External GUI editor for non-technical authors
  - Per-section JSON or SQLite backend
  - Cloud sync and content versioning

- [ ] **Grammar & Expressions**
  - Grammar-point review queue
  - Expression-level SRS
  - Word/expression origin tracking (LessonWordLink)
---

## UI Theming Guidelines

### VarnamalaTheme (lib/views/theme.dart)

The app uses a single `VarnamalaTheme` class that provides both `lightTheme` and `darkTheme` `ThemeData` getters, plus a suite of **semantic color helpers** that adapt to the current `Brightness` via `BuildContext`:

```dart
// Theme-aware helpers — use these instead of hard-coded Colors.white
static Color cardBg(BuildContext context)
static Color scaffoldBg(BuildContext context)
static Color dividerBg(BuildContext context)
static Color textHintColor(BuildContext context)
static Color inputFillColor(BuildContext context)
static Color statCardBorder(BuildContext context)
static Color bottomNavBg(BuildContext context)
static Color streakChipBg(BuildContext context)
static Color scoreChipBg(BuildContext context)
// ... and more
```

### Color Palette (Peacock-inspired, distinct from Duolingo)

```dart
// Primary: Teal/Cyan
const primaryColor = Color(0xFF1F727E);
const primaryLight = Color(0xFF359CBB);
const primaryDark = Color(0xFF145A64);

// Accent / Secondary
const secondary = Color(0xFF46D1BF);
const secondaryLight = Color(0xFF00FFC6);

// Semantic
const error = Color(0xFFE74C3C);
const success = Color(0xFFFFD93D);
const warning = Color(0xFFFF9F43);

// League Colors (Jewel Tones)
const amethystLeague = Color(0xFF9B59B6);
const pearlLeague = Color(0xFFF5F5F5);
const rubyLeague = Color(0xFFE74C3C);
const emeraldLeague = Color(0xFF27AE60);
const diamondLeague = Color(0xFF3498DB);
```

### Theme Switching

- `ThemeProvider` (ChangeNotifier) manages `ThemeMode.light / dark / system`
- Preference persisted to `StreamingSharedPreferences` (`settings.themeMode`)
- `PlatformDispatcher.platformBrightness` used when `system` mode is active
- Toggle available in Profile page (AccountWidget popup menu)
- `MaterialApp.router` receives both `theme` and `darkTheme`

---

## Course Data Structure

### Question Types
```dart
enum QuestionType {
  multipleChoice,    // Choose correct translation
  translate,         // Translate sentence
  fillBlank,         // Complete the sentence (TODO)
  matchWords,        // Match pairs (partially implemented)
  listening,         // Listen and select (TODO)
  speaking,          // Speak the phrase (TODO)
}
```

### Course Format (in lib/courses/languages/)
```dart
{
  "courseName": "basics",
  "image": "assets/images/course_icon.png",
  "color": 0xff2b70c9,
  "levels": [
    {
      "level": 1,
      "questions": [
        {
          "type": "multiple_choice",
          "prompt": "Choose an appropriate response",
          "sentence": "Ninna hesaru enu?",
          "sentenceIsTargetLanguage": true,
          "options": ["Option A", "Option B", "Option C"],
          "correctAnswer": "Option A",
          "translatedSentence": "What is your name?"
        }
      ]
    }
  ]
}
```

---

## Development Commands

```bash
# Install dependencies
flutter pub get

# Generate code (routes, freezed, json_serializable)
flutter pub run build_runner build --delete-conflicting-outputs

# Run app
flutter run

# Run on specific device
flutter run -d chrome
flutter run -d ios
flutter run -d android

# Clean build
flutter clean && flutter pub get && flutter pub run build_runner build --delete-conflicting-outputs
```

---

## Key Files Reference

| File | Purpose |
|------|---------|
| `lib/main.dart` | App entry point, Firebase init |
| `lib/views/app.dart` | Root widget with providers |
| `lib/routing/routing.dart` | Auto Route configuration |
| `lib/di/injection.dart` | GetIt DI setup |
| `lib/service/locator.dart` | AppPrefs, preferences, TTS setup |
| `lib/application/game_provider.dart` | Score/streak logic |
| `lib/application/srs_provider.dart` | SM-2 spaced repetition |
| `lib/application/mistake_provider.dart` | FIFO mistake log |
| `lib/application/lesson_viewmodel.dart` | Lesson flow + SRS/mistake registration |
| `lib/domain/course/lesson.dart` | Lesson model + LessonTemplate |
| `lib/domain/course/lesson_content.dart` | Lesson content (stages/subLessons/listeningPhases/readingPassage) |
| `lib/views/play/play_hub_screen.dart` | Play hub (Match Madness, SRS Review, Mistakes) |
| `lib/views/review/srs_review_screen.dart` | SRS flashcard review |
| `lib/views/review/mistake_list_page.dart` | Mistake list |
| `lib/views/theme.dart` | VarnamalaTheme: light/dark ThemeData + semantic color helpers |
| `lib/application/study_stats_provider.dart` | Learning statistics aggregation and recording |
| `lib/domain/study/study_log.dart` | Study activity event model |
| `lib/domain/study/daily_stats.dart` | Daily/weekly aggregated study statistics |
| `lib/data/study_log_repository.dart` | Study log persistence (prefs-backed, 90-day retention) |
| `lib/views/profile/widgets/learning_stats.dart` | Profile page learning statistics dashboard UI |
| `dreamplan.md` | Long-term scaling vision and feasibility analysis |

---

## Firebase Security Rules (Recommended)

```javascript
rules_version = '2';
service cloud.firestore {
  match /databases/{database}/documents {
    // Users can only read/write their own data
    match /users/{userId} {
      allow read, write: if request.auth != null && request.auth.uid == userId;
    }
    
    // Leaderboard - all authenticated users can read
    match /users/{userId} {
      allow read: if request.auth != null;
    }
    
    // Leagues collection
    match /leagues/{leagueId} {
      allow read: if request.auth != null;
      allow write: if false; // Only cloud functions
    }
  }
}
```

---

## Agents Available

### Flutter/Firebase Expert
Location: `.claude/agents/FLUTTER_FIREBASE_EXPERT.md`
- Architecture guidance
- Firebase implementation
- State management patterns
- Performance optimization

### Course Generator Agent
Location: `.claude/agents/COURSE_GENERATOR_AGENT.md`
- Generate new language courses
- Create question sets
- Validate course structure
- Subject matter expertise for languages

---

## Contributing

1. Follow existing code patterns
2. Run `build_runner` after model changes
3. Test on both iOS and Android
4. Ensure Firebase rules are considered
5. Use the theming guidelines for UI consistency


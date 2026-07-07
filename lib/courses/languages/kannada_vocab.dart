// Project imports:
import 'package:words625/domain/course/word_entry.dart';

/// Curated Kannada vocabulary for the SRS word pool.
/// Words are grouped by thematic unit and registered into [SrsProvider]
/// when the user first encounters a lesson that references them.
const List<WordEntry> kannadaVocabulary = [
  // Section 1 — Foundations
  WordEntry(id: 'w-naanu', term: 'Naanu', translation: 'I', tags: ['pronoun']),
  WordEntry(id: 'w-neenu', term: 'Neenu', translation: 'You', tags: ['pronoun']),
  WordEntry(id: 'w-naavu', term: 'Naavu', translation: 'We', tags: ['pronoun']),
  WordEntry(id: 'w-howdu', term: 'Howdu', translation: 'Yes', tags: ['greeting']),
  WordEntry(id: 'w-illa', term: 'Illa', translation: 'No', tags: ['greeting']),
  WordEntry(id: 'w-baa', term: 'Baa', translation: 'Come', tags: ['verb']),
  WordEntry(id: 'w-hogu', term: 'Hogu', translation: 'Go', tags: ['verb']),
  WordEntry(id: 'w-hesaru', term: 'Hesaru', translation: 'Name', tags: ['noun']),
  WordEntry(id: 'w-vidyaarthi', term: 'Vidyaarthi', translation: 'Student', tags: ['noun']),
  WordEntry(id: 'w-oota', term: 'Oota', translation: 'Food / Eating', tags: ['noun', 'verb']),

  // Section 2 — Daily Life
  WordEntry(id: 'w-naayi', term: 'Naayi', translation: 'Dog', tags: ['animal']),
  WordEntry(id: 'w-koli', term: 'Koli', translation: 'Cat', tags: ['animal']),
  WordEntry(id: 'w-aane', term: 'Aane', translation: 'Elephant', tags: ['animal']),
  WordEntry(id: 'w-bekku', term: 'Bekku', translation: 'Cat (colloquial)', tags: ['animal']),
  WordEntry(id: 'w-kempu', term: 'Kempu', translation: 'Red', tags: ['color']),
  WordEntry(id: 'w-bili', term: 'Bili', translation: 'White', tags: ['color']),
  WordEntry(id: 'w-kappu', term: 'Kappu', translation: 'Black', tags: ['color']),
  WordEntry(id: 'w-hasiru', term: 'Hasiru', translation: 'Green', tags: ['color']),
  WordEntry(id: 'w-ondu', term: 'Ondu', translation: 'One', tags: ['number']),
  WordEntry(id: 'w-eradu', term: 'Eradu', translation: 'Two', tags: ['number']),
  WordEntry(id: 'w-mooru', term: 'Mooru', translation: 'Three', tags: ['number']),
  WordEntry(id: 'w-naaku', term: 'Naaku', translation: 'Four', tags: ['number']),
  WordEntry(id: 'w-aidhu', term: 'Aidhu', translation: 'Five', tags: ['number']),

  // Section 3 — World Around
  WordEntry(id: 'w-santosha', term: 'Santosha', translation: 'Happy', tags: ['emotion']),
  WordEntry(id: 'w-dukha', term: 'Dukha', translation: 'Sad', tags: ['emotion']),
  WordEntry(id: 'w-kopam', term: 'Kopam', translation: 'Anger', tags: ['emotion']),
  WordEntry(id: 'w-bhayav', term: 'Bayav', translation: 'Fear', tags: ['emotion']),
  WordEntry(id: 'w-mara', term: 'Mara', translation: 'Tree', tags: ['nature']),
  WordEntry(id: 'w-huvu', term: 'Huvu', translation: 'Flower', tags: ['nature']),
  WordEntry(id: 'w-neeru', term: 'Neeru', translation: 'Water', tags: ['nature']),
  WordEntry(id: 'w-bhoomi', term: 'Bhoomi', translation: 'Earth / Land', tags: ['nature']),
  WordEntry(id: 'w-prayan', term: 'Prayan', translation: 'Travel', tags: ['travel']),
  WordEntry(id: 'w-rail', term: 'Rail', translation: 'Train', tags: ['travel']),
  WordEntry(id: 'w-bus', term: 'Bus', translation: 'Bus', tags: ['travel']),
  WordEntry(id: 'w-hotel', term: 'Hotel', translation: 'Hotel', tags: ['travel']),
];

/// Lookup map for fast vocabulary lookup by id.
final Map<String, WordEntry> kannadaVocabById = {
  for (final w in kannadaVocabulary) w.id: w,
};

/// Lookup by English translation (case-insensitive).
final Map<String, WordEntry> kannadaVocabByTranslation = {
  for (final w in kannadaVocabulary) w.translation.toLowerCase(): w,
};
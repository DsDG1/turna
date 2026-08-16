import 'package:turna/domain/ai_companion/ai_note.dart';

abstract interface class IAiNoteRepository {
  Future<void> saveNote(AiLearningNote note);
  Future<List<AiLearningNote>> searchNotes(String query, {int limit = 100});
  Future<void> deleteNote(String id);
  Future<void> clearNotes();
}

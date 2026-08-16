import 'package:turna/domain/ai_companion/ai_citation.dart';

abstract interface class ICourseKnowledgeRetriever {
  Future<List<AiCitation>> retrieve(String query, {int limit = 5});
  bool validateCitationIds(Iterable<String> ids);
}

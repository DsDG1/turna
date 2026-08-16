import 'package:turna/domain/ai_companion/diagnosis_snapshot.dart';

abstract interface class IDiagnosisRepository {
  Future<void> saveDiagnosis(DiagnosisSnapshot snapshot);
  Future<List<DiagnosisSnapshot>> recentDiagnoses({int limit = 10});
  Future<void> clearDiagnoses();
}

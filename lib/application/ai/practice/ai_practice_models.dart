// Project imports:
import 'package:turna/application/ai/ai_course_spec.dart';
import 'package:turna/domain/ai/ai_course.dart';

/// One generation job submitted to [AiPracticeJobQueue].
///
/// The spec carries the structural parameters (language, level, unit/lesson
/// counts, template, design brief, grounding). [sourceContext] is the already
/// formatted learner data block (mistakes / weak words / difficult points) —
/// plain text so the request can be persisted and retried without re-reading
/// the live providers.
class AiPracticeRequest {
  const AiPracticeRequest({
    required this.id,
    required this.title,
    required this.source,
    required this.spec,
    required this.languageCode,
    this.sourceContext = '',
    this.explanationRequested = false,
  });

  /// Row id; also used as the section id prefix by the prompt.
  final String id;

  final String title;
  final AiPracticeSource source;
  final AiCourseSpec spec;

  /// Canonical course language code (`tr`, `fr`, …) for the library row.
  final String languageCode;

  /// Pre-formatted learner evidence block injected into the user prompt.
  final String sourceContext;

  /// Whether a plain-language explanation is requested after generation.
  final bool explanationRequested;

  /// Persisted spec snapshot for retry after failure / interruption.
  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'source': source.name,
        'language': spec.language,
        'sourceLanguage': spec.sourceLanguage,
        'topic': spec.topic,
        'level': spec.level,
        'unitCount': spec.unitCount,
        'lessonsPerUnit': spec.lessonsPerUnit,
        'template': spec.template,
        'designBrief': spec.designBrief,
        'extraInstructions': spec.extraInstructions,
        'grounded': spec.groundedMode,
        'languageCode': languageCode,
        'sourceContext': sourceContext,
        'explanationRequested': explanationRequested,
      };

  static AiPracticeRequest? fromJson(Map<String, dynamic> json) {
    final id = json['id']?.toString() ?? '';
    if (id.isEmpty) return null;
    final unitCount = json['unitCount'];
    final lessonsPerUnit = json['lessonsPerUnit'];
    return AiPracticeRequest(
      id: id,
      title: json['title']?.toString() ?? 'AI practice',
      source: AiPracticeSource.fromWire(json['source']?.toString()),
      languageCode: json['languageCode']?.toString() ?? 'tr',
      sourceContext: json['sourceContext']?.toString() ?? '',
      explanationRequested: json['explanationRequested'] == true,
      spec: AiCourseSpec(
        language: json['language']?.toString() ?? 'Turkish',
        sourceLanguage: json['sourceLanguage']?.toString() ?? 'Chinese',
        topic: json['topic']?.toString() ?? '',
        level: json['level']?.toString() ?? 'A1',
        unitCount: unitCount is int ? unitCount : 1,
        lessonsPerUnit: lessonsPerUnit is int ? lessonsPerUnit : 1,
        template: json['template']?.toString() ?? 'mastery',
        designBrief: json['designBrief']?.toString() ?? '',
        extraInstructions: json['extraInstructions']?.toString() ?? '',
        groundedMode: json['grounded'] == true,
      ),
    );
  }
}

/// Coarse phase of the phased generator, used by the hub progress banner.
enum AiPracticePhase { outline, lessons, validating }

/// Progress callback payload. [done]/[total] count lessons in the fill phase;
/// they are both 0 for the single-shot outline/validate phases.
class AiPracticeProgress {
  const AiPracticeProgress({
    required this.phase,
    this.done = 0,
    this.total = 0,
    this.message = '',
  });

  final AiPracticePhase phase;
  final int done;
  final int total;
  final String message;
}

/// Final payload of one generation job.
class AiPracticeGenerationResult {
  const AiPracticeGenerationResult({
    required this.section,
    this.explanation,
    this.qualityJson,
  });

  /// Canonical section JSON (same contract as tool/gui and the asset loader).
  final Map<String, dynamic> section;

  /// Optional plain-language explanation from the chat model.
  final String? explanation;

  /// Serialized [AiPracticeQualityReport] for the generated section.
  final String? qualityJson;

  Map<String, dynamic> toSectionJson() => section;
}

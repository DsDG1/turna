// Project imports:
import 'package:turna/application/ai/ai_course_spec.dart';
import 'package:turna/application/ai/engine/ai_cancel_token.dart';
import 'package:turna/application/ai/engine/ai_engine.dart';
import 'package:turna/application/ai/engine/ai_engine_config.dart';

/// Plain-language explanation of a generated/transformed course section
/// (mirrors the former `AiCourseService.explainCourse` prompt, now routed
/// through the engine). Shared by the wish flow and the lesson helper.
Future<String> explainGeneratedCourse({
  required AiEngine engine,
  required AiEngineConfig config,
  required AiCourseSpec spec,
  required Map<String, dynamic> sectionJson,
  required AiCancelToken cancelToken,
}) async {
  final prompt =
      'You just generated the following course for a teacher with no '
      'technical background. Please explain in plain, easy-to-understand '
      '${spec.sourceLanguage}: the course\'s learning objectives, how units '
      'are divided, the key vocabulary / sentence patterns, and why it is '
      'designed this way. Do not output JSON or code.\n\n'
      'Course language: ${spec.language}\n'
      'Prompt language: ${spec.sourceLanguage}\n'
      'Level: ${spec.level}\n'
      'Course name: ${sectionJson['name'] ?? ''}\n'
      'Course description: ${sectionJson['description'] ?? ''}\n';
  final result = await engine.chat(
    config: config,
    messages: <Map<String, dynamic>>[
      {
        'role': 'system',
        'content':
            'You are a language-course design assistant who explains course '
                'content in plain ${spec.sourceLanguage}.',
      },
      {'role': 'user', 'content': prompt},
    ],
    temperature: 0.6,
    timeout: const Duration(seconds: 120),
    cancelToken: cancelToken,
  );
  final content = result.content;
  return content.isEmpty ? '(AI returned no explanation)' : content;
}

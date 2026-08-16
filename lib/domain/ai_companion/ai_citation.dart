enum AiCitationType { word, expression, grammar, lesson, aiSupplement }

class AiCitation {
  const AiCitation({
    required this.resourceId,
    required this.type,
    required this.title,
    required this.snippet,
    this.coursePath,
    this.version,
  });

  final String resourceId;
  final AiCitationType type;
  final String title;
  final String snippet;
  final String? coursePath;
  final String? version;

  Map<String, dynamic> toJson() => <String, dynamic>{
        'resourceId': resourceId,
        'type': type.name,
        'title': title,
        'snippet': snippet,
        'coursePath': coursePath,
        'version': version,
      };
}

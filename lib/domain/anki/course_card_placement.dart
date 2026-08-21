import 'package:turna/domain/anki/canonical_card_key.dart';

class CourseCardPlacement {
  const CourseCardPlacement({
    required this.placementId,
    required this.courseId,
    required this.cardKey,
    required this.sectionId,
    required this.unitId,
    required this.lessonId,
    required this.order,
    this.active = true,
    this.projectionVersion = 1,
    this.sourceFingerprint = '',
  });

  final String placementId;
  final String courseId;
  final CanonicalCardKey cardKey;
  final String sectionId;
  final String unitId;
  final String lessonId;
  final int order;
  final bool active;
  final int projectionVersion;
  final String sourceFingerprint;
}

class CourseProjectionGeneration {
  const CourseProjectionGeneration({
    required this.courseId,
    required this.sourceId,
    required this.generationId,
    required this.placements,
    required this.presentations,
  });

  final String courseId;
  final String sourceId;
  final String generationId;
  final List<CourseCardPlacement> placements;
  final List<PresentationPublishRow> presentations;
}

class PresentationPublishRow {
  const PresentationPublishRow({
    required this.cardKey,
    required this.kindName,
    required this.payloadJson,
    required this.sourceFingerprint,
    this.mappingVersion = 1,
    this.classifierVersion = 1,
    this.userConfirmed = false,
  });

  final CanonicalCardKey cardKey;
  final String kindName;
  final String payloadJson;
  final String sourceFingerprint;
  final int mappingVersion;
  final int classifierVersion;
  final bool userConfirmed;
}

class CanonicalSource {
  const CanonicalSource({
    required this.courseId,
    required this.profileId,
    required this.sourceId,
    required this.backend,
    required this.displayName,
    required this.sourceHash,
    required this.sourceFingerprint,
    required this.state,
  });

  final String courseId;
  final String profileId;
  final String sourceId;
  final AnkiBackendKind backend;
  final String displayName;
  final String sourceHash;
  final String sourceFingerprint;
  final String state;
}

class ImportPackageRequest {
  const ImportPackageRequest({
    required this.profileId,
    required this.packagePath,
    required this.sourceHash,
    this.displayName = '',
    this.courseId,
  });

  final String profileId;
  final String packagePath;
  final String sourceHash;
  final String displayName;
  final String? courseId;
}

import 'package:flutter/material.dart';
import 'package:turna/application/anki_official/contract/official_anki_dto.dart';
import 'package:turna/application/anki_official/engine/official_anki_engine.dart';
import 'package:turna/application/anki_official/official_anki_composition.dart';
import 'package:turna/application/anki_official/official_anki_feature_flags.dart';
import 'package:turna/application/anki_official/projection/official_anki_course_entry.dart';
import 'package:turna/application/anki_official/projection/official_anki_projection_jobs.dart';
import 'package:turna/application/anki_official/projection/official_anki_projection_mapper.dart';
import 'package:turna/application/anki_official/projection/official_anki_projection_service.dart';
import 'package:turna/application/anki_official/storage/official_anki_database.dart';
import 'package:turna/application/anki_official/storage/official_anki_source_dao.dart';
import 'package:turna/application/course_provider.dart';
import 'package:turna/courses/course_loader.dart';
import 'package:turna/data/course_database.dart';
import 'package:turna/views/anki_official/official_anki_mapping_page.dart';
import 'package:turna/views/anki_official/official_anki_reviewer_error_view.dart';

/// Production source management: mapping save/skip and explicit Generate.
class OfficialAnkiSourceManagementPage extends StatefulWidget {
  const OfficialAnkiSourceManagementPage({
    super.key,
    required this.engine,
    required this.catalog,
    required this.course,
    required this.profileId,
    this.flags,
    this.courseProvider,
    this.serviceOf,
  });

  final OfficialAnkiEngine engine;
  final OfficialAnkiDatabase catalog;
  final CourseDatabase course;
  final String profileId;
  final OfficialAnkiFeatureFlags? flags;
  final CourseProvider? courseProvider;
  final OfficialAnkiCourseProjectionService Function(String sourceId)? serviceOf;

  static const routeName = '/official-anki/sources';

  @override
  State<OfficialAnkiSourceManagementPage> createState() =>
      OfficialAnkiSourceManagementPageState();
}

class OfficialAnkiSourceManagementPageState
    extends State<OfficialAnkiSourceManagementPage> {
  String? selectedSourceId;
  OfficialAnkiProjectionPublishResult? lastResult;
  OfficialAnkiCourseProjectionService? _service;

  OfficialAnkiFeatureFlags get _flags =>
      widget.flags ?? OfficialAnkiFeatureFlags.current;

  OfficialAnkiCourseProjectionService serviceFor(String sourceId) {
    _service = widget.serviceOf?.call(sourceId) ??
        OfficialAnkiCompositionRoot.createProjectionService(
          engine: widget.engine,
          catalog: widget.catalog,
          course: widget.course,
          sourceId: sourceId,
          profileId: widget.profileId,
          flags: _flags,
        );
    return _service!;
  }

  Future<void> saveMapping({
    required String sourceId,
    required OfficialAnkiProjectionSchema schema,
    required OfficialAnkiMappingSuggestion suggestion,
  }) async {
    serviceFor(sourceId).confirmMapping(schema: schema, suggestion: suggestion);
    setState(() {});
  }

  Future<void> skipMapping({
    required String sourceId,
    required OfficialAnkiProjectionSchema schema,
  }) async {
    serviceFor(sourceId).skipNotetype(schema: schema);
    setState(() {});
  }

  Future<void> generate(String sourceId) async {
    final service = serviceFor(sourceId);
    final existing = service.jobs.activeWriter(sourceId);
    lastResult = await service.generateCourse(jobId: existing?.jobId);
    if (lastResult?.failed != true && lastResult?.needsMapping != true) {
      await widget.courseProvider?.reloadCourse();
    }
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    if (!_flags.allowsProjection) {
      return const Scaffold(
        body: OfficialAnkiReviewerErrorView(
          key: Key('official-source-flag-fail-closed'),
          messageKey: 'official_anki.flag_fail_closed',
        ),
      );
    }
    final sources = OfficialAnkiSourceDao(widget.catalog).listSources(
      widget.profileId,
    );
    return Scaffold(
      appBar: AppBar(title: const Text('官方 Anki 课程')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          for (final source in sources)
            ListTile(
              key: Key('official-source-${source.sourceId}'),
              title: Text(source.displayName),
              subtitle: Text(_stateLabel(source.sourceId)),
              onTap: () => setState(() => selectedSourceId = source.sourceId),
              trailing: Wrap(
                spacing: 8,
                children: [
                  TextButton(
                    key: Key('official-source-map-${source.sourceId}'),
                    onPressed: () => _openMapping(source.sourceId),
                    child: const Text('映射'),
                  ),
                  FilledButton(
                    key: Key('official-source-generate-${source.sourceId}'),
                    onPressed: () => generate(source.sourceId),
                    child: const Text('生成课程'),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  String _stateLabel(String sourceId) {
    final job = OfficialAnkiProjectionJobRepository(widget.catalog)
        .activeWriter(sourceId);
    if (job == null) return 'not_projected';
    return job.state.name;
  }

  Future<void> _openMapping(String sourceId) async {
    final service = serviceFor(sourceId);
    final schemas = await widget.engine.getProjectionSchemas(includeSamples: true);
    if (!mounted || schemas.isEmpty) return;
    final schema = schemas.first;
    final suggestion = service.suggestFor(schema);
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => OfficialAnkiMappingPage(
          notetypeName: schema.name,
          suggestion: suggestion,
          schema: schema,
          onConfirm: (next) => saveMapping(
            sourceId: sourceId,
            schema: schema,
            suggestion: next,
          ),
          onSkip: () => skipMapping(sourceId: sourceId, schema: schema),
          onGenerateCourse: () => generate(sourceId),
        ),
      ),
    );
  }
}

/// Production factory used by OfficialAnkiInternalPage. Flag-off or missing
/// catalog/course/engine returns null (fail closed, no Legacy fallback).
Future<OfficialAnkiSourceManagementPage?> officialAnkiBuildSourceManagementPage({
  OfficialAnkiEngine? engine,
  OfficialAnkiDatabase? catalog,
  CourseDatabase? course,
  String? profileId,
  OfficialAnkiFeatureFlags? flags,
  CourseProvider? courseProvider,
}) async {
  final resolvedFlags = flags ?? OfficialAnkiFeatureFlags.current;
  if (!resolvedFlags.allowsProjection) return null;
  final resolvedCatalog = catalog ??
      OfficialAnkiCompositionRoot.readOnlyCatalog ??
      OfficialAnkiCourseEntry.catalogOf?.call();
  final resolvedCourse = course ?? officialAnkiProductionCourseDatabase();
  final resolvedEngine =
      engine ?? OfficialAnkiCompositionRoot.projectionEngineFromSession();
  final resolvedProfile = profileId ??
      OfficialAnkiCompositionRoot.locatorPaths?.profileId ??
      'profile-default-01';
  if (resolvedCatalog == null ||
      resolvedCourse == null ||
      resolvedEngine == null) {
    return null;
  }
  return OfficialAnkiSourceManagementPage(
    engine: resolvedEngine,
    catalog: resolvedCatalog,
    course: resolvedCourse,
    profileId: resolvedProfile,
    flags: resolvedFlags,
    courseProvider: courseProvider,
  );
}

OfficialAnkiCourseProjectionService officialAnkiProductionProjectionService({
  required OfficialAnkiEngine engine,
  required OfficialAnkiDatabase catalog,
  required CourseDatabase course,
  required String sourceId,
  required String profileId,
  OfficialAnkiFeatureFlags? flags,
}) {
  return OfficialAnkiCompositionRoot.createProjectionService(
    engine: engine,
    catalog: catalog,
    course: course,
    sourceId: sourceId,
    profileId: profileId,
    flags: flags,
  );
}

CourseDatabase? officialAnkiProductionCourseDatabase() {
  return CourseLoader.databaseOrNull();
}

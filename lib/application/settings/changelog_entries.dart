/// 单条 release 数据。可公开复用。
class ChangelogRelease {
  final String version;
  final String title;
  final List<String> items;

  const ChangelogRelease({
    required this.version,
    required this.title,
    required this.items,
  });
}

/// 历程步骤数据。
class JourneyStep {
  final String label;
  final String title;
  final String subtitle;

  const JourneyStep({
    required this.label,
    required this.title,
    required this.subtitle,
  });
}

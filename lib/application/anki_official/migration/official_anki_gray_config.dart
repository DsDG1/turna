enum OfficialAnkiGrayCohort { off, g0, g1, g2, g3, g4 }

class OfficialAnkiGrayConfig {
  const OfficialAnkiGrayConfig({this.cohort = OfficialAnkiGrayCohort.off});

  final OfficialAnkiGrayCohort cohort;

  factory OfficialAnkiGrayConfig.fromEnvironment() {
    const raw = String.fromEnvironment(
      'TURNA_OFFICIAL_ANKI_GRAY_COHORT',
      defaultValue: 'g4',
    );
    return OfficialAnkiGrayConfig(cohort: parseGrayCohort(raw));
  }

  bool get isOn => cohort != OfficialAnkiGrayCohort.off;

  int get thresholdPercent {
    switch (cohort) {
      case OfficialAnkiGrayCohort.off:
      case OfficialAnkiGrayCohort.g0:
        return 0;
      case OfficialAnkiGrayCohort.g1:
        return 1;
      case OfficialAnkiGrayCohort.g2:
        return 10;
      case OfficialAnkiGrayCohort.g3:
        return 50;
      case OfficialAnkiGrayCohort.g4:
        return 100;
    }
  }

  bool allowsNewOfficialImport({
    required String platform,
    required bool cutoverEnabled,
  }) {
    if (!cutoverEnabled) return false;
    if (platform != 'android') return false;
    return thresholdPercent > 0;
  }

  static OfficialAnkiGrayCohort parseGrayCohort(String? raw) {
    final v = (raw ?? '').trim().toLowerCase();
    if (v.isEmpty || v == 'off' || v == '0' || v == 'g0') {
      return OfficialAnkiGrayCohort.off;
    }
    if (v == 'g1' || v == '1' || v == '1%' || v == '01') return OfficialAnkiGrayCohort.g1;
    if (v == 'g2' || v == '2' || v == '10%' || v == '10') return OfficialAnkiGrayCohort.g2;
    if (v == 'g3' || v == '3' || v == '50%' || v == '50') return OfficialAnkiGrayCohort.g3;
    if (v == 'g4' || v == '4' || v == '100%' || v == '100') return OfficialAnkiGrayCohort.g4;
    return OfficialAnkiGrayCohort.off;
  }
}

/// Dual-source home due. Never merge Official and Turna stores.
class OfficialAnkiHomeDue {
  OfficialAnkiHomeDue._();

  static var officialDue = 0;
  static var turnaDue = 0;

  static void reset() {
    officialDue = 0;
    turnaDue = 0;
  }
}

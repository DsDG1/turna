import 'package:flutter_test/flutter_test.dart';
import 'package:turna/application/anki_official/official_anki_feature_flags.dart';

/// step4.md A1：v2 并存 flag 的命名与灰度边界。
void main() {
  test('constructor default keeps v2ImportChain off', () {
    expect(const OfficialAnkiFeatureFlags().v2ImportChain, isFalse);
  });

  test('productionAndroid stays off until the kill matrix is green', () {
    expect(OfficialAnkiFeatureFlags.productionAndroid.v2ImportChain, isFalse);
  });

  test('allowsV2ImportChain rides the v1 capability floor', () {
    // v1 位全开 + v2 位关 → 不放行（回退态：仅路由回 v1）。
    const v1Floor = OfficialAnkiFeatureFlags.productionAndroid;
    expect(v1Floor.allowsV2ImportChain, isFalse);

    // v2 位开但 v1 地基缺一（engine off）→ fail-closed。
    final missingEngine = v1Floor.copyWith(engine: false, v2ImportChain: true);
    expect(missingEngine.allowsV2ImportChain, isFalse);

    // 地基全开 + v2 位开 → 放行。
    final v2 = v1Floor.copyWith(v2ImportChain: true);
    expect(v2.allowsV2ImportChain, isTrue);
  });

  test('copyWith round-trips v2ImportChain', () {
    final on = const OfficialAnkiFeatureFlags().copyWith(v2ImportChain: true);
    expect(on.v2ImportChain, isTrue);
    expect(on.copyWith().v2ImportChain, isTrue);
    expect(on.copyWith(v2ImportChain: false).v2ImportChain, isFalse);
  });

  test('fromEnvironment keeps production default off', () {
    expect(OfficialAnkiFeatureFlags.fromEnvironment().v2ImportChain, isFalse);
  });
}

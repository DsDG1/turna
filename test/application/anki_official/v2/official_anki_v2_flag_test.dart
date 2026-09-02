import 'package:flutter_test/flutter_test.dart';
import 'package:turna/application/anki_official/official_anki_feature_flags.dart';

/// step4.md A1：v2 并存 flag 的命名与灰度边界。R4（2026-09-02）翻开后：
/// productionAndroid 恒 true；回退 = 常量翻回 false（只把新导入路由回 v1，
/// 已导入的 v2 来源继续可学——见 official_anki_feature_flags.dart 头注释）。
void main() {
  test('constructor default keeps v2ImportChain off', () {
    expect(const OfficialAnkiFeatureFlags().v2ImportChain, isFalse);
  });

  test('productionAndroid ships with v2ImportChain on (R4, 2026-09-02)', () {
    expect(OfficialAnkiFeatureFlags.productionAndroid.v2ImportChain, isTrue);
  });

  test('allowsV2ImportChain rides the v1 capability floor', () {
    // 生产位全开 → 放行。
    const production = OfficialAnkiFeatureFlags.productionAndroid;
    expect(production.allowsV2ImportChain, isTrue);

    // 回退态：v2 位翻回 false → 不放行（仅新导入回 v1）。
    final rolledBack = production.copyWith(v2ImportChain: false);
    expect(rolledBack.allowsV2ImportChain, isFalse);

    // v2 位开但 v1 地基缺一（engine off）→ fail-closed。
    final missingEngine = production.copyWith(engine: false);
    expect(missingEngine.allowsV2ImportChain, isFalse);
  });

  test('copyWith round-trips v2ImportChain', () {
    final on = const OfficialAnkiFeatureFlags().copyWith(v2ImportChain: true);
    expect(on.v2ImportChain, isTrue);
    expect(on.copyWith().v2ImportChain, isTrue);
    expect(on.copyWith(v2ImportChain: false).v2ImportChain, isFalse);
  });

  test('fromEnvironment inherits the production v2 bit', () {
    // R4 陷阱守卫：fromEnvironment 不得把 v2 位经 copyWith(v2ImportChain:
    // define) 接回——absent define 读 false，会把生产常量的 true 盖回
    // false（生产包等于白翻）。必须继承 productionAndroid 的值。
    expect(
      OfficialAnkiFeatureFlags.fromEnvironment().v2ImportChain,
      OfficialAnkiFeatureFlags.productionAndroid.v2ImportChain,
    );
  });
}

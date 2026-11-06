import 'package:freezed_annotation/freezed_annotation.dart';

part 'review_policy.freezed.dart';
part 'review_policy.g.dart';

@freezed
abstract class ReviewPolicy with _$ReviewPolicy {
  const factory ReviewPolicy({
    required int minItems,
    required int maxItems,
    @Default(<String, double>{}) Map<String, double> typeWeights,
  }) = _ReviewPolicy;

  const ReviewPolicy._();

  factory ReviewPolicy.fromJson(Map<String, dynamic> json) =>
      _$ReviewPolicyFromJson(json);

  double baseWeightFor(String runtimeType) => typeWeights[runtimeType] ?? 1.0;
}

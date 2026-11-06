// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'review_policy.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

_ReviewPolicy _$ReviewPolicyFromJson(Map<String, dynamic> json) =>
    _ReviewPolicy(
      minItems: (json['minItems'] as num).toInt(),
      maxItems: (json['maxItems'] as num).toInt(),
      typeWeights: (json['typeWeights'] as Map<String, dynamic>?)?.map(
            (k, e) => MapEntry(k, (e as num).toDouble()),
          ) ??
          const <String, double>{},
    );

Map<String, dynamic> _$ReviewPolicyToJson(_ReviewPolicy instance) =>
    <String, dynamic>{
      'minItems': instance.minItems,
      'maxItems': instance.maxItems,
      'typeWeights': instance.typeWeights,
    };

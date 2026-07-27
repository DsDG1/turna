// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'word_entry.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

_WordEntry _$WordEntryFromJson(Map<String, dynamic> json) => _WordEntry(
      id: json['id'] as String,
      term: json['term'] as String,
      translation: json['translation'] as String,
      pronunciation: json['pronunciation'] as String?,
      audioAsset: json['audioAsset'] as String?,
      tags:
          (json['tags'] as List<dynamic>?)?.map((e) => e as String).toList() ??
              const <String>[],
    );

Map<String, dynamic> _$WordEntryToJson(_WordEntry instance) =>
    <String, dynamic>{
      'id': instance.id,
      'term': instance.term,
      'translation': instance.translation,
      'pronunciation': instance.pronunciation,
      'audioAsset': instance.audioAsset,
      'tags': instance.tags,
    };

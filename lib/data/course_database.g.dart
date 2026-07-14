// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'course_database.dart';

// ignore_for_file: type=lint
class $SectionsTable extends Sections with TableInfo<$SectionsTable, Section> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $SectionsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
      'id', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _nameMeta = const VerificationMeta('name');
  @override
  late final GeneratedColumn<String> name = GeneratedColumn<String>(
      'name', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _descriptionMeta =
      const VerificationMeta('description');
  @override
  late final GeneratedColumn<String> description = GeneratedColumn<String>(
      'description', aliasedName, false,
      type: DriftSqlType.string,
      requiredDuringInsert: false,
      defaultValue: const Constant(''));
  static const VerificationMeta _prerequisiteSectionIdsMeta =
      const VerificationMeta('prerequisiteSectionIds');
  @override
  late final GeneratedColumn<String> prerequisiteSectionIds =
      GeneratedColumn<String>('prerequisite_section_ids', aliasedName, false,
          type: DriftSqlType.string,
          requiredDuringInsert: false,
          defaultValue: const Constant('[]'));
  static const VerificationMeta _sortOrderMeta =
      const VerificationMeta('sortOrder');
  @override
  late final GeneratedColumn<int> sortOrder = GeneratedColumn<int>(
      'sort_order', aliasedName, false,
      type: DriftSqlType.int,
      requiredDuringInsert: false,
      defaultValue: const Constant(0));
  @override
  List<GeneratedColumn> get $columns =>
      [id, name, description, prerequisiteSectionIds, sortOrder];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'sections';
  @override
  VerificationContext validateIntegrity(Insertable<Section> instance,
      {bool isInserting = false}) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('name')) {
      context.handle(
          _nameMeta, name.isAcceptableOrUnknown(data['name']!, _nameMeta));
    } else if (isInserting) {
      context.missing(_nameMeta);
    }
    if (data.containsKey('description')) {
      context.handle(
          _descriptionMeta,
          description.isAcceptableOrUnknown(
              data['description']!, _descriptionMeta));
    }
    if (data.containsKey('prerequisite_section_ids')) {
      context.handle(
          _prerequisiteSectionIdsMeta,
          prerequisiteSectionIds.isAcceptableOrUnknown(
              data['prerequisite_section_ids']!, _prerequisiteSectionIdsMeta));
    }
    if (data.containsKey('sort_order')) {
      context.handle(_sortOrderMeta,
          sortOrder.isAcceptableOrUnknown(data['sort_order']!, _sortOrderMeta));
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  Section map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return Section(
      id: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}id'])!,
      name: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}name'])!,
      description: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}description'])!,
      prerequisiteSectionIds: attachedDatabase.typeMapping.read(
          DriftSqlType.string,
          data['${effectivePrefix}prerequisite_section_ids'])!,
      sortOrder: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}sort_order'])!,
    );
  }

  @override
  $SectionsTable createAlias(String alias) {
    return $SectionsTable(attachedDatabase, alias);
  }
}

class Section extends DataClass implements Insertable<Section> {
  final String id;
  final String name;
  final String description;
  final String prerequisiteSectionIds;
  final int sortOrder;
  const Section(
      {required this.id,
      required this.name,
      required this.description,
      required this.prerequisiteSectionIds,
      required this.sortOrder});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['name'] = Variable<String>(name);
    map['description'] = Variable<String>(description);
    map['prerequisite_section_ids'] = Variable<String>(prerequisiteSectionIds);
    map['sort_order'] = Variable<int>(sortOrder);
    return map;
  }

  SectionsCompanion toCompanion(bool nullToAbsent) {
    return SectionsCompanion(
      id: Value(id),
      name: Value(name),
      description: Value(description),
      prerequisiteSectionIds: Value(prerequisiteSectionIds),
      sortOrder: Value(sortOrder),
    );
  }

  factory Section.fromJson(Map<String, dynamic> json,
      {ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return Section(
      id: serializer.fromJson<String>(json['id']),
      name: serializer.fromJson<String>(json['name']),
      description: serializer.fromJson<String>(json['description']),
      prerequisiteSectionIds:
          serializer.fromJson<String>(json['prerequisiteSectionIds']),
      sortOrder: serializer.fromJson<int>(json['sortOrder']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'name': serializer.toJson<String>(name),
      'description': serializer.toJson<String>(description),
      'prerequisiteSectionIds':
          serializer.toJson<String>(prerequisiteSectionIds),
      'sortOrder': serializer.toJson<int>(sortOrder),
    };
  }

  Section copyWith(
          {String? id,
          String? name,
          String? description,
          String? prerequisiteSectionIds,
          int? sortOrder}) =>
      Section(
        id: id ?? this.id,
        name: name ?? this.name,
        description: description ?? this.description,
        prerequisiteSectionIds:
            prerequisiteSectionIds ?? this.prerequisiteSectionIds,
        sortOrder: sortOrder ?? this.sortOrder,
      );
  Section copyWithCompanion(SectionsCompanion data) {
    return Section(
      id: data.id.present ? data.id.value : this.id,
      name: data.name.present ? data.name.value : this.name,
      description:
          data.description.present ? data.description.value : this.description,
      prerequisiteSectionIds: data.prerequisiteSectionIds.present
          ? data.prerequisiteSectionIds.value
          : this.prerequisiteSectionIds,
      sortOrder: data.sortOrder.present ? data.sortOrder.value : this.sortOrder,
    );
  }

  @override
  String toString() {
    return (StringBuffer('Section(')
          ..write('id: $id, ')
          ..write('name: $name, ')
          ..write('description: $description, ')
          ..write('prerequisiteSectionIds: $prerequisiteSectionIds, ')
          ..write('sortOrder: $sortOrder')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode =>
      Object.hash(id, name, description, prerequisiteSectionIds, sortOrder);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is Section &&
          other.id == this.id &&
          other.name == this.name &&
          other.description == this.description &&
          other.prerequisiteSectionIds == this.prerequisiteSectionIds &&
          other.sortOrder == this.sortOrder);
}

class SectionsCompanion extends UpdateCompanion<Section> {
  final Value<String> id;
  final Value<String> name;
  final Value<String> description;
  final Value<String> prerequisiteSectionIds;
  final Value<int> sortOrder;
  final Value<int> rowid;
  const SectionsCompanion({
    this.id = const Value.absent(),
    this.name = const Value.absent(),
    this.description = const Value.absent(),
    this.prerequisiteSectionIds = const Value.absent(),
    this.sortOrder = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  SectionsCompanion.insert({
    required String id,
    required String name,
    this.description = const Value.absent(),
    this.prerequisiteSectionIds = const Value.absent(),
    this.sortOrder = const Value.absent(),
    this.rowid = const Value.absent(),
  })  : id = Value(id),
        name = Value(name);
  static Insertable<Section> custom({
    Expression<String>? id,
    Expression<String>? name,
    Expression<String>? description,
    Expression<String>? prerequisiteSectionIds,
    Expression<int>? sortOrder,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (name != null) 'name': name,
      if (description != null) 'description': description,
      if (prerequisiteSectionIds != null)
        'prerequisite_section_ids': prerequisiteSectionIds,
      if (sortOrder != null) 'sort_order': sortOrder,
      if (rowid != null) 'rowid': rowid,
    });
  }

  SectionsCompanion copyWith(
      {Value<String>? id,
      Value<String>? name,
      Value<String>? description,
      Value<String>? prerequisiteSectionIds,
      Value<int>? sortOrder,
      Value<int>? rowid}) {
    return SectionsCompanion(
      id: id ?? this.id,
      name: name ?? this.name,
      description: description ?? this.description,
      prerequisiteSectionIds:
          prerequisiteSectionIds ?? this.prerequisiteSectionIds,
      sortOrder: sortOrder ?? this.sortOrder,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (name.present) {
      map['name'] = Variable<String>(name.value);
    }
    if (description.present) {
      map['description'] = Variable<String>(description.value);
    }
    if (prerequisiteSectionIds.present) {
      map['prerequisite_section_ids'] =
          Variable<String>(prerequisiteSectionIds.value);
    }
    if (sortOrder.present) {
      map['sort_order'] = Variable<int>(sortOrder.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('SectionsCompanion(')
          ..write('id: $id, ')
          ..write('name: $name, ')
          ..write('description: $description, ')
          ..write('prerequisiteSectionIds: $prerequisiteSectionIds, ')
          ..write('sortOrder: $sortOrder, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $UnitsTable extends Units with TableInfo<$UnitsTable, Unit> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $UnitsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
      'id', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _sectionIdMeta =
      const VerificationMeta('sectionId');
  @override
  late final GeneratedColumn<String> sectionId = GeneratedColumn<String>(
      'section_id', aliasedName, false,
      type: DriftSqlType.string,
      requiredDuringInsert: true,
      $customConstraints: 'NOT NULL REFERENCES sections(id) ON DELETE CASCADE');
  static const VerificationMeta _nameMeta = const VerificationMeta('name');
  @override
  late final GeneratedColumn<String> name = GeneratedColumn<String>(
      'name', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _descriptionMeta =
      const VerificationMeta('description');
  @override
  late final GeneratedColumn<String> description = GeneratedColumn<String>(
      'description', aliasedName, false,
      type: DriftSqlType.string,
      requiredDuringInsert: false,
      defaultValue: const Constant(''));
  static const VerificationMeta _prerequisiteUnitIdsMeta =
      const VerificationMeta('prerequisiteUnitIds');
  @override
  late final GeneratedColumn<String> prerequisiteUnitIds =
      GeneratedColumn<String>('prerequisite_unit_ids', aliasedName, false,
          type: DriftSqlType.string,
          requiredDuringInsert: false,
          defaultValue: const Constant('[]'));
  static const VerificationMeta _sortOrderMeta =
      const VerificationMeta('sortOrder');
  @override
  late final GeneratedColumn<int> sortOrder = GeneratedColumn<int>(
      'sort_order', aliasedName, false,
      type: DriftSqlType.int,
      requiredDuringInsert: false,
      defaultValue: const Constant(0));
  @override
  List<GeneratedColumn> get $columns =>
      [id, sectionId, name, description, prerequisiteUnitIds, sortOrder];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'units';
  @override
  VerificationContext validateIntegrity(Insertable<Unit> instance,
      {bool isInserting = false}) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('section_id')) {
      context.handle(_sectionIdMeta,
          sectionId.isAcceptableOrUnknown(data['section_id']!, _sectionIdMeta));
    } else if (isInserting) {
      context.missing(_sectionIdMeta);
    }
    if (data.containsKey('name')) {
      context.handle(
          _nameMeta, name.isAcceptableOrUnknown(data['name']!, _nameMeta));
    } else if (isInserting) {
      context.missing(_nameMeta);
    }
    if (data.containsKey('description')) {
      context.handle(
          _descriptionMeta,
          description.isAcceptableOrUnknown(
              data['description']!, _descriptionMeta));
    }
    if (data.containsKey('prerequisite_unit_ids')) {
      context.handle(
          _prerequisiteUnitIdsMeta,
          prerequisiteUnitIds.isAcceptableOrUnknown(
              data['prerequisite_unit_ids']!, _prerequisiteUnitIdsMeta));
    }
    if (data.containsKey('sort_order')) {
      context.handle(_sortOrderMeta,
          sortOrder.isAcceptableOrUnknown(data['sort_order']!, _sortOrderMeta));
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  Unit map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return Unit(
      id: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}id'])!,
      sectionId: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}section_id'])!,
      name: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}name'])!,
      description: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}description'])!,
      prerequisiteUnitIds: attachedDatabase.typeMapping.read(
          DriftSqlType.string,
          data['${effectivePrefix}prerequisite_unit_ids'])!,
      sortOrder: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}sort_order'])!,
    );
  }

  @override
  $UnitsTable createAlias(String alias) {
    return $UnitsTable(attachedDatabase, alias);
  }
}

class Unit extends DataClass implements Insertable<Unit> {
  final String id;
  final String sectionId;
  final String name;
  final String description;
  final String prerequisiteUnitIds;
  final int sortOrder;
  const Unit(
      {required this.id,
      required this.sectionId,
      required this.name,
      required this.description,
      required this.prerequisiteUnitIds,
      required this.sortOrder});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['section_id'] = Variable<String>(sectionId);
    map['name'] = Variable<String>(name);
    map['description'] = Variable<String>(description);
    map['prerequisite_unit_ids'] = Variable<String>(prerequisiteUnitIds);
    map['sort_order'] = Variable<int>(sortOrder);
    return map;
  }

  UnitsCompanion toCompanion(bool nullToAbsent) {
    return UnitsCompanion(
      id: Value(id),
      sectionId: Value(sectionId),
      name: Value(name),
      description: Value(description),
      prerequisiteUnitIds: Value(prerequisiteUnitIds),
      sortOrder: Value(sortOrder),
    );
  }

  factory Unit.fromJson(Map<String, dynamic> json,
      {ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return Unit(
      id: serializer.fromJson<String>(json['id']),
      sectionId: serializer.fromJson<String>(json['sectionId']),
      name: serializer.fromJson<String>(json['name']),
      description: serializer.fromJson<String>(json['description']),
      prerequisiteUnitIds:
          serializer.fromJson<String>(json['prerequisiteUnitIds']),
      sortOrder: serializer.fromJson<int>(json['sortOrder']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'sectionId': serializer.toJson<String>(sectionId),
      'name': serializer.toJson<String>(name),
      'description': serializer.toJson<String>(description),
      'prerequisiteUnitIds': serializer.toJson<String>(prerequisiteUnitIds),
      'sortOrder': serializer.toJson<int>(sortOrder),
    };
  }

  Unit copyWith(
          {String? id,
          String? sectionId,
          String? name,
          String? description,
          String? prerequisiteUnitIds,
          int? sortOrder}) =>
      Unit(
        id: id ?? this.id,
        sectionId: sectionId ?? this.sectionId,
        name: name ?? this.name,
        description: description ?? this.description,
        prerequisiteUnitIds: prerequisiteUnitIds ?? this.prerequisiteUnitIds,
        sortOrder: sortOrder ?? this.sortOrder,
      );
  Unit copyWithCompanion(UnitsCompanion data) {
    return Unit(
      id: data.id.present ? data.id.value : this.id,
      sectionId: data.sectionId.present ? data.sectionId.value : this.sectionId,
      name: data.name.present ? data.name.value : this.name,
      description:
          data.description.present ? data.description.value : this.description,
      prerequisiteUnitIds: data.prerequisiteUnitIds.present
          ? data.prerequisiteUnitIds.value
          : this.prerequisiteUnitIds,
      sortOrder: data.sortOrder.present ? data.sortOrder.value : this.sortOrder,
    );
  }

  @override
  String toString() {
    return (StringBuffer('Unit(')
          ..write('id: $id, ')
          ..write('sectionId: $sectionId, ')
          ..write('name: $name, ')
          ..write('description: $description, ')
          ..write('prerequisiteUnitIds: $prerequisiteUnitIds, ')
          ..write('sortOrder: $sortOrder')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
      id, sectionId, name, description, prerequisiteUnitIds, sortOrder);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is Unit &&
          other.id == this.id &&
          other.sectionId == this.sectionId &&
          other.name == this.name &&
          other.description == this.description &&
          other.prerequisiteUnitIds == this.prerequisiteUnitIds &&
          other.sortOrder == this.sortOrder);
}

class UnitsCompanion extends UpdateCompanion<Unit> {
  final Value<String> id;
  final Value<String> sectionId;
  final Value<String> name;
  final Value<String> description;
  final Value<String> prerequisiteUnitIds;
  final Value<int> sortOrder;
  final Value<int> rowid;
  const UnitsCompanion({
    this.id = const Value.absent(),
    this.sectionId = const Value.absent(),
    this.name = const Value.absent(),
    this.description = const Value.absent(),
    this.prerequisiteUnitIds = const Value.absent(),
    this.sortOrder = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  UnitsCompanion.insert({
    required String id,
    required String sectionId,
    required String name,
    this.description = const Value.absent(),
    this.prerequisiteUnitIds = const Value.absent(),
    this.sortOrder = const Value.absent(),
    this.rowid = const Value.absent(),
  })  : id = Value(id),
        sectionId = Value(sectionId),
        name = Value(name);
  static Insertable<Unit> custom({
    Expression<String>? id,
    Expression<String>? sectionId,
    Expression<String>? name,
    Expression<String>? description,
    Expression<String>? prerequisiteUnitIds,
    Expression<int>? sortOrder,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (sectionId != null) 'section_id': sectionId,
      if (name != null) 'name': name,
      if (description != null) 'description': description,
      if (prerequisiteUnitIds != null)
        'prerequisite_unit_ids': prerequisiteUnitIds,
      if (sortOrder != null) 'sort_order': sortOrder,
      if (rowid != null) 'rowid': rowid,
    });
  }

  UnitsCompanion copyWith(
      {Value<String>? id,
      Value<String>? sectionId,
      Value<String>? name,
      Value<String>? description,
      Value<String>? prerequisiteUnitIds,
      Value<int>? sortOrder,
      Value<int>? rowid}) {
    return UnitsCompanion(
      id: id ?? this.id,
      sectionId: sectionId ?? this.sectionId,
      name: name ?? this.name,
      description: description ?? this.description,
      prerequisiteUnitIds: prerequisiteUnitIds ?? this.prerequisiteUnitIds,
      sortOrder: sortOrder ?? this.sortOrder,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (sectionId.present) {
      map['section_id'] = Variable<String>(sectionId.value);
    }
    if (name.present) {
      map['name'] = Variable<String>(name.value);
    }
    if (description.present) {
      map['description'] = Variable<String>(description.value);
    }
    if (prerequisiteUnitIds.present) {
      map['prerequisite_unit_ids'] =
          Variable<String>(prerequisiteUnitIds.value);
    }
    if (sortOrder.present) {
      map['sort_order'] = Variable<int>(sortOrder.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('UnitsCompanion(')
          ..write('id: $id, ')
          ..write('sectionId: $sectionId, ')
          ..write('name: $name, ')
          ..write('description: $description, ')
          ..write('prerequisiteUnitIds: $prerequisiteUnitIds, ')
          ..write('sortOrder: $sortOrder, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $LessonsTable extends Lessons with TableInfo<$LessonsTable, Lesson> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $LessonsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
      'id', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _unitIdMeta = const VerificationMeta('unitId');
  @override
  late final GeneratedColumn<String> unitId = GeneratedColumn<String>(
      'unit_id', aliasedName, false,
      type: DriftSqlType.string,
      requiredDuringInsert: true,
      $customConstraints: 'NOT NULL REFERENCES units(id) ON DELETE CASCADE');
  static const VerificationMeta _nameMeta = const VerificationMeta('name');
  @override
  late final GeneratedColumn<String> name = GeneratedColumn<String>(
      'name', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _descriptionMeta =
      const VerificationMeta('description');
  @override
  late final GeneratedColumn<String> description = GeneratedColumn<String>(
      'description', aliasedName, false,
      type: DriftSqlType.string,
      requiredDuringInsert: false,
      defaultValue: const Constant(''));
  static const VerificationMeta _typeMeta = const VerificationMeta('type');
  @override
  late final GeneratedColumn<String> type = GeneratedColumn<String>(
      'type', aliasedName, false,
      type: DriftSqlType.string,
      requiredDuringInsert: false,
      defaultValue: const Constant('normal'));
  static const VerificationMeta _templateMeta =
      const VerificationMeta('template');
  @override
  late final GeneratedColumn<String> template = GeneratedColumn<String>(
      'template', aliasedName, false,
      type: DriftSqlType.string,
      requiredDuringInsert: false,
      defaultValue: const Constant('legacy'));
  static const VerificationMeta _prerequisiteLessonIdsMeta =
      const VerificationMeta('prerequisiteLessonIds');
  @override
  late final GeneratedColumn<String> prerequisiteLessonIds =
      GeneratedColumn<String>('prerequisite_lesson_ids', aliasedName, false,
          type: DriftSqlType.string,
          requiredDuringInsert: false,
          defaultValue: const Constant('[]'));
  static const VerificationMeta _sortOrderMeta =
      const VerificationMeta('sortOrder');
  @override
  late final GeneratedColumn<int> sortOrder = GeneratedColumn<int>(
      'sort_order', aliasedName, false,
      type: DriftSqlType.int,
      requiredDuringInsert: false,
      defaultValue: const Constant(0));
  @override
  List<GeneratedColumn> get $columns => [
        id,
        unitId,
        name,
        description,
        type,
        template,
        prerequisiteLessonIds,
        sortOrder
      ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'lessons';
  @override
  VerificationContext validateIntegrity(Insertable<Lesson> instance,
      {bool isInserting = false}) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('unit_id')) {
      context.handle(_unitIdMeta,
          unitId.isAcceptableOrUnknown(data['unit_id']!, _unitIdMeta));
    } else if (isInserting) {
      context.missing(_unitIdMeta);
    }
    if (data.containsKey('name')) {
      context.handle(
          _nameMeta, name.isAcceptableOrUnknown(data['name']!, _nameMeta));
    } else if (isInserting) {
      context.missing(_nameMeta);
    }
    if (data.containsKey('description')) {
      context.handle(
          _descriptionMeta,
          description.isAcceptableOrUnknown(
              data['description']!, _descriptionMeta));
    }
    if (data.containsKey('type')) {
      context.handle(
          _typeMeta, type.isAcceptableOrUnknown(data['type']!, _typeMeta));
    }
    if (data.containsKey('template')) {
      context.handle(_templateMeta,
          template.isAcceptableOrUnknown(data['template']!, _templateMeta));
    }
    if (data.containsKey('prerequisite_lesson_ids')) {
      context.handle(
          _prerequisiteLessonIdsMeta,
          prerequisiteLessonIds.isAcceptableOrUnknown(
              data['prerequisite_lesson_ids']!, _prerequisiteLessonIdsMeta));
    }
    if (data.containsKey('sort_order')) {
      context.handle(_sortOrderMeta,
          sortOrder.isAcceptableOrUnknown(data['sort_order']!, _sortOrderMeta));
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  Lesson map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return Lesson(
      id: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}id'])!,
      unitId: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}unit_id'])!,
      name: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}name'])!,
      description: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}description'])!,
      type: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}type'])!,
      template: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}template'])!,
      prerequisiteLessonIds: attachedDatabase.typeMapping.read(
          DriftSqlType.string,
          data['${effectivePrefix}prerequisite_lesson_ids'])!,
      sortOrder: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}sort_order'])!,
    );
  }

  @override
  $LessonsTable createAlias(String alias) {
    return $LessonsTable(attachedDatabase, alias);
  }
}

class Lesson extends DataClass implements Insertable<Lesson> {
  final String id;
  final String unitId;
  final String name;
  final String description;
  final String type;
  final String template;
  final String prerequisiteLessonIds;
  final int sortOrder;
  const Lesson(
      {required this.id,
      required this.unitId,
      required this.name,
      required this.description,
      required this.type,
      required this.template,
      required this.prerequisiteLessonIds,
      required this.sortOrder});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['unit_id'] = Variable<String>(unitId);
    map['name'] = Variable<String>(name);
    map['description'] = Variable<String>(description);
    map['type'] = Variable<String>(type);
    map['template'] = Variable<String>(template);
    map['prerequisite_lesson_ids'] = Variable<String>(prerequisiteLessonIds);
    map['sort_order'] = Variable<int>(sortOrder);
    return map;
  }

  LessonsCompanion toCompanion(bool nullToAbsent) {
    return LessonsCompanion(
      id: Value(id),
      unitId: Value(unitId),
      name: Value(name),
      description: Value(description),
      type: Value(type),
      template: Value(template),
      prerequisiteLessonIds: Value(prerequisiteLessonIds),
      sortOrder: Value(sortOrder),
    );
  }

  factory Lesson.fromJson(Map<String, dynamic> json,
      {ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return Lesson(
      id: serializer.fromJson<String>(json['id']),
      unitId: serializer.fromJson<String>(json['unitId']),
      name: serializer.fromJson<String>(json['name']),
      description: serializer.fromJson<String>(json['description']),
      type: serializer.fromJson<String>(json['type']),
      template: serializer.fromJson<String>(json['template']),
      prerequisiteLessonIds:
          serializer.fromJson<String>(json['prerequisiteLessonIds']),
      sortOrder: serializer.fromJson<int>(json['sortOrder']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'unitId': serializer.toJson<String>(unitId),
      'name': serializer.toJson<String>(name),
      'description': serializer.toJson<String>(description),
      'type': serializer.toJson<String>(type),
      'template': serializer.toJson<String>(template),
      'prerequisiteLessonIds': serializer.toJson<String>(prerequisiteLessonIds),
      'sortOrder': serializer.toJson<int>(sortOrder),
    };
  }

  Lesson copyWith(
          {String? id,
          String? unitId,
          String? name,
          String? description,
          String? type,
          String? template,
          String? prerequisiteLessonIds,
          int? sortOrder}) =>
      Lesson(
        id: id ?? this.id,
        unitId: unitId ?? this.unitId,
        name: name ?? this.name,
        description: description ?? this.description,
        type: type ?? this.type,
        template: template ?? this.template,
        prerequisiteLessonIds:
            prerequisiteLessonIds ?? this.prerequisiteLessonIds,
        sortOrder: sortOrder ?? this.sortOrder,
      );
  Lesson copyWithCompanion(LessonsCompanion data) {
    return Lesson(
      id: data.id.present ? data.id.value : this.id,
      unitId: data.unitId.present ? data.unitId.value : this.unitId,
      name: data.name.present ? data.name.value : this.name,
      description:
          data.description.present ? data.description.value : this.description,
      type: data.type.present ? data.type.value : this.type,
      template: data.template.present ? data.template.value : this.template,
      prerequisiteLessonIds: data.prerequisiteLessonIds.present
          ? data.prerequisiteLessonIds.value
          : this.prerequisiteLessonIds,
      sortOrder: data.sortOrder.present ? data.sortOrder.value : this.sortOrder,
    );
  }

  @override
  String toString() {
    return (StringBuffer('Lesson(')
          ..write('id: $id, ')
          ..write('unitId: $unitId, ')
          ..write('name: $name, ')
          ..write('description: $description, ')
          ..write('type: $type, ')
          ..write('template: $template, ')
          ..write('prerequisiteLessonIds: $prerequisiteLessonIds, ')
          ..write('sortOrder: $sortOrder')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(id, unitId, name, description, type, template,
      prerequisiteLessonIds, sortOrder);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is Lesson &&
          other.id == this.id &&
          other.unitId == this.unitId &&
          other.name == this.name &&
          other.description == this.description &&
          other.type == this.type &&
          other.template == this.template &&
          other.prerequisiteLessonIds == this.prerequisiteLessonIds &&
          other.sortOrder == this.sortOrder);
}

class LessonsCompanion extends UpdateCompanion<Lesson> {
  final Value<String> id;
  final Value<String> unitId;
  final Value<String> name;
  final Value<String> description;
  final Value<String> type;
  final Value<String> template;
  final Value<String> prerequisiteLessonIds;
  final Value<int> sortOrder;
  final Value<int> rowid;
  const LessonsCompanion({
    this.id = const Value.absent(),
    this.unitId = const Value.absent(),
    this.name = const Value.absent(),
    this.description = const Value.absent(),
    this.type = const Value.absent(),
    this.template = const Value.absent(),
    this.prerequisiteLessonIds = const Value.absent(),
    this.sortOrder = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  LessonsCompanion.insert({
    required String id,
    required String unitId,
    required String name,
    this.description = const Value.absent(),
    this.type = const Value.absent(),
    this.template = const Value.absent(),
    this.prerequisiteLessonIds = const Value.absent(),
    this.sortOrder = const Value.absent(),
    this.rowid = const Value.absent(),
  })  : id = Value(id),
        unitId = Value(unitId),
        name = Value(name);
  static Insertable<Lesson> custom({
    Expression<String>? id,
    Expression<String>? unitId,
    Expression<String>? name,
    Expression<String>? description,
    Expression<String>? type,
    Expression<String>? template,
    Expression<String>? prerequisiteLessonIds,
    Expression<int>? sortOrder,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (unitId != null) 'unit_id': unitId,
      if (name != null) 'name': name,
      if (description != null) 'description': description,
      if (type != null) 'type': type,
      if (template != null) 'template': template,
      if (prerequisiteLessonIds != null)
        'prerequisite_lesson_ids': prerequisiteLessonIds,
      if (sortOrder != null) 'sort_order': sortOrder,
      if (rowid != null) 'rowid': rowid,
    });
  }

  LessonsCompanion copyWith(
      {Value<String>? id,
      Value<String>? unitId,
      Value<String>? name,
      Value<String>? description,
      Value<String>? type,
      Value<String>? template,
      Value<String>? prerequisiteLessonIds,
      Value<int>? sortOrder,
      Value<int>? rowid}) {
    return LessonsCompanion(
      id: id ?? this.id,
      unitId: unitId ?? this.unitId,
      name: name ?? this.name,
      description: description ?? this.description,
      type: type ?? this.type,
      template: template ?? this.template,
      prerequisiteLessonIds:
          prerequisiteLessonIds ?? this.prerequisiteLessonIds,
      sortOrder: sortOrder ?? this.sortOrder,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (unitId.present) {
      map['unit_id'] = Variable<String>(unitId.value);
    }
    if (name.present) {
      map['name'] = Variable<String>(name.value);
    }
    if (description.present) {
      map['description'] = Variable<String>(description.value);
    }
    if (type.present) {
      map['type'] = Variable<String>(type.value);
    }
    if (template.present) {
      map['template'] = Variable<String>(template.value);
    }
    if (prerequisiteLessonIds.present) {
      map['prerequisite_lesson_ids'] =
          Variable<String>(prerequisiteLessonIds.value);
    }
    if (sortOrder.present) {
      map['sort_order'] = Variable<int>(sortOrder.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('LessonsCompanion(')
          ..write('id: $id, ')
          ..write('unitId: $unitId, ')
          ..write('name: $name, ')
          ..write('description: $description, ')
          ..write('type: $type, ')
          ..write('template: $template, ')
          ..write('prerequisiteLessonIds: $prerequisiteLessonIds, ')
          ..write('sortOrder: $sortOrder, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $LessonContentsTable extends LessonContents
    with TableInfo<$LessonContentsTable, LessonContent> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $LessonContentsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _lessonIdMeta =
      const VerificationMeta('lessonId');
  @override
  late final GeneratedColumn<String> lessonId = GeneratedColumn<String>(
      'lesson_id', aliasedName, false,
      type: DriftSqlType.string,
      requiredDuringInsert: true,
      $customConstraints: 'NOT NULL REFERENCES lessons(id) ON DELETE CASCADE');
  static const VerificationMeta _contentJsonMeta =
      const VerificationMeta('contentJson');
  @override
  late final GeneratedColumn<String> contentJson = GeneratedColumn<String>(
      'content_json', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  @override
  List<GeneratedColumn> get $columns => [lessonId, contentJson];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'lesson_contents';
  @override
  VerificationContext validateIntegrity(Insertable<LessonContent> instance,
      {bool isInserting = false}) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('lesson_id')) {
      context.handle(_lessonIdMeta,
          lessonId.isAcceptableOrUnknown(data['lesson_id']!, _lessonIdMeta));
    } else if (isInserting) {
      context.missing(_lessonIdMeta);
    }
    if (data.containsKey('content_json')) {
      context.handle(
          _contentJsonMeta,
          contentJson.isAcceptableOrUnknown(
              data['content_json']!, _contentJsonMeta));
    } else if (isInserting) {
      context.missing(_contentJsonMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {lessonId};
  @override
  LessonContent map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return LessonContent(
      lessonId: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}lesson_id'])!,
      contentJson: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}content_json'])!,
    );
  }

  @override
  $LessonContentsTable createAlias(String alias) {
    return $LessonContentsTable(attachedDatabase, alias);
  }
}

class LessonContent extends DataClass implements Insertable<LessonContent> {
  final String lessonId;
  final String contentJson;
  const LessonContent({required this.lessonId, required this.contentJson});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['lesson_id'] = Variable<String>(lessonId);
    map['content_json'] = Variable<String>(contentJson);
    return map;
  }

  LessonContentsCompanion toCompanion(bool nullToAbsent) {
    return LessonContentsCompanion(
      lessonId: Value(lessonId),
      contentJson: Value(contentJson),
    );
  }

  factory LessonContent.fromJson(Map<String, dynamic> json,
      {ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return LessonContent(
      lessonId: serializer.fromJson<String>(json['lessonId']),
      contentJson: serializer.fromJson<String>(json['contentJson']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'lessonId': serializer.toJson<String>(lessonId),
      'contentJson': serializer.toJson<String>(contentJson),
    };
  }

  LessonContent copyWith({String? lessonId, String? contentJson}) =>
      LessonContent(
        lessonId: lessonId ?? this.lessonId,
        contentJson: contentJson ?? this.contentJson,
      );
  LessonContent copyWithCompanion(LessonContentsCompanion data) {
    return LessonContent(
      lessonId: data.lessonId.present ? data.lessonId.value : this.lessonId,
      contentJson:
          data.contentJson.present ? data.contentJson.value : this.contentJson,
    );
  }

  @override
  String toString() {
    return (StringBuffer('LessonContent(')
          ..write('lessonId: $lessonId, ')
          ..write('contentJson: $contentJson')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(lessonId, contentJson);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is LessonContent &&
          other.lessonId == this.lessonId &&
          other.contentJson == this.contentJson);
}

class LessonContentsCompanion extends UpdateCompanion<LessonContent> {
  final Value<String> lessonId;
  final Value<String> contentJson;
  final Value<int> rowid;
  const LessonContentsCompanion({
    this.lessonId = const Value.absent(),
    this.contentJson = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  LessonContentsCompanion.insert({
    required String lessonId,
    required String contentJson,
    this.rowid = const Value.absent(),
  })  : lessonId = Value(lessonId),
        contentJson = Value(contentJson);
  static Insertable<LessonContent> custom({
    Expression<String>? lessonId,
    Expression<String>? contentJson,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (lessonId != null) 'lesson_id': lessonId,
      if (contentJson != null) 'content_json': contentJson,
      if (rowid != null) 'rowid': rowid,
    });
  }

  LessonContentsCompanion copyWith(
      {Value<String>? lessonId,
      Value<String>? contentJson,
      Value<int>? rowid}) {
    return LessonContentsCompanion(
      lessonId: lessonId ?? this.lessonId,
      contentJson: contentJson ?? this.contentJson,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (lessonId.present) {
      map['lesson_id'] = Variable<String>(lessonId.value);
    }
    if (contentJson.present) {
      map['content_json'] = Variable<String>(contentJson.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('LessonContentsCompanion(')
          ..write('lessonId: $lessonId, ')
          ..write('contentJson: $contentJson, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $VocabularyTable extends Vocabulary
    with TableInfo<$VocabularyTable, VocabularyData> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $VocabularyTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
      'id', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _termMeta = const VerificationMeta('term');
  @override
  late final GeneratedColumn<String> term = GeneratedColumn<String>(
      'term', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _translationMeta =
      const VerificationMeta('translation');
  @override
  late final GeneratedColumn<String> translation = GeneratedColumn<String>(
      'translation', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _pronunciationMeta =
      const VerificationMeta('pronunciation');
  @override
  late final GeneratedColumn<String> pronunciation = GeneratedColumn<String>(
      'pronunciation', aliasedName, true,
      type: DriftSqlType.string, requiredDuringInsert: false);
  static const VerificationMeta _audioAssetMeta =
      const VerificationMeta('audioAsset');
  @override
  late final GeneratedColumn<String> audioAsset = GeneratedColumn<String>(
      'audio_asset', aliasedName, true,
      type: DriftSqlType.string, requiredDuringInsert: false);
  static const VerificationMeta _tagsMeta = const VerificationMeta('tags');
  @override
  late final GeneratedColumn<String> tags = GeneratedColumn<String>(
      'tags', aliasedName, false,
      type: DriftSqlType.string,
      requiredDuringInsert: false,
      defaultValue: const Constant('[]'));
  @override
  List<GeneratedColumn> get $columns =>
      [id, term, translation, pronunciation, audioAsset, tags];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'vocabulary';
  @override
  VerificationContext validateIntegrity(Insertable<VocabularyData> instance,
      {bool isInserting = false}) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('term')) {
      context.handle(
          _termMeta, term.isAcceptableOrUnknown(data['term']!, _termMeta));
    } else if (isInserting) {
      context.missing(_termMeta);
    }
    if (data.containsKey('translation')) {
      context.handle(
          _translationMeta,
          translation.isAcceptableOrUnknown(
              data['translation']!, _translationMeta));
    } else if (isInserting) {
      context.missing(_translationMeta);
    }
    if (data.containsKey('pronunciation')) {
      context.handle(
          _pronunciationMeta,
          pronunciation.isAcceptableOrUnknown(
              data['pronunciation']!, _pronunciationMeta));
    }
    if (data.containsKey('audio_asset')) {
      context.handle(
          _audioAssetMeta,
          audioAsset.isAcceptableOrUnknown(
              data['audio_asset']!, _audioAssetMeta));
    }
    if (data.containsKey('tags')) {
      context.handle(
          _tagsMeta, tags.isAcceptableOrUnknown(data['tags']!, _tagsMeta));
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  VocabularyData map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return VocabularyData(
      id: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}id'])!,
      term: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}term'])!,
      translation: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}translation'])!,
      pronunciation: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}pronunciation']),
      audioAsset: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}audio_asset']),
      tags: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}tags'])!,
    );
  }

  @override
  $VocabularyTable createAlias(String alias) {
    return $VocabularyTable(attachedDatabase, alias);
  }
}

class VocabularyData extends DataClass implements Insertable<VocabularyData> {
  final String id;
  final String term;
  final String translation;
  final String? pronunciation;
  final String? audioAsset;
  final String tags;
  const VocabularyData(
      {required this.id,
      required this.term,
      required this.translation,
      this.pronunciation,
      this.audioAsset,
      required this.tags});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['term'] = Variable<String>(term);
    map['translation'] = Variable<String>(translation);
    if (!nullToAbsent || pronunciation != null) {
      map['pronunciation'] = Variable<String>(pronunciation);
    }
    if (!nullToAbsent || audioAsset != null) {
      map['audio_asset'] = Variable<String>(audioAsset);
    }
    map['tags'] = Variable<String>(tags);
    return map;
  }

  VocabularyCompanion toCompanion(bool nullToAbsent) {
    return VocabularyCompanion(
      id: Value(id),
      term: Value(term),
      translation: Value(translation),
      pronunciation: pronunciation == null && nullToAbsent
          ? const Value.absent()
          : Value(pronunciation),
      audioAsset: audioAsset == null && nullToAbsent
          ? const Value.absent()
          : Value(audioAsset),
      tags: Value(tags),
    );
  }

  factory VocabularyData.fromJson(Map<String, dynamic> json,
      {ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return VocabularyData(
      id: serializer.fromJson<String>(json['id']),
      term: serializer.fromJson<String>(json['term']),
      translation: serializer.fromJson<String>(json['translation']),
      pronunciation: serializer.fromJson<String?>(json['pronunciation']),
      audioAsset: serializer.fromJson<String?>(json['audioAsset']),
      tags: serializer.fromJson<String>(json['tags']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'term': serializer.toJson<String>(term),
      'translation': serializer.toJson<String>(translation),
      'pronunciation': serializer.toJson<String?>(pronunciation),
      'audioAsset': serializer.toJson<String?>(audioAsset),
      'tags': serializer.toJson<String>(tags),
    };
  }

  VocabularyData copyWith(
          {String? id,
          String? term,
          String? translation,
          Value<String?> pronunciation = const Value.absent(),
          Value<String?> audioAsset = const Value.absent(),
          String? tags}) =>
      VocabularyData(
        id: id ?? this.id,
        term: term ?? this.term,
        translation: translation ?? this.translation,
        pronunciation:
            pronunciation.present ? pronunciation.value : this.pronunciation,
        audioAsset: audioAsset.present ? audioAsset.value : this.audioAsset,
        tags: tags ?? this.tags,
      );
  VocabularyData copyWithCompanion(VocabularyCompanion data) {
    return VocabularyData(
      id: data.id.present ? data.id.value : this.id,
      term: data.term.present ? data.term.value : this.term,
      translation:
          data.translation.present ? data.translation.value : this.translation,
      pronunciation: data.pronunciation.present
          ? data.pronunciation.value
          : this.pronunciation,
      audioAsset:
          data.audioAsset.present ? data.audioAsset.value : this.audioAsset,
      tags: data.tags.present ? data.tags.value : this.tags,
    );
  }

  @override
  String toString() {
    return (StringBuffer('VocabularyData(')
          ..write('id: $id, ')
          ..write('term: $term, ')
          ..write('translation: $translation, ')
          ..write('pronunciation: $pronunciation, ')
          ..write('audioAsset: $audioAsset, ')
          ..write('tags: $tags')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode =>
      Object.hash(id, term, translation, pronunciation, audioAsset, tags);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is VocabularyData &&
          other.id == this.id &&
          other.term == this.term &&
          other.translation == this.translation &&
          other.pronunciation == this.pronunciation &&
          other.audioAsset == this.audioAsset &&
          other.tags == this.tags);
}

class VocabularyCompanion extends UpdateCompanion<VocabularyData> {
  final Value<String> id;
  final Value<String> term;
  final Value<String> translation;
  final Value<String?> pronunciation;
  final Value<String?> audioAsset;
  final Value<String> tags;
  final Value<int> rowid;
  const VocabularyCompanion({
    this.id = const Value.absent(),
    this.term = const Value.absent(),
    this.translation = const Value.absent(),
    this.pronunciation = const Value.absent(),
    this.audioAsset = const Value.absent(),
    this.tags = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  VocabularyCompanion.insert({
    required String id,
    required String term,
    required String translation,
    this.pronunciation = const Value.absent(),
    this.audioAsset = const Value.absent(),
    this.tags = const Value.absent(),
    this.rowid = const Value.absent(),
  })  : id = Value(id),
        term = Value(term),
        translation = Value(translation);
  static Insertable<VocabularyData> custom({
    Expression<String>? id,
    Expression<String>? term,
    Expression<String>? translation,
    Expression<String>? pronunciation,
    Expression<String>? audioAsset,
    Expression<String>? tags,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (term != null) 'term': term,
      if (translation != null) 'translation': translation,
      if (pronunciation != null) 'pronunciation': pronunciation,
      if (audioAsset != null) 'audio_asset': audioAsset,
      if (tags != null) 'tags': tags,
      if (rowid != null) 'rowid': rowid,
    });
  }

  VocabularyCompanion copyWith(
      {Value<String>? id,
      Value<String>? term,
      Value<String>? translation,
      Value<String?>? pronunciation,
      Value<String?>? audioAsset,
      Value<String>? tags,
      Value<int>? rowid}) {
    return VocabularyCompanion(
      id: id ?? this.id,
      term: term ?? this.term,
      translation: translation ?? this.translation,
      pronunciation: pronunciation ?? this.pronunciation,
      audioAsset: audioAsset ?? this.audioAsset,
      tags: tags ?? this.tags,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (term.present) {
      map['term'] = Variable<String>(term.value);
    }
    if (translation.present) {
      map['translation'] = Variable<String>(translation.value);
    }
    if (pronunciation.present) {
      map['pronunciation'] = Variable<String>(pronunciation.value);
    }
    if (audioAsset.present) {
      map['audio_asset'] = Variable<String>(audioAsset.value);
    }
    if (tags.present) {
      map['tags'] = Variable<String>(tags.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('VocabularyCompanion(')
          ..write('id: $id, ')
          ..write('term: $term, ')
          ..write('translation: $translation, ')
          ..write('pronunciation: $pronunciation, ')
          ..write('audioAsset: $audioAsset, ')
          ..write('tags: $tags, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $GrammarPointsTable extends GrammarPoints
    with TableInfo<$GrammarPointsTable, GrammarPoint> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $GrammarPointsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
      'id', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _titleMeta = const VerificationMeta('title');
  @override
  late final GeneratedColumn<String> title = GeneratedColumn<String>(
      'title', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _explanationMeta =
      const VerificationMeta('explanation');
  @override
  late final GeneratedColumn<String> explanation = GeneratedColumn<String>(
      'explanation', aliasedName, false,
      type: DriftSqlType.string,
      requiredDuringInsert: false,
      defaultValue: const Constant(''));
  static const VerificationMeta _exampleExpressionIdsMeta =
      const VerificationMeta('exampleExpressionIds');
  @override
  late final GeneratedColumn<String> exampleExpressionIds =
      GeneratedColumn<String>('example_expression_ids', aliasedName, false,
          type: DriftSqlType.string,
          requiredDuringInsert: false,
          defaultValue: const Constant('[]'));
  static const VerificationMeta _exampleSentenceIdsMeta =
      const VerificationMeta('exampleSentenceIds');
  @override
  late final GeneratedColumn<String> exampleSentenceIds =
      GeneratedColumn<String>('example_sentence_ids', aliasedName, false,
          type: DriftSqlType.string,
          requiredDuringInsert: false,
          defaultValue: const Constant('[]'));
  static const VerificationMeta _practiceItemsMeta =
      const VerificationMeta('practiceItems');
  @override
  late final GeneratedColumn<String> practiceItems = GeneratedColumn<String>(
      'practice_items', aliasedName, false,
      type: DriftSqlType.string,
      requiredDuringInsert: false,
      defaultValue: const Constant('[]'));
  @override
  List<GeneratedColumn> get $columns => [
        id,
        title,
        explanation,
        exampleExpressionIds,
        exampleSentenceIds,
        practiceItems
      ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'grammar_points';
  @override
  VerificationContext validateIntegrity(Insertable<GrammarPoint> instance,
      {bool isInserting = false}) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('title')) {
      context.handle(
          _titleMeta, title.isAcceptableOrUnknown(data['title']!, _titleMeta));
    } else if (isInserting) {
      context.missing(_titleMeta);
    }
    if (data.containsKey('explanation')) {
      context.handle(
          _explanationMeta,
          explanation.isAcceptableOrUnknown(
              data['explanation']!, _explanationMeta));
    }
    if (data.containsKey('example_expression_ids')) {
      context.handle(
          _exampleExpressionIdsMeta,
          exampleExpressionIds.isAcceptableOrUnknown(
              data['example_expression_ids']!, _exampleExpressionIdsMeta));
    }
    if (data.containsKey('example_sentence_ids')) {
      context.handle(
          _exampleSentenceIdsMeta,
          exampleSentenceIds.isAcceptableOrUnknown(
              data['example_sentence_ids']!, _exampleSentenceIdsMeta));
    }
    if (data.containsKey('practice_items')) {
      context.handle(
          _practiceItemsMeta,
          practiceItems.isAcceptableOrUnknown(
              data['practice_items']!, _practiceItemsMeta));
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  GrammarPoint map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return GrammarPoint(
      id: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}id'])!,
      title: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}title'])!,
      explanation: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}explanation'])!,
      exampleExpressionIds: attachedDatabase.typeMapping.read(
          DriftSqlType.string,
          data['${effectivePrefix}example_expression_ids'])!,
      exampleSentenceIds: attachedDatabase.typeMapping.read(
          DriftSqlType.string, data['${effectivePrefix}example_sentence_ids'])!,
      practiceItems: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}practice_items'])!,
    );
  }

  @override
  $GrammarPointsTable createAlias(String alias) {
    return $GrammarPointsTable(attachedDatabase, alias);
  }
}

class GrammarPoint extends DataClass implements Insertable<GrammarPoint> {
  final String id;
  final String title;
  final String explanation;
  final String exampleExpressionIds;
  final String exampleSentenceIds;
  final String practiceItems;
  const GrammarPoint(
      {required this.id,
      required this.title,
      required this.explanation,
      required this.exampleExpressionIds,
      required this.exampleSentenceIds,
      required this.practiceItems});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['title'] = Variable<String>(title);
    map['explanation'] = Variable<String>(explanation);
    map['example_expression_ids'] = Variable<String>(exampleExpressionIds);
    map['example_sentence_ids'] = Variable<String>(exampleSentenceIds);
    map['practice_items'] = Variable<String>(practiceItems);
    return map;
  }

  GrammarPointsCompanion toCompanion(bool nullToAbsent) {
    return GrammarPointsCompanion(
      id: Value(id),
      title: Value(title),
      explanation: Value(explanation),
      exampleExpressionIds: Value(exampleExpressionIds),
      exampleSentenceIds: Value(exampleSentenceIds),
      practiceItems: Value(practiceItems),
    );
  }

  factory GrammarPoint.fromJson(Map<String, dynamic> json,
      {ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return GrammarPoint(
      id: serializer.fromJson<String>(json['id']),
      title: serializer.fromJson<String>(json['title']),
      explanation: serializer.fromJson<String>(json['explanation']),
      exampleExpressionIds:
          serializer.fromJson<String>(json['exampleExpressionIds']),
      exampleSentenceIds:
          serializer.fromJson<String>(json['exampleSentenceIds']),
      practiceItems: serializer.fromJson<String>(json['practiceItems']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'title': serializer.toJson<String>(title),
      'explanation': serializer.toJson<String>(explanation),
      'exampleExpressionIds': serializer.toJson<String>(exampleExpressionIds),
      'exampleSentenceIds': serializer.toJson<String>(exampleSentenceIds),
      'practiceItems': serializer.toJson<String>(practiceItems),
    };
  }

  GrammarPoint copyWith(
          {String? id,
          String? title,
          String? explanation,
          String? exampleExpressionIds,
          String? exampleSentenceIds,
          String? practiceItems}) =>
      GrammarPoint(
        id: id ?? this.id,
        title: title ?? this.title,
        explanation: explanation ?? this.explanation,
        exampleExpressionIds: exampleExpressionIds ?? this.exampleExpressionIds,
        exampleSentenceIds: exampleSentenceIds ?? this.exampleSentenceIds,
        practiceItems: practiceItems ?? this.practiceItems,
      );
  GrammarPoint copyWithCompanion(GrammarPointsCompanion data) {
    return GrammarPoint(
      id: data.id.present ? data.id.value : this.id,
      title: data.title.present ? data.title.value : this.title,
      explanation:
          data.explanation.present ? data.explanation.value : this.explanation,
      exampleExpressionIds: data.exampleExpressionIds.present
          ? data.exampleExpressionIds.value
          : this.exampleExpressionIds,
      exampleSentenceIds: data.exampleSentenceIds.present
          ? data.exampleSentenceIds.value
          : this.exampleSentenceIds,
      practiceItems: data.practiceItems.present
          ? data.practiceItems.value
          : this.practiceItems,
    );
  }

  @override
  String toString() {
    return (StringBuffer('GrammarPoint(')
          ..write('id: $id, ')
          ..write('title: $title, ')
          ..write('explanation: $explanation, ')
          ..write('exampleExpressionIds: $exampleExpressionIds, ')
          ..write('exampleSentenceIds: $exampleSentenceIds, ')
          ..write('practiceItems: $practiceItems')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(id, title, explanation, exampleExpressionIds,
      exampleSentenceIds, practiceItems);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is GrammarPoint &&
          other.id == this.id &&
          other.title == this.title &&
          other.explanation == this.explanation &&
          other.exampleExpressionIds == this.exampleExpressionIds &&
          other.exampleSentenceIds == this.exampleSentenceIds &&
          other.practiceItems == this.practiceItems);
}

class GrammarPointsCompanion extends UpdateCompanion<GrammarPoint> {
  final Value<String> id;
  final Value<String> title;
  final Value<String> explanation;
  final Value<String> exampleExpressionIds;
  final Value<String> exampleSentenceIds;
  final Value<String> practiceItems;
  final Value<int> rowid;
  const GrammarPointsCompanion({
    this.id = const Value.absent(),
    this.title = const Value.absent(),
    this.explanation = const Value.absent(),
    this.exampleExpressionIds = const Value.absent(),
    this.exampleSentenceIds = const Value.absent(),
    this.practiceItems = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  GrammarPointsCompanion.insert({
    required String id,
    required String title,
    this.explanation = const Value.absent(),
    this.exampleExpressionIds = const Value.absent(),
    this.exampleSentenceIds = const Value.absent(),
    this.practiceItems = const Value.absent(),
    this.rowid = const Value.absent(),
  })  : id = Value(id),
        title = Value(title);
  static Insertable<GrammarPoint> custom({
    Expression<String>? id,
    Expression<String>? title,
    Expression<String>? explanation,
    Expression<String>? exampleExpressionIds,
    Expression<String>? exampleSentenceIds,
    Expression<String>? practiceItems,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (title != null) 'title': title,
      if (explanation != null) 'explanation': explanation,
      if (exampleExpressionIds != null)
        'example_expression_ids': exampleExpressionIds,
      if (exampleSentenceIds != null)
        'example_sentence_ids': exampleSentenceIds,
      if (practiceItems != null) 'practice_items': practiceItems,
      if (rowid != null) 'rowid': rowid,
    });
  }

  GrammarPointsCompanion copyWith(
      {Value<String>? id,
      Value<String>? title,
      Value<String>? explanation,
      Value<String>? exampleExpressionIds,
      Value<String>? exampleSentenceIds,
      Value<String>? practiceItems,
      Value<int>? rowid}) {
    return GrammarPointsCompanion(
      id: id ?? this.id,
      title: title ?? this.title,
      explanation: explanation ?? this.explanation,
      exampleExpressionIds: exampleExpressionIds ?? this.exampleExpressionIds,
      exampleSentenceIds: exampleSentenceIds ?? this.exampleSentenceIds,
      practiceItems: practiceItems ?? this.practiceItems,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (title.present) {
      map['title'] = Variable<String>(title.value);
    }
    if (explanation.present) {
      map['explanation'] = Variable<String>(explanation.value);
    }
    if (exampleExpressionIds.present) {
      map['example_expression_ids'] =
          Variable<String>(exampleExpressionIds.value);
    }
    if (exampleSentenceIds.present) {
      map['example_sentence_ids'] = Variable<String>(exampleSentenceIds.value);
    }
    if (practiceItems.present) {
      map['practice_items'] = Variable<String>(practiceItems.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('GrammarPointsCompanion(')
          ..write('id: $id, ')
          ..write('title: $title, ')
          ..write('explanation: $explanation, ')
          ..write('exampleExpressionIds: $exampleExpressionIds, ')
          ..write('exampleSentenceIds: $exampleSentenceIds, ')
          ..write('practiceItems: $practiceItems, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $CourseMetaTable extends CourseMeta
    with TableInfo<$CourseMetaTable, CourseMetaData> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $CourseMetaTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _keyMeta = const VerificationMeta('key');
  @override
  late final GeneratedColumn<String> key = GeneratedColumn<String>(
      'key', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _valueMeta = const VerificationMeta('value');
  @override
  late final GeneratedColumn<String> value = GeneratedColumn<String>(
      'value', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  @override
  List<GeneratedColumn> get $columns => [key, value];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'course_meta';
  @override
  VerificationContext validateIntegrity(Insertable<CourseMetaData> instance,
      {bool isInserting = false}) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('key')) {
      context.handle(
          _keyMeta, key.isAcceptableOrUnknown(data['key']!, _keyMeta));
    } else if (isInserting) {
      context.missing(_keyMeta);
    }
    if (data.containsKey('value')) {
      context.handle(
          _valueMeta, value.isAcceptableOrUnknown(data['value']!, _valueMeta));
    } else if (isInserting) {
      context.missing(_valueMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {key};
  @override
  CourseMetaData map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return CourseMetaData(
      key: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}key'])!,
      value: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}value'])!,
    );
  }

  @override
  $CourseMetaTable createAlias(String alias) {
    return $CourseMetaTable(attachedDatabase, alias);
  }
}

class CourseMetaData extends DataClass implements Insertable<CourseMetaData> {
  final String key;
  final String value;
  const CourseMetaData({required this.key, required this.value});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['key'] = Variable<String>(key);
    map['value'] = Variable<String>(value);
    return map;
  }

  CourseMetaCompanion toCompanion(bool nullToAbsent) {
    return CourseMetaCompanion(
      key: Value(key),
      value: Value(value),
    );
  }

  factory CourseMetaData.fromJson(Map<String, dynamic> json,
      {ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return CourseMetaData(
      key: serializer.fromJson<String>(json['key']),
      value: serializer.fromJson<String>(json['value']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'key': serializer.toJson<String>(key),
      'value': serializer.toJson<String>(value),
    };
  }

  CourseMetaData copyWith({String? key, String? value}) => CourseMetaData(
        key: key ?? this.key,
        value: value ?? this.value,
      );
  CourseMetaData copyWithCompanion(CourseMetaCompanion data) {
    return CourseMetaData(
      key: data.key.present ? data.key.value : this.key,
      value: data.value.present ? data.value.value : this.value,
    );
  }

  @override
  String toString() {
    return (StringBuffer('CourseMetaData(')
          ..write('key: $key, ')
          ..write('value: $value')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(key, value);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is CourseMetaData &&
          other.key == this.key &&
          other.value == this.value);
}

class CourseMetaCompanion extends UpdateCompanion<CourseMetaData> {
  final Value<String> key;
  final Value<String> value;
  final Value<int> rowid;
  const CourseMetaCompanion({
    this.key = const Value.absent(),
    this.value = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  CourseMetaCompanion.insert({
    required String key,
    required String value,
    this.rowid = const Value.absent(),
  })  : key = Value(key),
        value = Value(value);
  static Insertable<CourseMetaData> custom({
    Expression<String>? key,
    Expression<String>? value,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (key != null) 'key': key,
      if (value != null) 'value': value,
      if (rowid != null) 'rowid': rowid,
    });
  }

  CourseMetaCompanion copyWith(
      {Value<String>? key, Value<String>? value, Value<int>? rowid}) {
    return CourseMetaCompanion(
      key: key ?? this.key,
      value: value ?? this.value,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (key.present) {
      map['key'] = Variable<String>(key.value);
    }
    if (value.present) {
      map['value'] = Variable<String>(value.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('CourseMetaCompanion(')
          ..write('key: $key, ')
          ..write('value: $value, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $ExpressionsTable extends Expressions
    with TableInfo<$ExpressionsTable, ExpressionEntry> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $ExpressionsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
      'id', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _termMeta = const VerificationMeta('term');
  @override
  late final GeneratedColumn<String> term = GeneratedColumn<String>(
      'term', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _translationMeta =
      const VerificationMeta('translation');
  @override
  late final GeneratedColumn<String> translation = GeneratedColumn<String>(
      'translation', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _pronunciationMeta =
      const VerificationMeta('pronunciation');
  @override
  late final GeneratedColumn<String> pronunciation = GeneratedColumn<String>(
      'pronunciation', aliasedName, true,
      type: DriftSqlType.string, requiredDuringInsert: false);
  static const VerificationMeta _audioAssetMeta =
      const VerificationMeta('audioAsset');
  @override
  late final GeneratedColumn<String> audioAsset = GeneratedColumn<String>(
      'audio_asset', aliasedName, true,
      type: DriftSqlType.string, requiredDuringInsert: false);
  static const VerificationMeta _tagsMeta = const VerificationMeta('tags');
  @override
  late final GeneratedColumn<String> tags = GeneratedColumn<String>(
      'tags', aliasedName, false,
      type: DriftSqlType.string,
      requiredDuringInsert: false,
      defaultValue: const Constant('[]'));
  @override
  List<GeneratedColumn> get $columns =>
      [id, term, translation, pronunciation, audioAsset, tags];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'expressions';
  @override
  VerificationContext validateIntegrity(Insertable<ExpressionEntry> instance,
      {bool isInserting = false}) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('term')) {
      context.handle(
          _termMeta, term.isAcceptableOrUnknown(data['term']!, _termMeta));
    } else if (isInserting) {
      context.missing(_termMeta);
    }
    if (data.containsKey('translation')) {
      context.handle(
          _translationMeta,
          translation.isAcceptableOrUnknown(
              data['translation']!, _translationMeta));
    } else if (isInserting) {
      context.missing(_translationMeta);
    }
    if (data.containsKey('pronunciation')) {
      context.handle(
          _pronunciationMeta,
          pronunciation.isAcceptableOrUnknown(
              data['pronunciation']!, _pronunciationMeta));
    }
    if (data.containsKey('audio_asset')) {
      context.handle(
          _audioAssetMeta,
          audioAsset.isAcceptableOrUnknown(
              data['audio_asset']!, _audioAssetMeta));
    }
    if (data.containsKey('tags')) {
      context.handle(
          _tagsMeta, tags.isAcceptableOrUnknown(data['tags']!, _tagsMeta));
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  ExpressionEntry map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return ExpressionEntry(
      id: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}id'])!,
      term: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}term'])!,
      translation: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}translation'])!,
      pronunciation: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}pronunciation']),
      audioAsset: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}audio_asset']),
      tags: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}tags'])!,
    );
  }

  @override
  $ExpressionsTable createAlias(String alias) {
    return $ExpressionsTable(attachedDatabase, alias);
  }
}

class ExpressionEntry extends DataClass implements Insertable<ExpressionEntry> {
  final String id;
  final String term;
  final String translation;
  final String? pronunciation;
  final String? audioAsset;
  final String tags;
  const ExpressionEntry(
      {required this.id,
      required this.term,
      required this.translation,
      this.pronunciation,
      this.audioAsset,
      required this.tags});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['term'] = Variable<String>(term);
    map['translation'] = Variable<String>(translation);
    if (!nullToAbsent || pronunciation != null) {
      map['pronunciation'] = Variable<String>(pronunciation);
    }
    if (!nullToAbsent || audioAsset != null) {
      map['audio_asset'] = Variable<String>(audioAsset);
    }
    map['tags'] = Variable<String>(tags);
    return map;
  }

  ExpressionsCompanion toCompanion(bool nullToAbsent) {
    return ExpressionsCompanion(
      id: Value(id),
      term: Value(term),
      translation: Value(translation),
      pronunciation: pronunciation == null && nullToAbsent
          ? const Value.absent()
          : Value(pronunciation),
      audioAsset: audioAsset == null && nullToAbsent
          ? const Value.absent()
          : Value(audioAsset),
      tags: Value(tags),
    );
  }

  factory ExpressionEntry.fromJson(Map<String, dynamic> json,
      {ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return ExpressionEntry(
      id: serializer.fromJson<String>(json['id']),
      term: serializer.fromJson<String>(json['term']),
      translation: serializer.fromJson<String>(json['translation']),
      pronunciation: serializer.fromJson<String?>(json['pronunciation']),
      audioAsset: serializer.fromJson<String?>(json['audioAsset']),
      tags: serializer.fromJson<String>(json['tags']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'term': serializer.toJson<String>(term),
      'translation': serializer.toJson<String>(translation),
      'pronunciation': serializer.toJson<String?>(pronunciation),
      'audioAsset': serializer.toJson<String?>(audioAsset),
      'tags': serializer.toJson<String>(tags),
    };
  }

  ExpressionEntry copyWith(
          {String? id,
          String? term,
          String? translation,
          Value<String?> pronunciation = const Value.absent(),
          Value<String?> audioAsset = const Value.absent(),
          String? tags}) =>
      ExpressionEntry(
        id: id ?? this.id,
        term: term ?? this.term,
        translation: translation ?? this.translation,
        pronunciation:
            pronunciation.present ? pronunciation.value : this.pronunciation,
        audioAsset: audioAsset.present ? audioAsset.value : this.audioAsset,
        tags: tags ?? this.tags,
      );
  ExpressionEntry copyWithCompanion(ExpressionsCompanion data) {
    return ExpressionEntry(
      id: data.id.present ? data.id.value : this.id,
      term: data.term.present ? data.term.value : this.term,
      translation:
          data.translation.present ? data.translation.value : this.translation,
      pronunciation: data.pronunciation.present
          ? data.pronunciation.value
          : this.pronunciation,
      audioAsset:
          data.audioAsset.present ? data.audioAsset.value : this.audioAsset,
      tags: data.tags.present ? data.tags.value : this.tags,
    );
  }

  @override
  String toString() {
    return (StringBuffer('ExpressionEntry(')
          ..write('id: $id, ')
          ..write('term: $term, ')
          ..write('translation: $translation, ')
          ..write('pronunciation: $pronunciation, ')
          ..write('audioAsset: $audioAsset, ')
          ..write('tags: $tags')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode =>
      Object.hash(id, term, translation, pronunciation, audioAsset, tags);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is ExpressionEntry &&
          other.id == this.id &&
          other.term == this.term &&
          other.translation == this.translation &&
          other.pronunciation == this.pronunciation &&
          other.audioAsset == this.audioAsset &&
          other.tags == this.tags);
}

class ExpressionsCompanion extends UpdateCompanion<ExpressionEntry> {
  final Value<String> id;
  final Value<String> term;
  final Value<String> translation;
  final Value<String?> pronunciation;
  final Value<String?> audioAsset;
  final Value<String> tags;
  final Value<int> rowid;
  const ExpressionsCompanion({
    this.id = const Value.absent(),
    this.term = const Value.absent(),
    this.translation = const Value.absent(),
    this.pronunciation = const Value.absent(),
    this.audioAsset = const Value.absent(),
    this.tags = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  ExpressionsCompanion.insert({
    required String id,
    required String term,
    required String translation,
    this.pronunciation = const Value.absent(),
    this.audioAsset = const Value.absent(),
    this.tags = const Value.absent(),
    this.rowid = const Value.absent(),
  })  : id = Value(id),
        term = Value(term),
        translation = Value(translation);
  static Insertable<ExpressionEntry> custom({
    Expression<String>? id,
    Expression<String>? term,
    Expression<String>? translation,
    Expression<String>? pronunciation,
    Expression<String>? audioAsset,
    Expression<String>? tags,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (term != null) 'term': term,
      if (translation != null) 'translation': translation,
      if (pronunciation != null) 'pronunciation': pronunciation,
      if (audioAsset != null) 'audio_asset': audioAsset,
      if (tags != null) 'tags': tags,
      if (rowid != null) 'rowid': rowid,
    });
  }

  ExpressionsCompanion copyWith(
      {Value<String>? id,
      Value<String>? term,
      Value<String>? translation,
      Value<String?>? pronunciation,
      Value<String?>? audioAsset,
      Value<String>? tags,
      Value<int>? rowid}) {
    return ExpressionsCompanion(
      id: id ?? this.id,
      term: term ?? this.term,
      translation: translation ?? this.translation,
      pronunciation: pronunciation ?? this.pronunciation,
      audioAsset: audioAsset ?? this.audioAsset,
      tags: tags ?? this.tags,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (term.present) {
      map['term'] = Variable<String>(term.value);
    }
    if (translation.present) {
      map['translation'] = Variable<String>(translation.value);
    }
    if (pronunciation.present) {
      map['pronunciation'] = Variable<String>(pronunciation.value);
    }
    if (audioAsset.present) {
      map['audio_asset'] = Variable<String>(audioAsset.value);
    }
    if (tags.present) {
      map['tags'] = Variable<String>(tags.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('ExpressionsCompanion(')
          ..write('id: $id, ')
          ..write('term: $term, ')
          ..write('translation: $translation, ')
          ..write('pronunciation: $pronunciation, ')
          ..write('audioAsset: $audioAsset, ')
          ..write('tags: $tags, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

abstract class _$CourseDatabase extends GeneratedDatabase {
  _$CourseDatabase(QueryExecutor e) : super(e);
  $CourseDatabaseManager get managers => $CourseDatabaseManager(this);
  late final $SectionsTable sections = $SectionsTable(this);
  late final $UnitsTable units = $UnitsTable(this);
  late final $LessonsTable lessons = $LessonsTable(this);
  late final $LessonContentsTable lessonContents = $LessonContentsTable(this);
  late final $VocabularyTable vocabulary = $VocabularyTable(this);
  late final $GrammarPointsTable grammarPoints = $GrammarPointsTable(this);
  late final $CourseMetaTable courseMeta = $CourseMetaTable(this);
  late final $ExpressionsTable expressions = $ExpressionsTable(this);
  @override
  Iterable<TableInfo<Table, Object?>> get allTables =>
      allSchemaEntities.whereType<TableInfo<Table, Object?>>();
  @override
  List<DatabaseSchemaEntity> get allSchemaEntities => [
        sections,
        units,
        lessons,
        lessonContents,
        vocabulary,
        grammarPoints,
        courseMeta,
        expressions
      ];
  @override
  StreamQueryUpdateRules get streamUpdateRules => const StreamQueryUpdateRules(
        [
          WritePropagation(
            on: TableUpdateQuery.onTableName('sections',
                limitUpdateKind: UpdateKind.delete),
            result: [
              TableUpdate('units', kind: UpdateKind.delete),
            ],
          ),
          WritePropagation(
            on: TableUpdateQuery.onTableName('units',
                limitUpdateKind: UpdateKind.delete),
            result: [
              TableUpdate('lessons', kind: UpdateKind.delete),
            ],
          ),
          WritePropagation(
            on: TableUpdateQuery.onTableName('lessons',
                limitUpdateKind: UpdateKind.delete),
            result: [
              TableUpdate('lesson_contents', kind: UpdateKind.delete),
            ],
          ),
        ],
      );
}

typedef $$SectionsTableCreateCompanionBuilder = SectionsCompanion Function({
  required String id,
  required String name,
  Value<String> description,
  Value<String> prerequisiteSectionIds,
  Value<int> sortOrder,
  Value<int> rowid,
});
typedef $$SectionsTableUpdateCompanionBuilder = SectionsCompanion Function({
  Value<String> id,
  Value<String> name,
  Value<String> description,
  Value<String> prerequisiteSectionIds,
  Value<int> sortOrder,
  Value<int> rowid,
});

final class $$SectionsTableReferences
    extends BaseReferences<_$CourseDatabase, $SectionsTable, Section> {
  $$SectionsTableReferences(super.$_db, super.$_table, super.$_typedResult);

  static MultiTypedResultKey<$UnitsTable, List<Unit>> _unitsRefsTable(
          _$CourseDatabase db) =>
      MultiTypedResultKey.fromTable(db.units,
          aliasName: $_aliasNameGenerator(db.sections.id, db.units.sectionId));

  $$UnitsTableProcessedTableManager get unitsRefs {
    final manager = $$UnitsTableTableManager($_db, $_db.units)
        .filter((f) => f.sectionId.id($_item.id));

    final cache = $_typedResult.readTableOrNull(_unitsRefsTable($_db));
    return ProcessedTableManager(
        manager.$state.copyWith(prefetchedData: cache));
  }
}

class $$SectionsTableFilterComposer
    extends Composer<_$CourseDatabase, $SectionsTable> {
  $$SectionsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
      column: $table.id, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get name => $composableBuilder(
      column: $table.name, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get description => $composableBuilder(
      column: $table.description, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get prerequisiteSectionIds => $composableBuilder(
      column: $table.prerequisiteSectionIds,
      builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get sortOrder => $composableBuilder(
      column: $table.sortOrder, builder: (column) => ColumnFilters(column));

  Expression<bool> unitsRefs(
      Expression<bool> Function($$UnitsTableFilterComposer f) f) {
    final $$UnitsTableFilterComposer composer = $composerBuilder(
        composer: this,
        getCurrentColumn: (t) => t.id,
        referencedTable: $db.units,
        getReferencedColumn: (t) => t.sectionId,
        builder: (joinBuilder,
                {$addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer}) =>
            $$UnitsTableFilterComposer(
              $db: $db,
              $table: $db.units,
              $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
              joinBuilder: joinBuilder,
              $removeJoinBuilderFromRootComposer:
                  $removeJoinBuilderFromRootComposer,
            ));
    return f(composer);
  }
}

class $$SectionsTableOrderingComposer
    extends Composer<_$CourseDatabase, $SectionsTable> {
  $$SectionsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
      column: $table.id, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get name => $composableBuilder(
      column: $table.name, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get description => $composableBuilder(
      column: $table.description, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get prerequisiteSectionIds => $composableBuilder(
      column: $table.prerequisiteSectionIds,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get sortOrder => $composableBuilder(
      column: $table.sortOrder, builder: (column) => ColumnOrderings(column));
}

class $$SectionsTableAnnotationComposer
    extends Composer<_$CourseDatabase, $SectionsTable> {
  $$SectionsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get name =>
      $composableBuilder(column: $table.name, builder: (column) => column);

  GeneratedColumn<String> get description => $composableBuilder(
      column: $table.description, builder: (column) => column);

  GeneratedColumn<String> get prerequisiteSectionIds => $composableBuilder(
      column: $table.prerequisiteSectionIds, builder: (column) => column);

  GeneratedColumn<int> get sortOrder =>
      $composableBuilder(column: $table.sortOrder, builder: (column) => column);

  Expression<T> unitsRefs<T extends Object>(
      Expression<T> Function($$UnitsTableAnnotationComposer a) f) {
    final $$UnitsTableAnnotationComposer composer = $composerBuilder(
        composer: this,
        getCurrentColumn: (t) => t.id,
        referencedTable: $db.units,
        getReferencedColumn: (t) => t.sectionId,
        builder: (joinBuilder,
                {$addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer}) =>
            $$UnitsTableAnnotationComposer(
              $db: $db,
              $table: $db.units,
              $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
              joinBuilder: joinBuilder,
              $removeJoinBuilderFromRootComposer:
                  $removeJoinBuilderFromRootComposer,
            ));
    return f(composer);
  }
}

class $$SectionsTableTableManager extends RootTableManager<
    _$CourseDatabase,
    $SectionsTable,
    Section,
    $$SectionsTableFilterComposer,
    $$SectionsTableOrderingComposer,
    $$SectionsTableAnnotationComposer,
    $$SectionsTableCreateCompanionBuilder,
    $$SectionsTableUpdateCompanionBuilder,
    (Section, $$SectionsTableReferences),
    Section,
    PrefetchHooks Function({bool unitsRefs})> {
  $$SectionsTableTableManager(_$CourseDatabase db, $SectionsTable table)
      : super(TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$SectionsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$SectionsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$SectionsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback: ({
            Value<String> id = const Value.absent(),
            Value<String> name = const Value.absent(),
            Value<String> description = const Value.absent(),
            Value<String> prerequisiteSectionIds = const Value.absent(),
            Value<int> sortOrder = const Value.absent(),
            Value<int> rowid = const Value.absent(),
          }) =>
              SectionsCompanion(
            id: id,
            name: name,
            description: description,
            prerequisiteSectionIds: prerequisiteSectionIds,
            sortOrder: sortOrder,
            rowid: rowid,
          ),
          createCompanionCallback: ({
            required String id,
            required String name,
            Value<String> description = const Value.absent(),
            Value<String> prerequisiteSectionIds = const Value.absent(),
            Value<int> sortOrder = const Value.absent(),
            Value<int> rowid = const Value.absent(),
          }) =>
              SectionsCompanion.insert(
            id: id,
            name: name,
            description: description,
            prerequisiteSectionIds: prerequisiteSectionIds,
            sortOrder: sortOrder,
            rowid: rowid,
          ),
          withReferenceMapper: (p0) => p0
              .map((e) =>
                  (e.readTable(table), $$SectionsTableReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: ({unitsRefs = false}) {
            return PrefetchHooks(
              db: db,
              explicitlyWatchedTables: [if (unitsRefs) db.units],
              addJoins: null,
              getPrefetchedDataCallback: (items) async {
                return [
                  if (unitsRefs)
                    await $_getPrefetchedData(
                        currentTable: table,
                        referencedTable:
                            $$SectionsTableReferences._unitsRefsTable(db),
                        managerFromTypedResult: (p0) =>
                            $$SectionsTableReferences(db, table, p0).unitsRefs,
                        referencedItemsForCurrentItem:
                            (item, referencedItems) => referencedItems
                                .where((e) => e.sectionId == item.id),
                        typedResults: items)
                ];
              },
            );
          },
        ));
}

typedef $$SectionsTableProcessedTableManager = ProcessedTableManager<
    _$CourseDatabase,
    $SectionsTable,
    Section,
    $$SectionsTableFilterComposer,
    $$SectionsTableOrderingComposer,
    $$SectionsTableAnnotationComposer,
    $$SectionsTableCreateCompanionBuilder,
    $$SectionsTableUpdateCompanionBuilder,
    (Section, $$SectionsTableReferences),
    Section,
    PrefetchHooks Function({bool unitsRefs})>;
typedef $$UnitsTableCreateCompanionBuilder = UnitsCompanion Function({
  required String id,
  required String sectionId,
  required String name,
  Value<String> description,
  Value<String> prerequisiteUnitIds,
  Value<int> sortOrder,
  Value<int> rowid,
});
typedef $$UnitsTableUpdateCompanionBuilder = UnitsCompanion Function({
  Value<String> id,
  Value<String> sectionId,
  Value<String> name,
  Value<String> description,
  Value<String> prerequisiteUnitIds,
  Value<int> sortOrder,
  Value<int> rowid,
});

final class $$UnitsTableReferences
    extends BaseReferences<_$CourseDatabase, $UnitsTable, Unit> {
  $$UnitsTableReferences(super.$_db, super.$_table, super.$_typedResult);

  static $SectionsTable _sectionIdTable(_$CourseDatabase db) => db.sections
      .createAlias($_aliasNameGenerator(db.units.sectionId, db.sections.id));

  $$SectionsTableProcessedTableManager? get sectionId {
    if ($_item.sectionId == null) return null;
    final manager = $$SectionsTableTableManager($_db, $_db.sections)
        .filter((f) => f.id($_item.sectionId!));
    final item = $_typedResult.readTableOrNull(_sectionIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
        manager.$state.copyWith(prefetchedData: [item]));
  }

  static MultiTypedResultKey<$LessonsTable, List<Lesson>> _lessonsRefsTable(
          _$CourseDatabase db) =>
      MultiTypedResultKey.fromTable(db.lessons,
          aliasName: $_aliasNameGenerator(db.units.id, db.lessons.unitId));

  $$LessonsTableProcessedTableManager get lessonsRefs {
    final manager = $$LessonsTableTableManager($_db, $_db.lessons)
        .filter((f) => f.unitId.id($_item.id));

    final cache = $_typedResult.readTableOrNull(_lessonsRefsTable($_db));
    return ProcessedTableManager(
        manager.$state.copyWith(prefetchedData: cache));
  }
}

class $$UnitsTableFilterComposer
    extends Composer<_$CourseDatabase, $UnitsTable> {
  $$UnitsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
      column: $table.id, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get name => $composableBuilder(
      column: $table.name, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get description => $composableBuilder(
      column: $table.description, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get prerequisiteUnitIds => $composableBuilder(
      column: $table.prerequisiteUnitIds,
      builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get sortOrder => $composableBuilder(
      column: $table.sortOrder, builder: (column) => ColumnFilters(column));

  $$SectionsTableFilterComposer get sectionId {
    final $$SectionsTableFilterComposer composer = $composerBuilder(
        composer: this,
        getCurrentColumn: (t) => t.sectionId,
        referencedTable: $db.sections,
        getReferencedColumn: (t) => t.id,
        builder: (joinBuilder,
                {$addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer}) =>
            $$SectionsTableFilterComposer(
              $db: $db,
              $table: $db.sections,
              $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
              joinBuilder: joinBuilder,
              $removeJoinBuilderFromRootComposer:
                  $removeJoinBuilderFromRootComposer,
            ));
    return composer;
  }

  Expression<bool> lessonsRefs(
      Expression<bool> Function($$LessonsTableFilterComposer f) f) {
    final $$LessonsTableFilterComposer composer = $composerBuilder(
        composer: this,
        getCurrentColumn: (t) => t.id,
        referencedTable: $db.lessons,
        getReferencedColumn: (t) => t.unitId,
        builder: (joinBuilder,
                {$addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer}) =>
            $$LessonsTableFilterComposer(
              $db: $db,
              $table: $db.lessons,
              $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
              joinBuilder: joinBuilder,
              $removeJoinBuilderFromRootComposer:
                  $removeJoinBuilderFromRootComposer,
            ));
    return f(composer);
  }
}

class $$UnitsTableOrderingComposer
    extends Composer<_$CourseDatabase, $UnitsTable> {
  $$UnitsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
      column: $table.id, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get name => $composableBuilder(
      column: $table.name, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get description => $composableBuilder(
      column: $table.description, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get prerequisiteUnitIds => $composableBuilder(
      column: $table.prerequisiteUnitIds,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get sortOrder => $composableBuilder(
      column: $table.sortOrder, builder: (column) => ColumnOrderings(column));

  $$SectionsTableOrderingComposer get sectionId {
    final $$SectionsTableOrderingComposer composer = $composerBuilder(
        composer: this,
        getCurrentColumn: (t) => t.sectionId,
        referencedTable: $db.sections,
        getReferencedColumn: (t) => t.id,
        builder: (joinBuilder,
                {$addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer}) =>
            $$SectionsTableOrderingComposer(
              $db: $db,
              $table: $db.sections,
              $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
              joinBuilder: joinBuilder,
              $removeJoinBuilderFromRootComposer:
                  $removeJoinBuilderFromRootComposer,
            ));
    return composer;
  }
}

class $$UnitsTableAnnotationComposer
    extends Composer<_$CourseDatabase, $UnitsTable> {
  $$UnitsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get name =>
      $composableBuilder(column: $table.name, builder: (column) => column);

  GeneratedColumn<String> get description => $composableBuilder(
      column: $table.description, builder: (column) => column);

  GeneratedColumn<String> get prerequisiteUnitIds => $composableBuilder(
      column: $table.prerequisiteUnitIds, builder: (column) => column);

  GeneratedColumn<int> get sortOrder =>
      $composableBuilder(column: $table.sortOrder, builder: (column) => column);

  $$SectionsTableAnnotationComposer get sectionId {
    final $$SectionsTableAnnotationComposer composer = $composerBuilder(
        composer: this,
        getCurrentColumn: (t) => t.sectionId,
        referencedTable: $db.sections,
        getReferencedColumn: (t) => t.id,
        builder: (joinBuilder,
                {$addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer}) =>
            $$SectionsTableAnnotationComposer(
              $db: $db,
              $table: $db.sections,
              $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
              joinBuilder: joinBuilder,
              $removeJoinBuilderFromRootComposer:
                  $removeJoinBuilderFromRootComposer,
            ));
    return composer;
  }

  Expression<T> lessonsRefs<T extends Object>(
      Expression<T> Function($$LessonsTableAnnotationComposer a) f) {
    final $$LessonsTableAnnotationComposer composer = $composerBuilder(
        composer: this,
        getCurrentColumn: (t) => t.id,
        referencedTable: $db.lessons,
        getReferencedColumn: (t) => t.unitId,
        builder: (joinBuilder,
                {$addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer}) =>
            $$LessonsTableAnnotationComposer(
              $db: $db,
              $table: $db.lessons,
              $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
              joinBuilder: joinBuilder,
              $removeJoinBuilderFromRootComposer:
                  $removeJoinBuilderFromRootComposer,
            ));
    return f(composer);
  }
}

class $$UnitsTableTableManager extends RootTableManager<
    _$CourseDatabase,
    $UnitsTable,
    Unit,
    $$UnitsTableFilterComposer,
    $$UnitsTableOrderingComposer,
    $$UnitsTableAnnotationComposer,
    $$UnitsTableCreateCompanionBuilder,
    $$UnitsTableUpdateCompanionBuilder,
    (Unit, $$UnitsTableReferences),
    Unit,
    PrefetchHooks Function({bool sectionId, bool lessonsRefs})> {
  $$UnitsTableTableManager(_$CourseDatabase db, $UnitsTable table)
      : super(TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$UnitsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$UnitsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$UnitsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback: ({
            Value<String> id = const Value.absent(),
            Value<String> sectionId = const Value.absent(),
            Value<String> name = const Value.absent(),
            Value<String> description = const Value.absent(),
            Value<String> prerequisiteUnitIds = const Value.absent(),
            Value<int> sortOrder = const Value.absent(),
            Value<int> rowid = const Value.absent(),
          }) =>
              UnitsCompanion(
            id: id,
            sectionId: sectionId,
            name: name,
            description: description,
            prerequisiteUnitIds: prerequisiteUnitIds,
            sortOrder: sortOrder,
            rowid: rowid,
          ),
          createCompanionCallback: ({
            required String id,
            required String sectionId,
            required String name,
            Value<String> description = const Value.absent(),
            Value<String> prerequisiteUnitIds = const Value.absent(),
            Value<int> sortOrder = const Value.absent(),
            Value<int> rowid = const Value.absent(),
          }) =>
              UnitsCompanion.insert(
            id: id,
            sectionId: sectionId,
            name: name,
            description: description,
            prerequisiteUnitIds: prerequisiteUnitIds,
            sortOrder: sortOrder,
            rowid: rowid,
          ),
          withReferenceMapper: (p0) => p0
              .map((e) =>
                  (e.readTable(table), $$UnitsTableReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: ({sectionId = false, lessonsRefs = false}) {
            return PrefetchHooks(
              db: db,
              explicitlyWatchedTables: [if (lessonsRefs) db.lessons],
              addJoins: <
                  T extends TableManagerState<
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic>>(state) {
                if (sectionId) {
                  state = state.withJoin(
                    currentTable: table,
                    currentColumn: table.sectionId,
                    referencedTable: $$UnitsTableReferences._sectionIdTable(db),
                    referencedColumn:
                        $$UnitsTableReferences._sectionIdTable(db).id,
                  ) as T;
                }

                return state;
              },
              getPrefetchedDataCallback: (items) async {
                return [
                  if (lessonsRefs)
                    await $_getPrefetchedData(
                        currentTable: table,
                        referencedTable:
                            $$UnitsTableReferences._lessonsRefsTable(db),
                        managerFromTypedResult: (p0) =>
                            $$UnitsTableReferences(db, table, p0).lessonsRefs,
                        referencedItemsForCurrentItem: (item,
                                referencedItems) =>
                            referencedItems.where((e) => e.unitId == item.id),
                        typedResults: items)
                ];
              },
            );
          },
        ));
}

typedef $$UnitsTableProcessedTableManager = ProcessedTableManager<
    _$CourseDatabase,
    $UnitsTable,
    Unit,
    $$UnitsTableFilterComposer,
    $$UnitsTableOrderingComposer,
    $$UnitsTableAnnotationComposer,
    $$UnitsTableCreateCompanionBuilder,
    $$UnitsTableUpdateCompanionBuilder,
    (Unit, $$UnitsTableReferences),
    Unit,
    PrefetchHooks Function({bool sectionId, bool lessonsRefs})>;
typedef $$LessonsTableCreateCompanionBuilder = LessonsCompanion Function({
  required String id,
  required String unitId,
  required String name,
  Value<String> description,
  Value<String> type,
  Value<String> template,
  Value<String> prerequisiteLessonIds,
  Value<int> sortOrder,
  Value<int> rowid,
});
typedef $$LessonsTableUpdateCompanionBuilder = LessonsCompanion Function({
  Value<String> id,
  Value<String> unitId,
  Value<String> name,
  Value<String> description,
  Value<String> type,
  Value<String> template,
  Value<String> prerequisiteLessonIds,
  Value<int> sortOrder,
  Value<int> rowid,
});

final class $$LessonsTableReferences
    extends BaseReferences<_$CourseDatabase, $LessonsTable, Lesson> {
  $$LessonsTableReferences(super.$_db, super.$_table, super.$_typedResult);

  static $UnitsTable _unitIdTable(_$CourseDatabase db) => db.units
      .createAlias($_aliasNameGenerator(db.lessons.unitId, db.units.id));

  $$UnitsTableProcessedTableManager? get unitId {
    if ($_item.unitId == null) return null;
    final manager = $$UnitsTableTableManager($_db, $_db.units)
        .filter((f) => f.id($_item.unitId!));
    final item = $_typedResult.readTableOrNull(_unitIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
        manager.$state.copyWith(prefetchedData: [item]));
  }

  static MultiTypedResultKey<$LessonContentsTable, List<LessonContent>>
      _lessonContentsRefsTable(_$CourseDatabase db) =>
          MultiTypedResultKey.fromTable(db.lessonContents,
              aliasName: $_aliasNameGenerator(
                  db.lessons.id, db.lessonContents.lessonId));

  $$LessonContentsTableProcessedTableManager get lessonContentsRefs {
    final manager = $$LessonContentsTableTableManager($_db, $_db.lessonContents)
        .filter((f) => f.lessonId.id($_item.id));

    final cache = $_typedResult.readTableOrNull(_lessonContentsRefsTable($_db));
    return ProcessedTableManager(
        manager.$state.copyWith(prefetchedData: cache));
  }
}

class $$LessonsTableFilterComposer
    extends Composer<_$CourseDatabase, $LessonsTable> {
  $$LessonsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
      column: $table.id, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get name => $composableBuilder(
      column: $table.name, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get description => $composableBuilder(
      column: $table.description, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get type => $composableBuilder(
      column: $table.type, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get template => $composableBuilder(
      column: $table.template, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get prerequisiteLessonIds => $composableBuilder(
      column: $table.prerequisiteLessonIds,
      builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get sortOrder => $composableBuilder(
      column: $table.sortOrder, builder: (column) => ColumnFilters(column));

  $$UnitsTableFilterComposer get unitId {
    final $$UnitsTableFilterComposer composer = $composerBuilder(
        composer: this,
        getCurrentColumn: (t) => t.unitId,
        referencedTable: $db.units,
        getReferencedColumn: (t) => t.id,
        builder: (joinBuilder,
                {$addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer}) =>
            $$UnitsTableFilterComposer(
              $db: $db,
              $table: $db.units,
              $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
              joinBuilder: joinBuilder,
              $removeJoinBuilderFromRootComposer:
                  $removeJoinBuilderFromRootComposer,
            ));
    return composer;
  }

  Expression<bool> lessonContentsRefs(
      Expression<bool> Function($$LessonContentsTableFilterComposer f) f) {
    final $$LessonContentsTableFilterComposer composer = $composerBuilder(
        composer: this,
        getCurrentColumn: (t) => t.id,
        referencedTable: $db.lessonContents,
        getReferencedColumn: (t) => t.lessonId,
        builder: (joinBuilder,
                {$addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer}) =>
            $$LessonContentsTableFilterComposer(
              $db: $db,
              $table: $db.lessonContents,
              $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
              joinBuilder: joinBuilder,
              $removeJoinBuilderFromRootComposer:
                  $removeJoinBuilderFromRootComposer,
            ));
    return f(composer);
  }
}

class $$LessonsTableOrderingComposer
    extends Composer<_$CourseDatabase, $LessonsTable> {
  $$LessonsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
      column: $table.id, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get name => $composableBuilder(
      column: $table.name, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get description => $composableBuilder(
      column: $table.description, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get type => $composableBuilder(
      column: $table.type, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get template => $composableBuilder(
      column: $table.template, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get prerequisiteLessonIds => $composableBuilder(
      column: $table.prerequisiteLessonIds,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get sortOrder => $composableBuilder(
      column: $table.sortOrder, builder: (column) => ColumnOrderings(column));

  $$UnitsTableOrderingComposer get unitId {
    final $$UnitsTableOrderingComposer composer = $composerBuilder(
        composer: this,
        getCurrentColumn: (t) => t.unitId,
        referencedTable: $db.units,
        getReferencedColumn: (t) => t.id,
        builder: (joinBuilder,
                {$addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer}) =>
            $$UnitsTableOrderingComposer(
              $db: $db,
              $table: $db.units,
              $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
              joinBuilder: joinBuilder,
              $removeJoinBuilderFromRootComposer:
                  $removeJoinBuilderFromRootComposer,
            ));
    return composer;
  }
}

class $$LessonsTableAnnotationComposer
    extends Composer<_$CourseDatabase, $LessonsTable> {
  $$LessonsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get name =>
      $composableBuilder(column: $table.name, builder: (column) => column);

  GeneratedColumn<String> get description => $composableBuilder(
      column: $table.description, builder: (column) => column);

  GeneratedColumn<String> get type =>
      $composableBuilder(column: $table.type, builder: (column) => column);

  GeneratedColumn<String> get template =>
      $composableBuilder(column: $table.template, builder: (column) => column);

  GeneratedColumn<String> get prerequisiteLessonIds => $composableBuilder(
      column: $table.prerequisiteLessonIds, builder: (column) => column);

  GeneratedColumn<int> get sortOrder =>
      $composableBuilder(column: $table.sortOrder, builder: (column) => column);

  $$UnitsTableAnnotationComposer get unitId {
    final $$UnitsTableAnnotationComposer composer = $composerBuilder(
        composer: this,
        getCurrentColumn: (t) => t.unitId,
        referencedTable: $db.units,
        getReferencedColumn: (t) => t.id,
        builder: (joinBuilder,
                {$addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer}) =>
            $$UnitsTableAnnotationComposer(
              $db: $db,
              $table: $db.units,
              $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
              joinBuilder: joinBuilder,
              $removeJoinBuilderFromRootComposer:
                  $removeJoinBuilderFromRootComposer,
            ));
    return composer;
  }

  Expression<T> lessonContentsRefs<T extends Object>(
      Expression<T> Function($$LessonContentsTableAnnotationComposer a) f) {
    final $$LessonContentsTableAnnotationComposer composer = $composerBuilder(
        composer: this,
        getCurrentColumn: (t) => t.id,
        referencedTable: $db.lessonContents,
        getReferencedColumn: (t) => t.lessonId,
        builder: (joinBuilder,
                {$addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer}) =>
            $$LessonContentsTableAnnotationComposer(
              $db: $db,
              $table: $db.lessonContents,
              $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
              joinBuilder: joinBuilder,
              $removeJoinBuilderFromRootComposer:
                  $removeJoinBuilderFromRootComposer,
            ));
    return f(composer);
  }
}

class $$LessonsTableTableManager extends RootTableManager<
    _$CourseDatabase,
    $LessonsTable,
    Lesson,
    $$LessonsTableFilterComposer,
    $$LessonsTableOrderingComposer,
    $$LessonsTableAnnotationComposer,
    $$LessonsTableCreateCompanionBuilder,
    $$LessonsTableUpdateCompanionBuilder,
    (Lesson, $$LessonsTableReferences),
    Lesson,
    PrefetchHooks Function({bool unitId, bool lessonContentsRefs})> {
  $$LessonsTableTableManager(_$CourseDatabase db, $LessonsTable table)
      : super(TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$LessonsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$LessonsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$LessonsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback: ({
            Value<String> id = const Value.absent(),
            Value<String> unitId = const Value.absent(),
            Value<String> name = const Value.absent(),
            Value<String> description = const Value.absent(),
            Value<String> type = const Value.absent(),
            Value<String> template = const Value.absent(),
            Value<String> prerequisiteLessonIds = const Value.absent(),
            Value<int> sortOrder = const Value.absent(),
            Value<int> rowid = const Value.absent(),
          }) =>
              LessonsCompanion(
            id: id,
            unitId: unitId,
            name: name,
            description: description,
            type: type,
            template: template,
            prerequisiteLessonIds: prerequisiteLessonIds,
            sortOrder: sortOrder,
            rowid: rowid,
          ),
          createCompanionCallback: ({
            required String id,
            required String unitId,
            required String name,
            Value<String> description = const Value.absent(),
            Value<String> type = const Value.absent(),
            Value<String> template = const Value.absent(),
            Value<String> prerequisiteLessonIds = const Value.absent(),
            Value<int> sortOrder = const Value.absent(),
            Value<int> rowid = const Value.absent(),
          }) =>
              LessonsCompanion.insert(
            id: id,
            unitId: unitId,
            name: name,
            description: description,
            type: type,
            template: template,
            prerequisiteLessonIds: prerequisiteLessonIds,
            sortOrder: sortOrder,
            rowid: rowid,
          ),
          withReferenceMapper: (p0) => p0
              .map((e) =>
                  (e.readTable(table), $$LessonsTableReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: (
              {unitId = false, lessonContentsRefs = false}) {
            return PrefetchHooks(
              db: db,
              explicitlyWatchedTables: [
                if (lessonContentsRefs) db.lessonContents
              ],
              addJoins: <
                  T extends TableManagerState<
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic>>(state) {
                if (unitId) {
                  state = state.withJoin(
                    currentTable: table,
                    currentColumn: table.unitId,
                    referencedTable: $$LessonsTableReferences._unitIdTable(db),
                    referencedColumn:
                        $$LessonsTableReferences._unitIdTable(db).id,
                  ) as T;
                }

                return state;
              },
              getPrefetchedDataCallback: (items) async {
                return [
                  if (lessonContentsRefs)
                    await $_getPrefetchedData(
                        currentTable: table,
                        referencedTable: $$LessonsTableReferences
                            ._lessonContentsRefsTable(db),
                        managerFromTypedResult: (p0) =>
                            $$LessonsTableReferences(db, table, p0)
                                .lessonContentsRefs,
                        referencedItemsForCurrentItem: (item,
                                referencedItems) =>
                            referencedItems.where((e) => e.lessonId == item.id),
                        typedResults: items)
                ];
              },
            );
          },
        ));
}

typedef $$LessonsTableProcessedTableManager = ProcessedTableManager<
    _$CourseDatabase,
    $LessonsTable,
    Lesson,
    $$LessonsTableFilterComposer,
    $$LessonsTableOrderingComposer,
    $$LessonsTableAnnotationComposer,
    $$LessonsTableCreateCompanionBuilder,
    $$LessonsTableUpdateCompanionBuilder,
    (Lesson, $$LessonsTableReferences),
    Lesson,
    PrefetchHooks Function({bool unitId, bool lessonContentsRefs})>;
typedef $$LessonContentsTableCreateCompanionBuilder = LessonContentsCompanion
    Function({
  required String lessonId,
  required String contentJson,
  Value<int> rowid,
});
typedef $$LessonContentsTableUpdateCompanionBuilder = LessonContentsCompanion
    Function({
  Value<String> lessonId,
  Value<String> contentJson,
  Value<int> rowid,
});

final class $$LessonContentsTableReferences extends BaseReferences<
    _$CourseDatabase, $LessonContentsTable, LessonContent> {
  $$LessonContentsTableReferences(
      super.$_db, super.$_table, super.$_typedResult);

  static $LessonsTable _lessonIdTable(_$CourseDatabase db) =>
      db.lessons.createAlias(
          $_aliasNameGenerator(db.lessonContents.lessonId, db.lessons.id));

  $$LessonsTableProcessedTableManager? get lessonId {
    if ($_item.lessonId == null) return null;
    final manager = $$LessonsTableTableManager($_db, $_db.lessons)
        .filter((f) => f.id($_item.lessonId!));
    final item = $_typedResult.readTableOrNull(_lessonIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
        manager.$state.copyWith(prefetchedData: [item]));
  }
}

class $$LessonContentsTableFilterComposer
    extends Composer<_$CourseDatabase, $LessonContentsTable> {
  $$LessonContentsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get contentJson => $composableBuilder(
      column: $table.contentJson, builder: (column) => ColumnFilters(column));

  $$LessonsTableFilterComposer get lessonId {
    final $$LessonsTableFilterComposer composer = $composerBuilder(
        composer: this,
        getCurrentColumn: (t) => t.lessonId,
        referencedTable: $db.lessons,
        getReferencedColumn: (t) => t.id,
        builder: (joinBuilder,
                {$addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer}) =>
            $$LessonsTableFilterComposer(
              $db: $db,
              $table: $db.lessons,
              $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
              joinBuilder: joinBuilder,
              $removeJoinBuilderFromRootComposer:
                  $removeJoinBuilderFromRootComposer,
            ));
    return composer;
  }
}

class $$LessonContentsTableOrderingComposer
    extends Composer<_$CourseDatabase, $LessonContentsTable> {
  $$LessonContentsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get contentJson => $composableBuilder(
      column: $table.contentJson, builder: (column) => ColumnOrderings(column));

  $$LessonsTableOrderingComposer get lessonId {
    final $$LessonsTableOrderingComposer composer = $composerBuilder(
        composer: this,
        getCurrentColumn: (t) => t.lessonId,
        referencedTable: $db.lessons,
        getReferencedColumn: (t) => t.id,
        builder: (joinBuilder,
                {$addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer}) =>
            $$LessonsTableOrderingComposer(
              $db: $db,
              $table: $db.lessons,
              $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
              joinBuilder: joinBuilder,
              $removeJoinBuilderFromRootComposer:
                  $removeJoinBuilderFromRootComposer,
            ));
    return composer;
  }
}

class $$LessonContentsTableAnnotationComposer
    extends Composer<_$CourseDatabase, $LessonContentsTable> {
  $$LessonContentsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get contentJson => $composableBuilder(
      column: $table.contentJson, builder: (column) => column);

  $$LessonsTableAnnotationComposer get lessonId {
    final $$LessonsTableAnnotationComposer composer = $composerBuilder(
        composer: this,
        getCurrentColumn: (t) => t.lessonId,
        referencedTable: $db.lessons,
        getReferencedColumn: (t) => t.id,
        builder: (joinBuilder,
                {$addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer}) =>
            $$LessonsTableAnnotationComposer(
              $db: $db,
              $table: $db.lessons,
              $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
              joinBuilder: joinBuilder,
              $removeJoinBuilderFromRootComposer:
                  $removeJoinBuilderFromRootComposer,
            ));
    return composer;
  }
}

class $$LessonContentsTableTableManager extends RootTableManager<
    _$CourseDatabase,
    $LessonContentsTable,
    LessonContent,
    $$LessonContentsTableFilterComposer,
    $$LessonContentsTableOrderingComposer,
    $$LessonContentsTableAnnotationComposer,
    $$LessonContentsTableCreateCompanionBuilder,
    $$LessonContentsTableUpdateCompanionBuilder,
    (LessonContent, $$LessonContentsTableReferences),
    LessonContent,
    PrefetchHooks Function({bool lessonId})> {
  $$LessonContentsTableTableManager(
      _$CourseDatabase db, $LessonContentsTable table)
      : super(TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$LessonContentsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$LessonContentsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$LessonContentsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback: ({
            Value<String> lessonId = const Value.absent(),
            Value<String> contentJson = const Value.absent(),
            Value<int> rowid = const Value.absent(),
          }) =>
              LessonContentsCompanion(
            lessonId: lessonId,
            contentJson: contentJson,
            rowid: rowid,
          ),
          createCompanionCallback: ({
            required String lessonId,
            required String contentJson,
            Value<int> rowid = const Value.absent(),
          }) =>
              LessonContentsCompanion.insert(
            lessonId: lessonId,
            contentJson: contentJson,
            rowid: rowid,
          ),
          withReferenceMapper: (p0) => p0
              .map((e) => (
                    e.readTable(table),
                    $$LessonContentsTableReferences(db, table, e)
                  ))
              .toList(),
          prefetchHooksCallback: ({lessonId = false}) {
            return PrefetchHooks(
              db: db,
              explicitlyWatchedTables: [],
              addJoins: <
                  T extends TableManagerState<
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic>>(state) {
                if (lessonId) {
                  state = state.withJoin(
                    currentTable: table,
                    currentColumn: table.lessonId,
                    referencedTable:
                        $$LessonContentsTableReferences._lessonIdTable(db),
                    referencedColumn:
                        $$LessonContentsTableReferences._lessonIdTable(db).id,
                  ) as T;
                }

                return state;
              },
              getPrefetchedDataCallback: (items) async {
                return [];
              },
            );
          },
        ));
}

typedef $$LessonContentsTableProcessedTableManager = ProcessedTableManager<
    _$CourseDatabase,
    $LessonContentsTable,
    LessonContent,
    $$LessonContentsTableFilterComposer,
    $$LessonContentsTableOrderingComposer,
    $$LessonContentsTableAnnotationComposer,
    $$LessonContentsTableCreateCompanionBuilder,
    $$LessonContentsTableUpdateCompanionBuilder,
    (LessonContent, $$LessonContentsTableReferences),
    LessonContent,
    PrefetchHooks Function({bool lessonId})>;
typedef $$VocabularyTableCreateCompanionBuilder = VocabularyCompanion Function({
  required String id,
  required String term,
  required String translation,
  Value<String?> pronunciation,
  Value<String?> audioAsset,
  Value<String> tags,
  Value<int> rowid,
});
typedef $$VocabularyTableUpdateCompanionBuilder = VocabularyCompanion Function({
  Value<String> id,
  Value<String> term,
  Value<String> translation,
  Value<String?> pronunciation,
  Value<String?> audioAsset,
  Value<String> tags,
  Value<int> rowid,
});

class $$VocabularyTableFilterComposer
    extends Composer<_$CourseDatabase, $VocabularyTable> {
  $$VocabularyTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
      column: $table.id, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get term => $composableBuilder(
      column: $table.term, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get translation => $composableBuilder(
      column: $table.translation, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get pronunciation => $composableBuilder(
      column: $table.pronunciation, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get audioAsset => $composableBuilder(
      column: $table.audioAsset, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get tags => $composableBuilder(
      column: $table.tags, builder: (column) => ColumnFilters(column));
}

class $$VocabularyTableOrderingComposer
    extends Composer<_$CourseDatabase, $VocabularyTable> {
  $$VocabularyTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
      column: $table.id, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get term => $composableBuilder(
      column: $table.term, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get translation => $composableBuilder(
      column: $table.translation, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get pronunciation => $composableBuilder(
      column: $table.pronunciation,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get audioAsset => $composableBuilder(
      column: $table.audioAsset, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get tags => $composableBuilder(
      column: $table.tags, builder: (column) => ColumnOrderings(column));
}

class $$VocabularyTableAnnotationComposer
    extends Composer<_$CourseDatabase, $VocabularyTable> {
  $$VocabularyTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get term =>
      $composableBuilder(column: $table.term, builder: (column) => column);

  GeneratedColumn<String> get translation => $composableBuilder(
      column: $table.translation, builder: (column) => column);

  GeneratedColumn<String> get pronunciation => $composableBuilder(
      column: $table.pronunciation, builder: (column) => column);

  GeneratedColumn<String> get audioAsset => $composableBuilder(
      column: $table.audioAsset, builder: (column) => column);

  GeneratedColumn<String> get tags =>
      $composableBuilder(column: $table.tags, builder: (column) => column);
}

class $$VocabularyTableTableManager extends RootTableManager<
    _$CourseDatabase,
    $VocabularyTable,
    VocabularyData,
    $$VocabularyTableFilterComposer,
    $$VocabularyTableOrderingComposer,
    $$VocabularyTableAnnotationComposer,
    $$VocabularyTableCreateCompanionBuilder,
    $$VocabularyTableUpdateCompanionBuilder,
    (
      VocabularyData,
      BaseReferences<_$CourseDatabase, $VocabularyTable, VocabularyData>
    ),
    VocabularyData,
    PrefetchHooks Function()> {
  $$VocabularyTableTableManager(_$CourseDatabase db, $VocabularyTable table)
      : super(TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$VocabularyTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$VocabularyTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$VocabularyTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback: ({
            Value<String> id = const Value.absent(),
            Value<String> term = const Value.absent(),
            Value<String> translation = const Value.absent(),
            Value<String?> pronunciation = const Value.absent(),
            Value<String?> audioAsset = const Value.absent(),
            Value<String> tags = const Value.absent(),
            Value<int> rowid = const Value.absent(),
          }) =>
              VocabularyCompanion(
            id: id,
            term: term,
            translation: translation,
            pronunciation: pronunciation,
            audioAsset: audioAsset,
            tags: tags,
            rowid: rowid,
          ),
          createCompanionCallback: ({
            required String id,
            required String term,
            required String translation,
            Value<String?> pronunciation = const Value.absent(),
            Value<String?> audioAsset = const Value.absent(),
            Value<String> tags = const Value.absent(),
            Value<int> rowid = const Value.absent(),
          }) =>
              VocabularyCompanion.insert(
            id: id,
            term: term,
            translation: translation,
            pronunciation: pronunciation,
            audioAsset: audioAsset,
            tags: tags,
            rowid: rowid,
          ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ));
}

typedef $$VocabularyTableProcessedTableManager = ProcessedTableManager<
    _$CourseDatabase,
    $VocabularyTable,
    VocabularyData,
    $$VocabularyTableFilterComposer,
    $$VocabularyTableOrderingComposer,
    $$VocabularyTableAnnotationComposer,
    $$VocabularyTableCreateCompanionBuilder,
    $$VocabularyTableUpdateCompanionBuilder,
    (
      VocabularyData,
      BaseReferences<_$CourseDatabase, $VocabularyTable, VocabularyData>
    ),
    VocabularyData,
    PrefetchHooks Function()>;
typedef $$GrammarPointsTableCreateCompanionBuilder = GrammarPointsCompanion
    Function({
  required String id,
  required String title,
  Value<String> explanation,
  Value<String> exampleExpressionIds,
  Value<String> exampleSentenceIds,
  Value<String> practiceItems,
  Value<int> rowid,
});
typedef $$GrammarPointsTableUpdateCompanionBuilder = GrammarPointsCompanion
    Function({
  Value<String> id,
  Value<String> title,
  Value<String> explanation,
  Value<String> exampleExpressionIds,
  Value<String> exampleSentenceIds,
  Value<String> practiceItems,
  Value<int> rowid,
});

class $$GrammarPointsTableFilterComposer
    extends Composer<_$CourseDatabase, $GrammarPointsTable> {
  $$GrammarPointsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
      column: $table.id, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get title => $composableBuilder(
      column: $table.title, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get explanation => $composableBuilder(
      column: $table.explanation, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get exampleExpressionIds => $composableBuilder(
      column: $table.exampleExpressionIds,
      builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get exampleSentenceIds => $composableBuilder(
      column: $table.exampleSentenceIds,
      builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get practiceItems => $composableBuilder(
      column: $table.practiceItems, builder: (column) => ColumnFilters(column));
}

class $$GrammarPointsTableOrderingComposer
    extends Composer<_$CourseDatabase, $GrammarPointsTable> {
  $$GrammarPointsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
      column: $table.id, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get title => $composableBuilder(
      column: $table.title, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get explanation => $composableBuilder(
      column: $table.explanation, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get exampleExpressionIds => $composableBuilder(
      column: $table.exampleExpressionIds,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get exampleSentenceIds => $composableBuilder(
      column: $table.exampleSentenceIds,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get practiceItems => $composableBuilder(
      column: $table.practiceItems,
      builder: (column) => ColumnOrderings(column));
}

class $$GrammarPointsTableAnnotationComposer
    extends Composer<_$CourseDatabase, $GrammarPointsTable> {
  $$GrammarPointsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get title =>
      $composableBuilder(column: $table.title, builder: (column) => column);

  GeneratedColumn<String> get explanation => $composableBuilder(
      column: $table.explanation, builder: (column) => column);

  GeneratedColumn<String> get exampleExpressionIds => $composableBuilder(
      column: $table.exampleExpressionIds, builder: (column) => column);

  GeneratedColumn<String> get exampleSentenceIds => $composableBuilder(
      column: $table.exampleSentenceIds, builder: (column) => column);

  GeneratedColumn<String> get practiceItems => $composableBuilder(
      column: $table.practiceItems, builder: (column) => column);
}

class $$GrammarPointsTableTableManager extends RootTableManager<
    _$CourseDatabase,
    $GrammarPointsTable,
    GrammarPoint,
    $$GrammarPointsTableFilterComposer,
    $$GrammarPointsTableOrderingComposer,
    $$GrammarPointsTableAnnotationComposer,
    $$GrammarPointsTableCreateCompanionBuilder,
    $$GrammarPointsTableUpdateCompanionBuilder,
    (
      GrammarPoint,
      BaseReferences<_$CourseDatabase, $GrammarPointsTable, GrammarPoint>
    ),
    GrammarPoint,
    PrefetchHooks Function()> {
  $$GrammarPointsTableTableManager(
      _$CourseDatabase db, $GrammarPointsTable table)
      : super(TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$GrammarPointsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$GrammarPointsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$GrammarPointsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback: ({
            Value<String> id = const Value.absent(),
            Value<String> title = const Value.absent(),
            Value<String> explanation = const Value.absent(),
            Value<String> exampleExpressionIds = const Value.absent(),
            Value<String> exampleSentenceIds = const Value.absent(),
            Value<String> practiceItems = const Value.absent(),
            Value<int> rowid = const Value.absent(),
          }) =>
              GrammarPointsCompanion(
            id: id,
            title: title,
            explanation: explanation,
            exampleExpressionIds: exampleExpressionIds,
            exampleSentenceIds: exampleSentenceIds,
            practiceItems: practiceItems,
            rowid: rowid,
          ),
          createCompanionCallback: ({
            required String id,
            required String title,
            Value<String> explanation = const Value.absent(),
            Value<String> exampleExpressionIds = const Value.absent(),
            Value<String> exampleSentenceIds = const Value.absent(),
            Value<String> practiceItems = const Value.absent(),
            Value<int> rowid = const Value.absent(),
          }) =>
              GrammarPointsCompanion.insert(
            id: id,
            title: title,
            explanation: explanation,
            exampleExpressionIds: exampleExpressionIds,
            exampleSentenceIds: exampleSentenceIds,
            practiceItems: practiceItems,
            rowid: rowid,
          ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ));
}

typedef $$GrammarPointsTableProcessedTableManager = ProcessedTableManager<
    _$CourseDatabase,
    $GrammarPointsTable,
    GrammarPoint,
    $$GrammarPointsTableFilterComposer,
    $$GrammarPointsTableOrderingComposer,
    $$GrammarPointsTableAnnotationComposer,
    $$GrammarPointsTableCreateCompanionBuilder,
    $$GrammarPointsTableUpdateCompanionBuilder,
    (
      GrammarPoint,
      BaseReferences<_$CourseDatabase, $GrammarPointsTable, GrammarPoint>
    ),
    GrammarPoint,
    PrefetchHooks Function()>;
typedef $$CourseMetaTableCreateCompanionBuilder = CourseMetaCompanion Function({
  required String key,
  required String value,
  Value<int> rowid,
});
typedef $$CourseMetaTableUpdateCompanionBuilder = CourseMetaCompanion Function({
  Value<String> key,
  Value<String> value,
  Value<int> rowid,
});

class $$CourseMetaTableFilterComposer
    extends Composer<_$CourseDatabase, $CourseMetaTable> {
  $$CourseMetaTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get key => $composableBuilder(
      column: $table.key, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get value => $composableBuilder(
      column: $table.value, builder: (column) => ColumnFilters(column));
}

class $$CourseMetaTableOrderingComposer
    extends Composer<_$CourseDatabase, $CourseMetaTable> {
  $$CourseMetaTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get key => $composableBuilder(
      column: $table.key, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get value => $composableBuilder(
      column: $table.value, builder: (column) => ColumnOrderings(column));
}

class $$CourseMetaTableAnnotationComposer
    extends Composer<_$CourseDatabase, $CourseMetaTable> {
  $$CourseMetaTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get key =>
      $composableBuilder(column: $table.key, builder: (column) => column);

  GeneratedColumn<String> get value =>
      $composableBuilder(column: $table.value, builder: (column) => column);
}

class $$CourseMetaTableTableManager extends RootTableManager<
    _$CourseDatabase,
    $CourseMetaTable,
    CourseMetaData,
    $$CourseMetaTableFilterComposer,
    $$CourseMetaTableOrderingComposer,
    $$CourseMetaTableAnnotationComposer,
    $$CourseMetaTableCreateCompanionBuilder,
    $$CourseMetaTableUpdateCompanionBuilder,
    (
      CourseMetaData,
      BaseReferences<_$CourseDatabase, $CourseMetaTable, CourseMetaData>
    ),
    CourseMetaData,
    PrefetchHooks Function()> {
  $$CourseMetaTableTableManager(_$CourseDatabase db, $CourseMetaTable table)
      : super(TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$CourseMetaTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$CourseMetaTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$CourseMetaTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback: ({
            Value<String> key = const Value.absent(),
            Value<String> value = const Value.absent(),
            Value<int> rowid = const Value.absent(),
          }) =>
              CourseMetaCompanion(
            key: key,
            value: value,
            rowid: rowid,
          ),
          createCompanionCallback: ({
            required String key,
            required String value,
            Value<int> rowid = const Value.absent(),
          }) =>
              CourseMetaCompanion.insert(
            key: key,
            value: value,
            rowid: rowid,
          ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ));
}

typedef $$CourseMetaTableProcessedTableManager = ProcessedTableManager<
    _$CourseDatabase,
    $CourseMetaTable,
    CourseMetaData,
    $$CourseMetaTableFilterComposer,
    $$CourseMetaTableOrderingComposer,
    $$CourseMetaTableAnnotationComposer,
    $$CourseMetaTableCreateCompanionBuilder,
    $$CourseMetaTableUpdateCompanionBuilder,
    (
      CourseMetaData,
      BaseReferences<_$CourseDatabase, $CourseMetaTable, CourseMetaData>
    ),
    CourseMetaData,
    PrefetchHooks Function()>;
typedef $$ExpressionsTableCreateCompanionBuilder = ExpressionsCompanion
    Function({
  required String id,
  required String term,
  required String translation,
  Value<String?> pronunciation,
  Value<String?> audioAsset,
  Value<String> tags,
  Value<int> rowid,
});
typedef $$ExpressionsTableUpdateCompanionBuilder = ExpressionsCompanion
    Function({
  Value<String> id,
  Value<String> term,
  Value<String> translation,
  Value<String?> pronunciation,
  Value<String?> audioAsset,
  Value<String> tags,
  Value<int> rowid,
});

class $$ExpressionsTableFilterComposer
    extends Composer<_$CourseDatabase, $ExpressionsTable> {
  $$ExpressionsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
      column: $table.id, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get term => $composableBuilder(
      column: $table.term, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get translation => $composableBuilder(
      column: $table.translation, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get pronunciation => $composableBuilder(
      column: $table.pronunciation, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get audioAsset => $composableBuilder(
      column: $table.audioAsset, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get tags => $composableBuilder(
      column: $table.tags, builder: (column) => ColumnFilters(column));
}

class $$ExpressionsTableOrderingComposer
    extends Composer<_$CourseDatabase, $ExpressionsTable> {
  $$ExpressionsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
      column: $table.id, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get term => $composableBuilder(
      column: $table.term, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get translation => $composableBuilder(
      column: $table.translation, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get pronunciation => $composableBuilder(
      column: $table.pronunciation,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get audioAsset => $composableBuilder(
      column: $table.audioAsset, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get tags => $composableBuilder(
      column: $table.tags, builder: (column) => ColumnOrderings(column));
}

class $$ExpressionsTableAnnotationComposer
    extends Composer<_$CourseDatabase, $ExpressionsTable> {
  $$ExpressionsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get term =>
      $composableBuilder(column: $table.term, builder: (column) => column);

  GeneratedColumn<String> get translation => $composableBuilder(
      column: $table.translation, builder: (column) => column);

  GeneratedColumn<String> get pronunciation => $composableBuilder(
      column: $table.pronunciation, builder: (column) => column);

  GeneratedColumn<String> get audioAsset => $composableBuilder(
      column: $table.audioAsset, builder: (column) => column);

  GeneratedColumn<String> get tags =>
      $composableBuilder(column: $table.tags, builder: (column) => column);
}

class $$ExpressionsTableTableManager extends RootTableManager<
    _$CourseDatabase,
    $ExpressionsTable,
    ExpressionEntry,
    $$ExpressionsTableFilterComposer,
    $$ExpressionsTableOrderingComposer,
    $$ExpressionsTableAnnotationComposer,
    $$ExpressionsTableCreateCompanionBuilder,
    $$ExpressionsTableUpdateCompanionBuilder,
    (
      ExpressionEntry,
      BaseReferences<_$CourseDatabase, $ExpressionsTable, ExpressionEntry>
    ),
    ExpressionEntry,
    PrefetchHooks Function()> {
  $$ExpressionsTableTableManager(_$CourseDatabase db, $ExpressionsTable table)
      : super(TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$ExpressionsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$ExpressionsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$ExpressionsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback: ({
            Value<String> id = const Value.absent(),
            Value<String> term = const Value.absent(),
            Value<String> translation = const Value.absent(),
            Value<String?> pronunciation = const Value.absent(),
            Value<String?> audioAsset = const Value.absent(),
            Value<String> tags = const Value.absent(),
            Value<int> rowid = const Value.absent(),
          }) =>
              ExpressionsCompanion(
            id: id,
            term: term,
            translation: translation,
            pronunciation: pronunciation,
            audioAsset: audioAsset,
            tags: tags,
            rowid: rowid,
          ),
          createCompanionCallback: ({
            required String id,
            required String term,
            required String translation,
            Value<String?> pronunciation = const Value.absent(),
            Value<String?> audioAsset = const Value.absent(),
            Value<String> tags = const Value.absent(),
            Value<int> rowid = const Value.absent(),
          }) =>
              ExpressionsCompanion.insert(
            id: id,
            term: term,
            translation: translation,
            pronunciation: pronunciation,
            audioAsset: audioAsset,
            tags: tags,
            rowid: rowid,
          ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ));
}

typedef $$ExpressionsTableProcessedTableManager = ProcessedTableManager<
    _$CourseDatabase,
    $ExpressionsTable,
    ExpressionEntry,
    $$ExpressionsTableFilterComposer,
    $$ExpressionsTableOrderingComposer,
    $$ExpressionsTableAnnotationComposer,
    $$ExpressionsTableCreateCompanionBuilder,
    $$ExpressionsTableUpdateCompanionBuilder,
    (
      ExpressionEntry,
      BaseReferences<_$CourseDatabase, $ExpressionsTable, ExpressionEntry>
    ),
    ExpressionEntry,
    PrefetchHooks Function()>;

class $CourseDatabaseManager {
  final _$CourseDatabase _db;
  $CourseDatabaseManager(this._db);
  $$SectionsTableTableManager get sections =>
      $$SectionsTableTableManager(_db, _db.sections);
  $$UnitsTableTableManager get units =>
      $$UnitsTableTableManager(_db, _db.units);
  $$LessonsTableTableManager get lessons =>
      $$LessonsTableTableManager(_db, _db.lessons);
  $$LessonContentsTableTableManager get lessonContents =>
      $$LessonContentsTableTableManager(_db, _db.lessonContents);
  $$VocabularyTableTableManager get vocabulary =>
      $$VocabularyTableTableManager(_db, _db.vocabulary);
  $$GrammarPointsTableTableManager get grammarPoints =>
      $$GrammarPointsTableTableManager(_db, _db.grammarPoints);
  $$CourseMetaTableTableManager get courseMeta =>
      $$CourseMetaTableTableManager(_db, _db.courseMeta);
  $$ExpressionsTableTableManager get expressions =>
      $$ExpressionsTableTableManager(_db, _db.expressions);
}

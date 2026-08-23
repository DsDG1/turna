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
  static const VerificationMeta _levelMeta = const VerificationMeta('level');
  @override
  late final GeneratedColumn<String> level = GeneratedColumn<String>(
      'level', aliasedName, false,
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
      [id, name, description, level, prerequisiteSectionIds, sortOrder];
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
    if (data.containsKey('level')) {
      context.handle(
          _levelMeta, level.isAcceptableOrUnknown(data['level']!, _levelMeta));
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
      level: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}level'])!,
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
  final String level;
  final String prerequisiteSectionIds;
  final int sortOrder;
  const Section(
      {required this.id,
      required this.name,
      required this.description,
      required this.level,
      required this.prerequisiteSectionIds,
      required this.sortOrder});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['name'] = Variable<String>(name);
    map['description'] = Variable<String>(description);
    map['level'] = Variable<String>(level);
    map['prerequisite_section_ids'] = Variable<String>(prerequisiteSectionIds);
    map['sort_order'] = Variable<int>(sortOrder);
    return map;
  }

  SectionsCompanion toCompanion(bool nullToAbsent) {
    return SectionsCompanion(
      id: Value(id),
      name: Value(name),
      description: Value(description),
      level: Value(level),
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
      level: serializer.fromJson<String>(json['level']),
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
      'level': serializer.toJson<String>(level),
      'prerequisiteSectionIds':
          serializer.toJson<String>(prerequisiteSectionIds),
      'sortOrder': serializer.toJson<int>(sortOrder),
    };
  }

  Section copyWith(
          {String? id,
          String? name,
          String? description,
          String? level,
          String? prerequisiteSectionIds,
          int? sortOrder}) =>
      Section(
        id: id ?? this.id,
        name: name ?? this.name,
        description: description ?? this.description,
        level: level ?? this.level,
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
      level: data.level.present ? data.level.value : this.level,
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
          ..write('level: $level, ')
          ..write('prerequisiteSectionIds: $prerequisiteSectionIds, ')
          ..write('sortOrder: $sortOrder')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
      id, name, description, level, prerequisiteSectionIds, sortOrder);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is Section &&
          other.id == this.id &&
          other.name == this.name &&
          other.description == this.description &&
          other.level == this.level &&
          other.prerequisiteSectionIds == this.prerequisiteSectionIds &&
          other.sortOrder == this.sortOrder);
}

class SectionsCompanion extends UpdateCompanion<Section> {
  final Value<String> id;
  final Value<String> name;
  final Value<String> description;
  final Value<String> level;
  final Value<String> prerequisiteSectionIds;
  final Value<int> sortOrder;
  final Value<int> rowid;
  const SectionsCompanion({
    this.id = const Value.absent(),
    this.name = const Value.absent(),
    this.description = const Value.absent(),
    this.level = const Value.absent(),
    this.prerequisiteSectionIds = const Value.absent(),
    this.sortOrder = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  SectionsCompanion.insert({
    required String id,
    required String name,
    this.description = const Value.absent(),
    this.level = const Value.absent(),
    this.prerequisiteSectionIds = const Value.absent(),
    this.sortOrder = const Value.absent(),
    this.rowid = const Value.absent(),
  })  : id = Value(id),
        name = Value(name);
  static Insertable<Section> custom({
    Expression<String>? id,
    Expression<String>? name,
    Expression<String>? description,
    Expression<String>? level,
    Expression<String>? prerequisiteSectionIds,
    Expression<int>? sortOrder,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (name != null) 'name': name,
      if (description != null) 'description': description,
      if (level != null) 'level': level,
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
      Value<String>? level,
      Value<String>? prerequisiteSectionIds,
      Value<int>? sortOrder,
      Value<int>? rowid}) {
    return SectionsCompanion(
      id: id ?? this.id,
      name: name ?? this.name,
      description: description ?? this.description,
      level: level ?? this.level,
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
    if (level.present) {
      map['level'] = Variable<String>(level.value);
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
          ..write('level: $level, ')
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

class $AnkiImportsTable extends AnkiImports
    with TableInfo<$AnkiImportsTable, AnkiImport> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $AnkiImportsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _importIdMeta =
      const VerificationMeta('importId');
  @override
  late final GeneratedColumn<String> importId = GeneratedColumn<String>(
      'import_id', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _sourcePathMeta =
      const VerificationMeta('sourcePath');
  @override
  late final GeneratedColumn<String> sourcePath = GeneratedColumn<String>(
      'source_path', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _sourceHashMeta =
      const VerificationMeta('sourceHash');
  @override
  late final GeneratedColumn<String> sourceHash = GeneratedColumn<String>(
      'source_hash', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _importedAtMeta =
      const VerificationMeta('importedAt');
  @override
  late final GeneratedColumn<int> importedAt = GeneratedColumn<int>(
      'imported_at', aliasedName, false,
      type: DriftSqlType.int, requiredDuringInsert: true);
  static const VerificationMeta _deckCountMeta =
      const VerificationMeta('deckCount');
  @override
  late final GeneratedColumn<int> deckCount = GeneratedColumn<int>(
      'deck_count', aliasedName, false,
      type: DriftSqlType.int,
      requiredDuringInsert: false,
      defaultValue: const Constant(0));
  static const VerificationMeta _noteCountMeta =
      const VerificationMeta('noteCount');
  @override
  late final GeneratedColumn<int> noteCount = GeneratedColumn<int>(
      'note_count', aliasedName, false,
      type: DriftSqlType.int,
      requiredDuringInsert: false,
      defaultValue: const Constant(0));
  static const VerificationMeta _cardCountMeta =
      const VerificationMeta('cardCount');
  @override
  late final GeneratedColumn<int> cardCount = GeneratedColumn<int>(
      'card_count', aliasedName, false,
      type: DriftSqlType.int,
      requiredDuringInsert: false,
      defaultValue: const Constant(0));
  static const VerificationMeta _mediaCountMeta =
      const VerificationMeta('mediaCount');
  @override
  late final GeneratedColumn<int> mediaCount = GeneratedColumn<int>(
      'media_count', aliasedName, false,
      type: DriftSqlType.int,
      requiredDuringInsert: false,
      defaultValue: const Constant(0));
  static const VerificationMeta _notetypesJsonMeta =
      const VerificationMeta('notetypesJson');
  @override
  late final GeneratedColumn<String> notetypesJson = GeneratedColumn<String>(
      'notetypes_json', aliasedName, false,
      type: DriftSqlType.string,
      requiredDuringInsert: false,
      defaultValue: const Constant('{}'));
  static const VerificationMeta _aiEnhancedMeta =
      const VerificationMeta('aiEnhanced');
  @override
  late final GeneratedColumn<bool> aiEnhanced = GeneratedColumn<bool>(
      'ai_enhanced', aliasedName, false,
      type: DriftSqlType.bool,
      requiredDuringInsert: false,
      defaultConstraints:
          GeneratedColumn.constraintIsAlways('CHECK ("ai_enhanced" IN (0, 1))'),
      defaultValue: const Constant(false));
  static const VerificationMeta _versionMeta =
      const VerificationMeta('version');
  @override
  late final GeneratedColumn<int> version = GeneratedColumn<int>(
      'version', aliasedName, false,
      type: DriftSqlType.int,
      requiredDuringInsert: false,
      defaultValue: const Constant(1));
  @override
  List<GeneratedColumn> get $columns => [
        importId,
        sourcePath,
        sourceHash,
        importedAt,
        deckCount,
        noteCount,
        cardCount,
        mediaCount,
        notetypesJson,
        aiEnhanced,
        version
      ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'anki_imports';
  @override
  VerificationContext validateIntegrity(Insertable<AnkiImport> instance,
      {bool isInserting = false}) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('import_id')) {
      context.handle(_importIdMeta,
          importId.isAcceptableOrUnknown(data['import_id']!, _importIdMeta));
    } else if (isInserting) {
      context.missing(_importIdMeta);
    }
    if (data.containsKey('source_path')) {
      context.handle(
          _sourcePathMeta,
          sourcePath.isAcceptableOrUnknown(
              data['source_path']!, _sourcePathMeta));
    } else if (isInserting) {
      context.missing(_sourcePathMeta);
    }
    if (data.containsKey('source_hash')) {
      context.handle(
          _sourceHashMeta,
          sourceHash.isAcceptableOrUnknown(
              data['source_hash']!, _sourceHashMeta));
    } else if (isInserting) {
      context.missing(_sourceHashMeta);
    }
    if (data.containsKey('imported_at')) {
      context.handle(
          _importedAtMeta,
          importedAt.isAcceptableOrUnknown(
              data['imported_at']!, _importedAtMeta));
    } else if (isInserting) {
      context.missing(_importedAtMeta);
    }
    if (data.containsKey('deck_count')) {
      context.handle(_deckCountMeta,
          deckCount.isAcceptableOrUnknown(data['deck_count']!, _deckCountMeta));
    }
    if (data.containsKey('note_count')) {
      context.handle(_noteCountMeta,
          noteCount.isAcceptableOrUnknown(data['note_count']!, _noteCountMeta));
    }
    if (data.containsKey('card_count')) {
      context.handle(_cardCountMeta,
          cardCount.isAcceptableOrUnknown(data['card_count']!, _cardCountMeta));
    }
    if (data.containsKey('media_count')) {
      context.handle(
          _mediaCountMeta,
          mediaCount.isAcceptableOrUnknown(
              data['media_count']!, _mediaCountMeta));
    }
    if (data.containsKey('notetypes_json')) {
      context.handle(
          _notetypesJsonMeta,
          notetypesJson.isAcceptableOrUnknown(
              data['notetypes_json']!, _notetypesJsonMeta));
    }
    if (data.containsKey('ai_enhanced')) {
      context.handle(
          _aiEnhancedMeta,
          aiEnhanced.isAcceptableOrUnknown(
              data['ai_enhanced']!, _aiEnhancedMeta));
    }
    if (data.containsKey('version')) {
      context.handle(_versionMeta,
          version.isAcceptableOrUnknown(data['version']!, _versionMeta));
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {importId};
  @override
  AnkiImport map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return AnkiImport(
      importId: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}import_id'])!,
      sourcePath: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}source_path'])!,
      sourceHash: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}source_hash'])!,
      importedAt: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}imported_at'])!,
      deckCount: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}deck_count'])!,
      noteCount: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}note_count'])!,
      cardCount: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}card_count'])!,
      mediaCount: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}media_count'])!,
      notetypesJson: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}notetypes_json'])!,
      aiEnhanced: attachedDatabase.typeMapping
          .read(DriftSqlType.bool, data['${effectivePrefix}ai_enhanced'])!,
      version: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}version'])!,
    );
  }

  @override
  $AnkiImportsTable createAlias(String alias) {
    return $AnkiImportsTable(attachedDatabase, alias);
  }
}

class AnkiImport extends DataClass implements Insertable<AnkiImport> {
  final String importId;
  final String sourcePath;
  final String sourceHash;
  final int importedAt;
  final int deckCount;
  final int noteCount;
  final int cardCount;
  final int mediaCount;
  final String notetypesJson;
  final bool aiEnhanced;
  final int version;
  const AnkiImport(
      {required this.importId,
      required this.sourcePath,
      required this.sourceHash,
      required this.importedAt,
      required this.deckCount,
      required this.noteCount,
      required this.cardCount,
      required this.mediaCount,
      required this.notetypesJson,
      required this.aiEnhanced,
      required this.version});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['import_id'] = Variable<String>(importId);
    map['source_path'] = Variable<String>(sourcePath);
    map['source_hash'] = Variable<String>(sourceHash);
    map['imported_at'] = Variable<int>(importedAt);
    map['deck_count'] = Variable<int>(deckCount);
    map['note_count'] = Variable<int>(noteCount);
    map['card_count'] = Variable<int>(cardCount);
    map['media_count'] = Variable<int>(mediaCount);
    map['notetypes_json'] = Variable<String>(notetypesJson);
    map['ai_enhanced'] = Variable<bool>(aiEnhanced);
    map['version'] = Variable<int>(version);
    return map;
  }

  AnkiImportsCompanion toCompanion(bool nullToAbsent) {
    return AnkiImportsCompanion(
      importId: Value(importId),
      sourcePath: Value(sourcePath),
      sourceHash: Value(sourceHash),
      importedAt: Value(importedAt),
      deckCount: Value(deckCount),
      noteCount: Value(noteCount),
      cardCount: Value(cardCount),
      mediaCount: Value(mediaCount),
      notetypesJson: Value(notetypesJson),
      aiEnhanced: Value(aiEnhanced),
      version: Value(version),
    );
  }

  factory AnkiImport.fromJson(Map<String, dynamic> json,
      {ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return AnkiImport(
      importId: serializer.fromJson<String>(json['importId']),
      sourcePath: serializer.fromJson<String>(json['sourcePath']),
      sourceHash: serializer.fromJson<String>(json['sourceHash']),
      importedAt: serializer.fromJson<int>(json['importedAt']),
      deckCount: serializer.fromJson<int>(json['deckCount']),
      noteCount: serializer.fromJson<int>(json['noteCount']),
      cardCount: serializer.fromJson<int>(json['cardCount']),
      mediaCount: serializer.fromJson<int>(json['mediaCount']),
      notetypesJson: serializer.fromJson<String>(json['notetypesJson']),
      aiEnhanced: serializer.fromJson<bool>(json['aiEnhanced']),
      version: serializer.fromJson<int>(json['version']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'importId': serializer.toJson<String>(importId),
      'sourcePath': serializer.toJson<String>(sourcePath),
      'sourceHash': serializer.toJson<String>(sourceHash),
      'importedAt': serializer.toJson<int>(importedAt),
      'deckCount': serializer.toJson<int>(deckCount),
      'noteCount': serializer.toJson<int>(noteCount),
      'cardCount': serializer.toJson<int>(cardCount),
      'mediaCount': serializer.toJson<int>(mediaCount),
      'notetypesJson': serializer.toJson<String>(notetypesJson),
      'aiEnhanced': serializer.toJson<bool>(aiEnhanced),
      'version': serializer.toJson<int>(version),
    };
  }

  AnkiImport copyWith(
          {String? importId,
          String? sourcePath,
          String? sourceHash,
          int? importedAt,
          int? deckCount,
          int? noteCount,
          int? cardCount,
          int? mediaCount,
          String? notetypesJson,
          bool? aiEnhanced,
          int? version}) =>
      AnkiImport(
        importId: importId ?? this.importId,
        sourcePath: sourcePath ?? this.sourcePath,
        sourceHash: sourceHash ?? this.sourceHash,
        importedAt: importedAt ?? this.importedAt,
        deckCount: deckCount ?? this.deckCount,
        noteCount: noteCount ?? this.noteCount,
        cardCount: cardCount ?? this.cardCount,
        mediaCount: mediaCount ?? this.mediaCount,
        notetypesJson: notetypesJson ?? this.notetypesJson,
        aiEnhanced: aiEnhanced ?? this.aiEnhanced,
        version: version ?? this.version,
      );
  AnkiImport copyWithCompanion(AnkiImportsCompanion data) {
    return AnkiImport(
      importId: data.importId.present ? data.importId.value : this.importId,
      sourcePath:
          data.sourcePath.present ? data.sourcePath.value : this.sourcePath,
      sourceHash:
          data.sourceHash.present ? data.sourceHash.value : this.sourceHash,
      importedAt:
          data.importedAt.present ? data.importedAt.value : this.importedAt,
      deckCount: data.deckCount.present ? data.deckCount.value : this.deckCount,
      noteCount: data.noteCount.present ? data.noteCount.value : this.noteCount,
      cardCount: data.cardCount.present ? data.cardCount.value : this.cardCount,
      mediaCount:
          data.mediaCount.present ? data.mediaCount.value : this.mediaCount,
      notetypesJson: data.notetypesJson.present
          ? data.notetypesJson.value
          : this.notetypesJson,
      aiEnhanced:
          data.aiEnhanced.present ? data.aiEnhanced.value : this.aiEnhanced,
      version: data.version.present ? data.version.value : this.version,
    );
  }

  @override
  String toString() {
    return (StringBuffer('AnkiImport(')
          ..write('importId: $importId, ')
          ..write('sourcePath: $sourcePath, ')
          ..write('sourceHash: $sourceHash, ')
          ..write('importedAt: $importedAt, ')
          ..write('deckCount: $deckCount, ')
          ..write('noteCount: $noteCount, ')
          ..write('cardCount: $cardCount, ')
          ..write('mediaCount: $mediaCount, ')
          ..write('notetypesJson: $notetypesJson, ')
          ..write('aiEnhanced: $aiEnhanced, ')
          ..write('version: $version')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
      importId,
      sourcePath,
      sourceHash,
      importedAt,
      deckCount,
      noteCount,
      cardCount,
      mediaCount,
      notetypesJson,
      aiEnhanced,
      version);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is AnkiImport &&
          other.importId == this.importId &&
          other.sourcePath == this.sourcePath &&
          other.sourceHash == this.sourceHash &&
          other.importedAt == this.importedAt &&
          other.deckCount == this.deckCount &&
          other.noteCount == this.noteCount &&
          other.cardCount == this.cardCount &&
          other.mediaCount == this.mediaCount &&
          other.notetypesJson == this.notetypesJson &&
          other.aiEnhanced == this.aiEnhanced &&
          other.version == this.version);
}

class AnkiImportsCompanion extends UpdateCompanion<AnkiImport> {
  final Value<String> importId;
  final Value<String> sourcePath;
  final Value<String> sourceHash;
  final Value<int> importedAt;
  final Value<int> deckCount;
  final Value<int> noteCount;
  final Value<int> cardCount;
  final Value<int> mediaCount;
  final Value<String> notetypesJson;
  final Value<bool> aiEnhanced;
  final Value<int> version;
  final Value<int> rowid;
  const AnkiImportsCompanion({
    this.importId = const Value.absent(),
    this.sourcePath = const Value.absent(),
    this.sourceHash = const Value.absent(),
    this.importedAt = const Value.absent(),
    this.deckCount = const Value.absent(),
    this.noteCount = const Value.absent(),
    this.cardCount = const Value.absent(),
    this.mediaCount = const Value.absent(),
    this.notetypesJson = const Value.absent(),
    this.aiEnhanced = const Value.absent(),
    this.version = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  AnkiImportsCompanion.insert({
    required String importId,
    required String sourcePath,
    required String sourceHash,
    required int importedAt,
    this.deckCount = const Value.absent(),
    this.noteCount = const Value.absent(),
    this.cardCount = const Value.absent(),
    this.mediaCount = const Value.absent(),
    this.notetypesJson = const Value.absent(),
    this.aiEnhanced = const Value.absent(),
    this.version = const Value.absent(),
    this.rowid = const Value.absent(),
  })  : importId = Value(importId),
        sourcePath = Value(sourcePath),
        sourceHash = Value(sourceHash),
        importedAt = Value(importedAt);
  static Insertable<AnkiImport> custom({
    Expression<String>? importId,
    Expression<String>? sourcePath,
    Expression<String>? sourceHash,
    Expression<int>? importedAt,
    Expression<int>? deckCount,
    Expression<int>? noteCount,
    Expression<int>? cardCount,
    Expression<int>? mediaCount,
    Expression<String>? notetypesJson,
    Expression<bool>? aiEnhanced,
    Expression<int>? version,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (importId != null) 'import_id': importId,
      if (sourcePath != null) 'source_path': sourcePath,
      if (sourceHash != null) 'source_hash': sourceHash,
      if (importedAt != null) 'imported_at': importedAt,
      if (deckCount != null) 'deck_count': deckCount,
      if (noteCount != null) 'note_count': noteCount,
      if (cardCount != null) 'card_count': cardCount,
      if (mediaCount != null) 'media_count': mediaCount,
      if (notetypesJson != null) 'notetypes_json': notetypesJson,
      if (aiEnhanced != null) 'ai_enhanced': aiEnhanced,
      if (version != null) 'version': version,
      if (rowid != null) 'rowid': rowid,
    });
  }

  AnkiImportsCompanion copyWith(
      {Value<String>? importId,
      Value<String>? sourcePath,
      Value<String>? sourceHash,
      Value<int>? importedAt,
      Value<int>? deckCount,
      Value<int>? noteCount,
      Value<int>? cardCount,
      Value<int>? mediaCount,
      Value<String>? notetypesJson,
      Value<bool>? aiEnhanced,
      Value<int>? version,
      Value<int>? rowid}) {
    return AnkiImportsCompanion(
      importId: importId ?? this.importId,
      sourcePath: sourcePath ?? this.sourcePath,
      sourceHash: sourceHash ?? this.sourceHash,
      importedAt: importedAt ?? this.importedAt,
      deckCount: deckCount ?? this.deckCount,
      noteCount: noteCount ?? this.noteCount,
      cardCount: cardCount ?? this.cardCount,
      mediaCount: mediaCount ?? this.mediaCount,
      notetypesJson: notetypesJson ?? this.notetypesJson,
      aiEnhanced: aiEnhanced ?? this.aiEnhanced,
      version: version ?? this.version,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (importId.present) {
      map['import_id'] = Variable<String>(importId.value);
    }
    if (sourcePath.present) {
      map['source_path'] = Variable<String>(sourcePath.value);
    }
    if (sourceHash.present) {
      map['source_hash'] = Variable<String>(sourceHash.value);
    }
    if (importedAt.present) {
      map['imported_at'] = Variable<int>(importedAt.value);
    }
    if (deckCount.present) {
      map['deck_count'] = Variable<int>(deckCount.value);
    }
    if (noteCount.present) {
      map['note_count'] = Variable<int>(noteCount.value);
    }
    if (cardCount.present) {
      map['card_count'] = Variable<int>(cardCount.value);
    }
    if (mediaCount.present) {
      map['media_count'] = Variable<int>(mediaCount.value);
    }
    if (notetypesJson.present) {
      map['notetypes_json'] = Variable<String>(notetypesJson.value);
    }
    if (aiEnhanced.present) {
      map['ai_enhanced'] = Variable<bool>(aiEnhanced.value);
    }
    if (version.present) {
      map['version'] = Variable<int>(version.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('AnkiImportsCompanion(')
          ..write('importId: $importId, ')
          ..write('sourcePath: $sourcePath, ')
          ..write('sourceHash: $sourceHash, ')
          ..write('importedAt: $importedAt, ')
          ..write('deckCount: $deckCount, ')
          ..write('noteCount: $noteCount, ')
          ..write('cardCount: $cardCount, ')
          ..write('mediaCount: $mediaCount, ')
          ..write('notetypesJson: $notetypesJson, ')
          ..write('aiEnhanced: $aiEnhanced, ')
          ..write('version: $version, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $AnkiNotetypesTable extends AnkiNotetypes
    with TableInfo<$AnkiNotetypesTable, AnkiNotetypeRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $AnkiNotetypesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _importIdMeta =
      const VerificationMeta('importId');
  @override
  late final GeneratedColumn<String> importId = GeneratedColumn<String>(
      'import_id', aliasedName, false,
      type: DriftSqlType.string,
      requiredDuringInsert: true,
      $customConstraints:
          'NOT NULL REFERENCES anki_imports(import_id) ON DELETE CASCADE');
  static const VerificationMeta _midMeta = const VerificationMeta('mid');
  @override
  late final GeneratedColumn<int> mid = GeneratedColumn<int>(
      'mid', aliasedName, false,
      type: DriftSqlType.int, requiredDuringInsert: true);
  static const VerificationMeta _nameMeta = const VerificationMeta('name');
  @override
  late final GeneratedColumn<String> name = GeneratedColumn<String>(
      'name', aliasedName, false,
      type: DriftSqlType.string,
      requiredDuringInsert: false,
      defaultValue: const Constant(''));
  static const VerificationMeta _isClozeMeta =
      const VerificationMeta('isCloze');
  @override
  late final GeneratedColumn<bool> isCloze = GeneratedColumn<bool>(
      'is_cloze', aliasedName, false,
      type: DriftSqlType.bool,
      requiredDuringInsert: false,
      defaultConstraints:
          GeneratedColumn.constraintIsAlways('CHECK ("is_cloze" IN (0, 1))'),
      defaultValue: const Constant(false));
  static const VerificationMeta _fieldNamesJsonMeta =
      const VerificationMeta('fieldNamesJson');
  @override
  late final GeneratedColumn<String> fieldNamesJson = GeneratedColumn<String>(
      'field_names_json', aliasedName, false,
      type: DriftSqlType.string,
      requiredDuringInsert: false,
      defaultValue: const Constant('[]'));
  static const VerificationMeta _templatesJsonMeta =
      const VerificationMeta('templatesJson');
  @override
  late final GeneratedColumn<String> templatesJson = GeneratedColumn<String>(
      'templates_json', aliasedName, false,
      type: DriftSqlType.string,
      requiredDuringInsert: false,
      defaultValue: const Constant('[]'));
  static const VerificationMeta _cssMeta = const VerificationMeta('css');
  @override
  late final GeneratedColumn<String> css = GeneratedColumn<String>(
      'css', aliasedName, false,
      type: DriftSqlType.string,
      requiredDuringInsert: false,
      defaultValue: const Constant(''));
  static const VerificationMeta _allowJsMeta =
      const VerificationMeta('allowJs');
  @override
  late final GeneratedColumn<bool> allowJs = GeneratedColumn<bool>(
      'allow_js', aliasedName, false,
      type: DriftSqlType.bool,
      requiredDuringInsert: false,
      defaultConstraints:
          GeneratedColumn.constraintIsAlways('CHECK ("allow_js" IN (0, 1))'),
      defaultValue: const Constant(false));
  @override
  List<GeneratedColumn> get $columns => [
        importId,
        mid,
        name,
        isCloze,
        fieldNamesJson,
        templatesJson,
        css,
        allowJs
      ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'anki_notetypes';
  @override
  VerificationContext validateIntegrity(Insertable<AnkiNotetypeRow> instance,
      {bool isInserting = false}) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('import_id')) {
      context.handle(_importIdMeta,
          importId.isAcceptableOrUnknown(data['import_id']!, _importIdMeta));
    } else if (isInserting) {
      context.missing(_importIdMeta);
    }
    if (data.containsKey('mid')) {
      context.handle(
          _midMeta, mid.isAcceptableOrUnknown(data['mid']!, _midMeta));
    } else if (isInserting) {
      context.missing(_midMeta);
    }
    if (data.containsKey('name')) {
      context.handle(
          _nameMeta, name.isAcceptableOrUnknown(data['name']!, _nameMeta));
    }
    if (data.containsKey('is_cloze')) {
      context.handle(_isClozeMeta,
          isCloze.isAcceptableOrUnknown(data['is_cloze']!, _isClozeMeta));
    }
    if (data.containsKey('field_names_json')) {
      context.handle(
          _fieldNamesJsonMeta,
          fieldNamesJson.isAcceptableOrUnknown(
              data['field_names_json']!, _fieldNamesJsonMeta));
    }
    if (data.containsKey('templates_json')) {
      context.handle(
          _templatesJsonMeta,
          templatesJson.isAcceptableOrUnknown(
              data['templates_json']!, _templatesJsonMeta));
    }
    if (data.containsKey('css')) {
      context.handle(
          _cssMeta, css.isAcceptableOrUnknown(data['css']!, _cssMeta));
    }
    if (data.containsKey('allow_js')) {
      context.handle(_allowJsMeta,
          allowJs.isAcceptableOrUnknown(data['allow_js']!, _allowJsMeta));
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {importId, mid};
  @override
  AnkiNotetypeRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return AnkiNotetypeRow(
      importId: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}import_id'])!,
      mid: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}mid'])!,
      name: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}name'])!,
      isCloze: attachedDatabase.typeMapping
          .read(DriftSqlType.bool, data['${effectivePrefix}is_cloze'])!,
      fieldNamesJson: attachedDatabase.typeMapping.read(
          DriftSqlType.string, data['${effectivePrefix}field_names_json'])!,
      templatesJson: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}templates_json'])!,
      css: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}css'])!,
      allowJs: attachedDatabase.typeMapping
          .read(DriftSqlType.bool, data['${effectivePrefix}allow_js'])!,
    );
  }

  @override
  $AnkiNotetypesTable createAlias(String alias) {
    return $AnkiNotetypesTable(attachedDatabase, alias);
  }
}

class AnkiNotetypeRow extends DataClass implements Insertable<AnkiNotetypeRow> {
  final String importId;
  final int mid;
  final String name;
  final bool isCloze;
  final String fieldNamesJson;
  final String templatesJson;
  final String css;

  /// Whether this notetype's qfmt/afmt contains `<script>` / `on*=` handlers,
  /// enabling JS in the fidelity WebView (decision 3: default off + container
  /// isolation via navigationDelegate + restricted file access).
  final bool allowJs;
  const AnkiNotetypeRow(
      {required this.importId,
      required this.mid,
      required this.name,
      required this.isCloze,
      required this.fieldNamesJson,
      required this.templatesJson,
      required this.css,
      required this.allowJs});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['import_id'] = Variable<String>(importId);
    map['mid'] = Variable<int>(mid);
    map['name'] = Variable<String>(name);
    map['is_cloze'] = Variable<bool>(isCloze);
    map['field_names_json'] = Variable<String>(fieldNamesJson);
    map['templates_json'] = Variable<String>(templatesJson);
    map['css'] = Variable<String>(css);
    map['allow_js'] = Variable<bool>(allowJs);
    return map;
  }

  AnkiNotetypesCompanion toCompanion(bool nullToAbsent) {
    return AnkiNotetypesCompanion(
      importId: Value(importId),
      mid: Value(mid),
      name: Value(name),
      isCloze: Value(isCloze),
      fieldNamesJson: Value(fieldNamesJson),
      templatesJson: Value(templatesJson),
      css: Value(css),
      allowJs: Value(allowJs),
    );
  }

  factory AnkiNotetypeRow.fromJson(Map<String, dynamic> json,
      {ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return AnkiNotetypeRow(
      importId: serializer.fromJson<String>(json['importId']),
      mid: serializer.fromJson<int>(json['mid']),
      name: serializer.fromJson<String>(json['name']),
      isCloze: serializer.fromJson<bool>(json['isCloze']),
      fieldNamesJson: serializer.fromJson<String>(json['fieldNamesJson']),
      templatesJson: serializer.fromJson<String>(json['templatesJson']),
      css: serializer.fromJson<String>(json['css']),
      allowJs: serializer.fromJson<bool>(json['allowJs']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'importId': serializer.toJson<String>(importId),
      'mid': serializer.toJson<int>(mid),
      'name': serializer.toJson<String>(name),
      'isCloze': serializer.toJson<bool>(isCloze),
      'fieldNamesJson': serializer.toJson<String>(fieldNamesJson),
      'templatesJson': serializer.toJson<String>(templatesJson),
      'css': serializer.toJson<String>(css),
      'allowJs': serializer.toJson<bool>(allowJs),
    };
  }

  AnkiNotetypeRow copyWith(
          {String? importId,
          int? mid,
          String? name,
          bool? isCloze,
          String? fieldNamesJson,
          String? templatesJson,
          String? css,
          bool? allowJs}) =>
      AnkiNotetypeRow(
        importId: importId ?? this.importId,
        mid: mid ?? this.mid,
        name: name ?? this.name,
        isCloze: isCloze ?? this.isCloze,
        fieldNamesJson: fieldNamesJson ?? this.fieldNamesJson,
        templatesJson: templatesJson ?? this.templatesJson,
        css: css ?? this.css,
        allowJs: allowJs ?? this.allowJs,
      );
  AnkiNotetypeRow copyWithCompanion(AnkiNotetypesCompanion data) {
    return AnkiNotetypeRow(
      importId: data.importId.present ? data.importId.value : this.importId,
      mid: data.mid.present ? data.mid.value : this.mid,
      name: data.name.present ? data.name.value : this.name,
      isCloze: data.isCloze.present ? data.isCloze.value : this.isCloze,
      fieldNamesJson: data.fieldNamesJson.present
          ? data.fieldNamesJson.value
          : this.fieldNamesJson,
      templatesJson: data.templatesJson.present
          ? data.templatesJson.value
          : this.templatesJson,
      css: data.css.present ? data.css.value : this.css,
      allowJs: data.allowJs.present ? data.allowJs.value : this.allowJs,
    );
  }

  @override
  String toString() {
    return (StringBuffer('AnkiNotetypeRow(')
          ..write('importId: $importId, ')
          ..write('mid: $mid, ')
          ..write('name: $name, ')
          ..write('isCloze: $isCloze, ')
          ..write('fieldNamesJson: $fieldNamesJson, ')
          ..write('templatesJson: $templatesJson, ')
          ..write('css: $css, ')
          ..write('allowJs: $allowJs')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(importId, mid, name, isCloze, fieldNamesJson,
      templatesJson, css, allowJs);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is AnkiNotetypeRow &&
          other.importId == this.importId &&
          other.mid == this.mid &&
          other.name == this.name &&
          other.isCloze == this.isCloze &&
          other.fieldNamesJson == this.fieldNamesJson &&
          other.templatesJson == this.templatesJson &&
          other.css == this.css &&
          other.allowJs == this.allowJs);
}

class AnkiNotetypesCompanion extends UpdateCompanion<AnkiNotetypeRow> {
  final Value<String> importId;
  final Value<int> mid;
  final Value<String> name;
  final Value<bool> isCloze;
  final Value<String> fieldNamesJson;
  final Value<String> templatesJson;
  final Value<String> css;
  final Value<bool> allowJs;
  final Value<int> rowid;
  const AnkiNotetypesCompanion({
    this.importId = const Value.absent(),
    this.mid = const Value.absent(),
    this.name = const Value.absent(),
    this.isCloze = const Value.absent(),
    this.fieldNamesJson = const Value.absent(),
    this.templatesJson = const Value.absent(),
    this.css = const Value.absent(),
    this.allowJs = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  AnkiNotetypesCompanion.insert({
    required String importId,
    required int mid,
    this.name = const Value.absent(),
    this.isCloze = const Value.absent(),
    this.fieldNamesJson = const Value.absent(),
    this.templatesJson = const Value.absent(),
    this.css = const Value.absent(),
    this.allowJs = const Value.absent(),
    this.rowid = const Value.absent(),
  })  : importId = Value(importId),
        mid = Value(mid);
  static Insertable<AnkiNotetypeRow> custom({
    Expression<String>? importId,
    Expression<int>? mid,
    Expression<String>? name,
    Expression<bool>? isCloze,
    Expression<String>? fieldNamesJson,
    Expression<String>? templatesJson,
    Expression<String>? css,
    Expression<bool>? allowJs,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (importId != null) 'import_id': importId,
      if (mid != null) 'mid': mid,
      if (name != null) 'name': name,
      if (isCloze != null) 'is_cloze': isCloze,
      if (fieldNamesJson != null) 'field_names_json': fieldNamesJson,
      if (templatesJson != null) 'templates_json': templatesJson,
      if (css != null) 'css': css,
      if (allowJs != null) 'allow_js': allowJs,
      if (rowid != null) 'rowid': rowid,
    });
  }

  AnkiNotetypesCompanion copyWith(
      {Value<String>? importId,
      Value<int>? mid,
      Value<String>? name,
      Value<bool>? isCloze,
      Value<String>? fieldNamesJson,
      Value<String>? templatesJson,
      Value<String>? css,
      Value<bool>? allowJs,
      Value<int>? rowid}) {
    return AnkiNotetypesCompanion(
      importId: importId ?? this.importId,
      mid: mid ?? this.mid,
      name: name ?? this.name,
      isCloze: isCloze ?? this.isCloze,
      fieldNamesJson: fieldNamesJson ?? this.fieldNamesJson,
      templatesJson: templatesJson ?? this.templatesJson,
      css: css ?? this.css,
      allowJs: allowJs ?? this.allowJs,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (importId.present) {
      map['import_id'] = Variable<String>(importId.value);
    }
    if (mid.present) {
      map['mid'] = Variable<int>(mid.value);
    }
    if (name.present) {
      map['name'] = Variable<String>(name.value);
    }
    if (isCloze.present) {
      map['is_cloze'] = Variable<bool>(isCloze.value);
    }
    if (fieldNamesJson.present) {
      map['field_names_json'] = Variable<String>(fieldNamesJson.value);
    }
    if (templatesJson.present) {
      map['templates_json'] = Variable<String>(templatesJson.value);
    }
    if (css.present) {
      map['css'] = Variable<String>(css.value);
    }
    if (allowJs.present) {
      map['allow_js'] = Variable<bool>(allowJs.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('AnkiNotetypesCompanion(')
          ..write('importId: $importId, ')
          ..write('mid: $mid, ')
          ..write('name: $name, ')
          ..write('isCloze: $isCloze, ')
          ..write('fieldNamesJson: $fieldNamesJson, ')
          ..write('templatesJson: $templatesJson, ')
          ..write('css: $css, ')
          ..write('allowJs: $allowJs, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $AnkiNotesTable extends AnkiNotes
    with TableInfo<$AnkiNotesTable, AnkiNoteRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $AnkiNotesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _importIdMeta =
      const VerificationMeta('importId');
  @override
  late final GeneratedColumn<String> importId = GeneratedColumn<String>(
      'import_id', aliasedName, false,
      type: DriftSqlType.string,
      requiredDuringInsert: true,
      $customConstraints:
          'NOT NULL REFERENCES anki_imports(import_id) ON DELETE CASCADE');
  static const VerificationMeta _noteIdMeta = const VerificationMeta('noteId');
  @override
  late final GeneratedColumn<int> noteId = GeneratedColumn<int>(
      'note_id', aliasedName, false,
      type: DriftSqlType.int, requiredDuringInsert: true);
  static const VerificationMeta _midMeta = const VerificationMeta('mid');
  @override
  late final GeneratedColumn<int> mid = GeneratedColumn<int>(
      'mid', aliasedName, false,
      type: DriftSqlType.int, requiredDuringInsert: true);
  static const VerificationMeta _tagsMeta = const VerificationMeta('tags');
  @override
  late final GeneratedColumn<String> tags = GeneratedColumn<String>(
      'tags', aliasedName, false,
      type: DriftSqlType.string,
      requiredDuringInsert: false,
      defaultValue: const Constant(''));
  static const VerificationMeta _fieldsJsonMeta =
      const VerificationMeta('fieldsJson');
  @override
  late final GeneratedColumn<String> fieldsJson = GeneratedColumn<String>(
      'fields_json', aliasedName, false,
      type: DriftSqlType.string,
      requiredDuringInsert: false,
      defaultValue: const Constant('[]'));
  static const VerificationMeta _sfldMeta = const VerificationMeta('sfld');
  @override
  late final GeneratedColumn<String> sfld = GeneratedColumn<String>(
      'sfld', aliasedName, false,
      type: DriftSqlType.string,
      requiredDuringInsert: false,
      defaultValue: const Constant(''));
  static const VerificationMeta _guidMeta = const VerificationMeta('guid');
  @override
  late final GeneratedColumn<String> guid = GeneratedColumn<String>(
      'guid', aliasedName, false,
      type: DriftSqlType.string,
      requiredDuringInsert: false,
      defaultValue: const Constant(''));
  static const VerificationMeta _modMeta = const VerificationMeta('mod');
  @override
  late final GeneratedColumn<int> mod = GeneratedColumn<int>(
      'mod', aliasedName, false,
      type: DriftSqlType.int,
      requiredDuringInsert: false,
      defaultValue: const Constant(0));
  @override
  List<GeneratedColumn> get $columns =>
      [importId, noteId, mid, tags, fieldsJson, sfld, guid, mod];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'anki_notes';
  @override
  VerificationContext validateIntegrity(Insertable<AnkiNoteRow> instance,
      {bool isInserting = false}) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('import_id')) {
      context.handle(_importIdMeta,
          importId.isAcceptableOrUnknown(data['import_id']!, _importIdMeta));
    } else if (isInserting) {
      context.missing(_importIdMeta);
    }
    if (data.containsKey('note_id')) {
      context.handle(_noteIdMeta,
          noteId.isAcceptableOrUnknown(data['note_id']!, _noteIdMeta));
    } else if (isInserting) {
      context.missing(_noteIdMeta);
    }
    if (data.containsKey('mid')) {
      context.handle(
          _midMeta, mid.isAcceptableOrUnknown(data['mid']!, _midMeta));
    } else if (isInserting) {
      context.missing(_midMeta);
    }
    if (data.containsKey('tags')) {
      context.handle(
          _tagsMeta, tags.isAcceptableOrUnknown(data['tags']!, _tagsMeta));
    }
    if (data.containsKey('fields_json')) {
      context.handle(
          _fieldsJsonMeta,
          fieldsJson.isAcceptableOrUnknown(
              data['fields_json']!, _fieldsJsonMeta));
    }
    if (data.containsKey('sfld')) {
      context.handle(
          _sfldMeta, sfld.isAcceptableOrUnknown(data['sfld']!, _sfldMeta));
    }
    if (data.containsKey('guid')) {
      context.handle(
          _guidMeta, guid.isAcceptableOrUnknown(data['guid']!, _guidMeta));
    }
    if (data.containsKey('mod')) {
      context.handle(
          _modMeta, mod.isAcceptableOrUnknown(data['mod']!, _modMeta));
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {importId, noteId};
  @override
  AnkiNoteRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return AnkiNoteRow(
      importId: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}import_id'])!,
      noteId: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}note_id'])!,
      mid: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}mid'])!,
      tags: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}tags'])!,
      fieldsJson: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}fields_json'])!,
      sfld: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}sfld'])!,
      guid: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}guid'])!,
      mod: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}mod'])!,
    );
  }

  @override
  $AnkiNotesTable createAlias(String alias) {
    return $AnkiNotesTable(attachedDatabase, alias);
  }
}

class AnkiNoteRow extends DataClass implements Insertable<AnkiNoteRow> {
  final String importId;
  final int noteId;
  final int mid;
  final String tags;
  final String fieldsJson;
  final String sfld;
  final String guid;
  final int mod;
  const AnkiNoteRow(
      {required this.importId,
      required this.noteId,
      required this.mid,
      required this.tags,
      required this.fieldsJson,
      required this.sfld,
      required this.guid,
      required this.mod});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['import_id'] = Variable<String>(importId);
    map['note_id'] = Variable<int>(noteId);
    map['mid'] = Variable<int>(mid);
    map['tags'] = Variable<String>(tags);
    map['fields_json'] = Variable<String>(fieldsJson);
    map['sfld'] = Variable<String>(sfld);
    map['guid'] = Variable<String>(guid);
    map['mod'] = Variable<int>(mod);
    return map;
  }

  AnkiNotesCompanion toCompanion(bool nullToAbsent) {
    return AnkiNotesCompanion(
      importId: Value(importId),
      noteId: Value(noteId),
      mid: Value(mid),
      tags: Value(tags),
      fieldsJson: Value(fieldsJson),
      sfld: Value(sfld),
      guid: Value(guid),
      mod: Value(mod),
    );
  }

  factory AnkiNoteRow.fromJson(Map<String, dynamic> json,
      {ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return AnkiNoteRow(
      importId: serializer.fromJson<String>(json['importId']),
      noteId: serializer.fromJson<int>(json['noteId']),
      mid: serializer.fromJson<int>(json['mid']),
      tags: serializer.fromJson<String>(json['tags']),
      fieldsJson: serializer.fromJson<String>(json['fieldsJson']),
      sfld: serializer.fromJson<String>(json['sfld']),
      guid: serializer.fromJson<String>(json['guid']),
      mod: serializer.fromJson<int>(json['mod']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'importId': serializer.toJson<String>(importId),
      'noteId': serializer.toJson<int>(noteId),
      'mid': serializer.toJson<int>(mid),
      'tags': serializer.toJson<String>(tags),
      'fieldsJson': serializer.toJson<String>(fieldsJson),
      'sfld': serializer.toJson<String>(sfld),
      'guid': serializer.toJson<String>(guid),
      'mod': serializer.toJson<int>(mod),
    };
  }

  AnkiNoteRow copyWith(
          {String? importId,
          int? noteId,
          int? mid,
          String? tags,
          String? fieldsJson,
          String? sfld,
          String? guid,
          int? mod}) =>
      AnkiNoteRow(
        importId: importId ?? this.importId,
        noteId: noteId ?? this.noteId,
        mid: mid ?? this.mid,
        tags: tags ?? this.tags,
        fieldsJson: fieldsJson ?? this.fieldsJson,
        sfld: sfld ?? this.sfld,
        guid: guid ?? this.guid,
        mod: mod ?? this.mod,
      );
  AnkiNoteRow copyWithCompanion(AnkiNotesCompanion data) {
    return AnkiNoteRow(
      importId: data.importId.present ? data.importId.value : this.importId,
      noteId: data.noteId.present ? data.noteId.value : this.noteId,
      mid: data.mid.present ? data.mid.value : this.mid,
      tags: data.tags.present ? data.tags.value : this.tags,
      fieldsJson:
          data.fieldsJson.present ? data.fieldsJson.value : this.fieldsJson,
      sfld: data.sfld.present ? data.sfld.value : this.sfld,
      guid: data.guid.present ? data.guid.value : this.guid,
      mod: data.mod.present ? data.mod.value : this.mod,
    );
  }

  @override
  String toString() {
    return (StringBuffer('AnkiNoteRow(')
          ..write('importId: $importId, ')
          ..write('noteId: $noteId, ')
          ..write('mid: $mid, ')
          ..write('tags: $tags, ')
          ..write('fieldsJson: $fieldsJson, ')
          ..write('sfld: $sfld, ')
          ..write('guid: $guid, ')
          ..write('mod: $mod')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode =>
      Object.hash(importId, noteId, mid, tags, fieldsJson, sfld, guid, mod);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is AnkiNoteRow &&
          other.importId == this.importId &&
          other.noteId == this.noteId &&
          other.mid == this.mid &&
          other.tags == this.tags &&
          other.fieldsJson == this.fieldsJson &&
          other.sfld == this.sfld &&
          other.guid == this.guid &&
          other.mod == this.mod);
}

class AnkiNotesCompanion extends UpdateCompanion<AnkiNoteRow> {
  final Value<String> importId;
  final Value<int> noteId;
  final Value<int> mid;
  final Value<String> tags;
  final Value<String> fieldsJson;
  final Value<String> sfld;
  final Value<String> guid;
  final Value<int> mod;
  final Value<int> rowid;
  const AnkiNotesCompanion({
    this.importId = const Value.absent(),
    this.noteId = const Value.absent(),
    this.mid = const Value.absent(),
    this.tags = const Value.absent(),
    this.fieldsJson = const Value.absent(),
    this.sfld = const Value.absent(),
    this.guid = const Value.absent(),
    this.mod = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  AnkiNotesCompanion.insert({
    required String importId,
    required int noteId,
    required int mid,
    this.tags = const Value.absent(),
    this.fieldsJson = const Value.absent(),
    this.sfld = const Value.absent(),
    this.guid = const Value.absent(),
    this.mod = const Value.absent(),
    this.rowid = const Value.absent(),
  })  : importId = Value(importId),
        noteId = Value(noteId),
        mid = Value(mid);
  static Insertable<AnkiNoteRow> custom({
    Expression<String>? importId,
    Expression<int>? noteId,
    Expression<int>? mid,
    Expression<String>? tags,
    Expression<String>? fieldsJson,
    Expression<String>? sfld,
    Expression<String>? guid,
    Expression<int>? mod,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (importId != null) 'import_id': importId,
      if (noteId != null) 'note_id': noteId,
      if (mid != null) 'mid': mid,
      if (tags != null) 'tags': tags,
      if (fieldsJson != null) 'fields_json': fieldsJson,
      if (sfld != null) 'sfld': sfld,
      if (guid != null) 'guid': guid,
      if (mod != null) 'mod': mod,
      if (rowid != null) 'rowid': rowid,
    });
  }

  AnkiNotesCompanion copyWith(
      {Value<String>? importId,
      Value<int>? noteId,
      Value<int>? mid,
      Value<String>? tags,
      Value<String>? fieldsJson,
      Value<String>? sfld,
      Value<String>? guid,
      Value<int>? mod,
      Value<int>? rowid}) {
    return AnkiNotesCompanion(
      importId: importId ?? this.importId,
      noteId: noteId ?? this.noteId,
      mid: mid ?? this.mid,
      tags: tags ?? this.tags,
      fieldsJson: fieldsJson ?? this.fieldsJson,
      sfld: sfld ?? this.sfld,
      guid: guid ?? this.guid,
      mod: mod ?? this.mod,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (importId.present) {
      map['import_id'] = Variable<String>(importId.value);
    }
    if (noteId.present) {
      map['note_id'] = Variable<int>(noteId.value);
    }
    if (mid.present) {
      map['mid'] = Variable<int>(mid.value);
    }
    if (tags.present) {
      map['tags'] = Variable<String>(tags.value);
    }
    if (fieldsJson.present) {
      map['fields_json'] = Variable<String>(fieldsJson.value);
    }
    if (sfld.present) {
      map['sfld'] = Variable<String>(sfld.value);
    }
    if (guid.present) {
      map['guid'] = Variable<String>(guid.value);
    }
    if (mod.present) {
      map['mod'] = Variable<int>(mod.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('AnkiNotesCompanion(')
          ..write('importId: $importId, ')
          ..write('noteId: $noteId, ')
          ..write('mid: $mid, ')
          ..write('tags: $tags, ')
          ..write('fieldsJson: $fieldsJson, ')
          ..write('sfld: $sfld, ')
          ..write('guid: $guid, ')
          ..write('mod: $mod, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $AnkiCardsMetaTable extends AnkiCardsMeta
    with TableInfo<$AnkiCardsMetaTable, AnkiCardMetaRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $AnkiCardsMetaTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _importIdMeta =
      const VerificationMeta('importId');
  @override
  late final GeneratedColumn<String> importId = GeneratedColumn<String>(
      'import_id', aliasedName, false,
      type: DriftSqlType.string,
      requiredDuringInsert: true,
      $customConstraints:
          'NOT NULL REFERENCES anki_imports(import_id) ON DELETE CASCADE');
  static const VerificationMeta _cardIdMeta = const VerificationMeta('cardId');
  @override
  late final GeneratedColumn<int> cardId = GeneratedColumn<int>(
      'card_id', aliasedName, false,
      type: DriftSqlType.int, requiredDuringInsert: true);
  static const VerificationMeta _noteIdMeta = const VerificationMeta('noteId');
  @override
  late final GeneratedColumn<int> noteId = GeneratedColumn<int>(
      'note_id', aliasedName, false,
      type: DriftSqlType.int, requiredDuringInsert: true);
  static const VerificationMeta _ordMeta = const VerificationMeta('ord');
  @override
  late final GeneratedColumn<int> ord = GeneratedColumn<int>(
      'ord', aliasedName, false,
      type: DriftSqlType.int,
      requiredDuringInsert: false,
      defaultValue: const Constant(0));
  static const VerificationMeta _didMeta = const VerificationMeta('did');
  @override
  late final GeneratedColumn<int> did = GeneratedColumn<int>(
      'did', aliasedName, false,
      type: DriftSqlType.int,
      requiredDuringInsert: false,
      defaultValue: const Constant(0));
  static const VerificationMeta _wordIdMeta = const VerificationMeta('wordId');
  @override
  late final GeneratedColumn<String> wordId = GeneratedColumn<String>(
      'word_id', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _renderModeMeta =
      const VerificationMeta('renderMode');
  @override
  late final GeneratedColumn<String> renderMode = GeneratedColumn<String>(
      'render_mode', aliasedName, false,
      type: DriftSqlType.string,
      requiredDuringInsert: false,
      defaultValue: const Constant('hybrid'));
  static const VerificationMeta _schedulingJsonMeta =
      const VerificationMeta('schedulingJson');
  @override
  late final GeneratedColumn<String> schedulingJson = GeneratedColumn<String>(
      'scheduling_json', aliasedName, false,
      type: DriftSqlType.string,
      requiredDuringInsert: false,
      defaultValue: const Constant('{}'));
  @override
  List<GeneratedColumn> get $columns =>
      [importId, cardId, noteId, ord, did, wordId, renderMode, schedulingJson];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'anki_cards_meta';
  @override
  VerificationContext validateIntegrity(Insertable<AnkiCardMetaRow> instance,
      {bool isInserting = false}) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('import_id')) {
      context.handle(_importIdMeta,
          importId.isAcceptableOrUnknown(data['import_id']!, _importIdMeta));
    } else if (isInserting) {
      context.missing(_importIdMeta);
    }
    if (data.containsKey('card_id')) {
      context.handle(_cardIdMeta,
          cardId.isAcceptableOrUnknown(data['card_id']!, _cardIdMeta));
    } else if (isInserting) {
      context.missing(_cardIdMeta);
    }
    if (data.containsKey('note_id')) {
      context.handle(_noteIdMeta,
          noteId.isAcceptableOrUnknown(data['note_id']!, _noteIdMeta));
    } else if (isInserting) {
      context.missing(_noteIdMeta);
    }
    if (data.containsKey('ord')) {
      context.handle(
          _ordMeta, ord.isAcceptableOrUnknown(data['ord']!, _ordMeta));
    }
    if (data.containsKey('did')) {
      context.handle(
          _didMeta, did.isAcceptableOrUnknown(data['did']!, _didMeta));
    }
    if (data.containsKey('word_id')) {
      context.handle(_wordIdMeta,
          wordId.isAcceptableOrUnknown(data['word_id']!, _wordIdMeta));
    } else if (isInserting) {
      context.missing(_wordIdMeta);
    }
    if (data.containsKey('render_mode')) {
      context.handle(
          _renderModeMeta,
          renderMode.isAcceptableOrUnknown(
              data['render_mode']!, _renderModeMeta));
    }
    if (data.containsKey('scheduling_json')) {
      context.handle(
          _schedulingJsonMeta,
          schedulingJson.isAcceptableOrUnknown(
              data['scheduling_json']!, _schedulingJsonMeta));
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {importId, cardId};
  @override
  AnkiCardMetaRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return AnkiCardMetaRow(
      importId: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}import_id'])!,
      cardId: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}card_id'])!,
      noteId: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}note_id'])!,
      ord: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}ord'])!,
      did: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}did'])!,
      wordId: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}word_id'])!,
      renderMode: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}render_mode'])!,
      schedulingJson: attachedDatabase.typeMapping.read(
          DriftSqlType.string, data['${effectivePrefix}scheduling_json'])!,
    );
  }

  @override
  $AnkiCardsMetaTable createAlias(String alias) {
    return $AnkiCardsMetaTable(attachedDatabase, alias);
  }
}

class AnkiCardMetaRow extends DataClass implements Insertable<AnkiCardMetaRow> {
  final String importId;
  final int cardId;
  final int noteId;
  final int ord;
  final int did;
  final String wordId;
  final String renderMode;
  final String schedulingJson;
  const AnkiCardMetaRow(
      {required this.importId,
      required this.cardId,
      required this.noteId,
      required this.ord,
      required this.did,
      required this.wordId,
      required this.renderMode,
      required this.schedulingJson});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['import_id'] = Variable<String>(importId);
    map['card_id'] = Variable<int>(cardId);
    map['note_id'] = Variable<int>(noteId);
    map['ord'] = Variable<int>(ord);
    map['did'] = Variable<int>(did);
    map['word_id'] = Variable<String>(wordId);
    map['render_mode'] = Variable<String>(renderMode);
    map['scheduling_json'] = Variable<String>(schedulingJson);
    return map;
  }

  AnkiCardsMetaCompanion toCompanion(bool nullToAbsent) {
    return AnkiCardsMetaCompanion(
      importId: Value(importId),
      cardId: Value(cardId),
      noteId: Value(noteId),
      ord: Value(ord),
      did: Value(did),
      wordId: Value(wordId),
      renderMode: Value(renderMode),
      schedulingJson: Value(schedulingJson),
    );
  }

  factory AnkiCardMetaRow.fromJson(Map<String, dynamic> json,
      {ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return AnkiCardMetaRow(
      importId: serializer.fromJson<String>(json['importId']),
      cardId: serializer.fromJson<int>(json['cardId']),
      noteId: serializer.fromJson<int>(json['noteId']),
      ord: serializer.fromJson<int>(json['ord']),
      did: serializer.fromJson<int>(json['did']),
      wordId: serializer.fromJson<String>(json['wordId']),
      renderMode: serializer.fromJson<String>(json['renderMode']),
      schedulingJson: serializer.fromJson<String>(json['schedulingJson']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'importId': serializer.toJson<String>(importId),
      'cardId': serializer.toJson<int>(cardId),
      'noteId': serializer.toJson<int>(noteId),
      'ord': serializer.toJson<int>(ord),
      'did': serializer.toJson<int>(did),
      'wordId': serializer.toJson<String>(wordId),
      'renderMode': serializer.toJson<String>(renderMode),
      'schedulingJson': serializer.toJson<String>(schedulingJson),
    };
  }

  AnkiCardMetaRow copyWith(
          {String? importId,
          int? cardId,
          int? noteId,
          int? ord,
          int? did,
          String? wordId,
          String? renderMode,
          String? schedulingJson}) =>
      AnkiCardMetaRow(
        importId: importId ?? this.importId,
        cardId: cardId ?? this.cardId,
        noteId: noteId ?? this.noteId,
        ord: ord ?? this.ord,
        did: did ?? this.did,
        wordId: wordId ?? this.wordId,
        renderMode: renderMode ?? this.renderMode,
        schedulingJson: schedulingJson ?? this.schedulingJson,
      );
  AnkiCardMetaRow copyWithCompanion(AnkiCardsMetaCompanion data) {
    return AnkiCardMetaRow(
      importId: data.importId.present ? data.importId.value : this.importId,
      cardId: data.cardId.present ? data.cardId.value : this.cardId,
      noteId: data.noteId.present ? data.noteId.value : this.noteId,
      ord: data.ord.present ? data.ord.value : this.ord,
      did: data.did.present ? data.did.value : this.did,
      wordId: data.wordId.present ? data.wordId.value : this.wordId,
      renderMode:
          data.renderMode.present ? data.renderMode.value : this.renderMode,
      schedulingJson: data.schedulingJson.present
          ? data.schedulingJson.value
          : this.schedulingJson,
    );
  }

  @override
  String toString() {
    return (StringBuffer('AnkiCardMetaRow(')
          ..write('importId: $importId, ')
          ..write('cardId: $cardId, ')
          ..write('noteId: $noteId, ')
          ..write('ord: $ord, ')
          ..write('did: $did, ')
          ..write('wordId: $wordId, ')
          ..write('renderMode: $renderMode, ')
          ..write('schedulingJson: $schedulingJson')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
      importId, cardId, noteId, ord, did, wordId, renderMode, schedulingJson);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is AnkiCardMetaRow &&
          other.importId == this.importId &&
          other.cardId == this.cardId &&
          other.noteId == this.noteId &&
          other.ord == this.ord &&
          other.did == this.did &&
          other.wordId == this.wordId &&
          other.renderMode == this.renderMode &&
          other.schedulingJson == this.schedulingJson);
}

class AnkiCardsMetaCompanion extends UpdateCompanion<AnkiCardMetaRow> {
  final Value<String> importId;
  final Value<int> cardId;
  final Value<int> noteId;
  final Value<int> ord;
  final Value<int> did;
  final Value<String> wordId;
  final Value<String> renderMode;
  final Value<String> schedulingJson;
  final Value<int> rowid;
  const AnkiCardsMetaCompanion({
    this.importId = const Value.absent(),
    this.cardId = const Value.absent(),
    this.noteId = const Value.absent(),
    this.ord = const Value.absent(),
    this.did = const Value.absent(),
    this.wordId = const Value.absent(),
    this.renderMode = const Value.absent(),
    this.schedulingJson = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  AnkiCardsMetaCompanion.insert({
    required String importId,
    required int cardId,
    required int noteId,
    this.ord = const Value.absent(),
    this.did = const Value.absent(),
    required String wordId,
    this.renderMode = const Value.absent(),
    this.schedulingJson = const Value.absent(),
    this.rowid = const Value.absent(),
  })  : importId = Value(importId),
        cardId = Value(cardId),
        noteId = Value(noteId),
        wordId = Value(wordId);
  static Insertable<AnkiCardMetaRow> custom({
    Expression<String>? importId,
    Expression<int>? cardId,
    Expression<int>? noteId,
    Expression<int>? ord,
    Expression<int>? did,
    Expression<String>? wordId,
    Expression<String>? renderMode,
    Expression<String>? schedulingJson,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (importId != null) 'import_id': importId,
      if (cardId != null) 'card_id': cardId,
      if (noteId != null) 'note_id': noteId,
      if (ord != null) 'ord': ord,
      if (did != null) 'did': did,
      if (wordId != null) 'word_id': wordId,
      if (renderMode != null) 'render_mode': renderMode,
      if (schedulingJson != null) 'scheduling_json': schedulingJson,
      if (rowid != null) 'rowid': rowid,
    });
  }

  AnkiCardsMetaCompanion copyWith(
      {Value<String>? importId,
      Value<int>? cardId,
      Value<int>? noteId,
      Value<int>? ord,
      Value<int>? did,
      Value<String>? wordId,
      Value<String>? renderMode,
      Value<String>? schedulingJson,
      Value<int>? rowid}) {
    return AnkiCardsMetaCompanion(
      importId: importId ?? this.importId,
      cardId: cardId ?? this.cardId,
      noteId: noteId ?? this.noteId,
      ord: ord ?? this.ord,
      did: did ?? this.did,
      wordId: wordId ?? this.wordId,
      renderMode: renderMode ?? this.renderMode,
      schedulingJson: schedulingJson ?? this.schedulingJson,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (importId.present) {
      map['import_id'] = Variable<String>(importId.value);
    }
    if (cardId.present) {
      map['card_id'] = Variable<int>(cardId.value);
    }
    if (noteId.present) {
      map['note_id'] = Variable<int>(noteId.value);
    }
    if (ord.present) {
      map['ord'] = Variable<int>(ord.value);
    }
    if (did.present) {
      map['did'] = Variable<int>(did.value);
    }
    if (wordId.present) {
      map['word_id'] = Variable<String>(wordId.value);
    }
    if (renderMode.present) {
      map['render_mode'] = Variable<String>(renderMode.value);
    }
    if (schedulingJson.present) {
      map['scheduling_json'] = Variable<String>(schedulingJson.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('AnkiCardsMetaCompanion(')
          ..write('importId: $importId, ')
          ..write('cardId: $cardId, ')
          ..write('noteId: $noteId, ')
          ..write('ord: $ord, ')
          ..write('did: $did, ')
          ..write('wordId: $wordId, ')
          ..write('renderMode: $renderMode, ')
          ..write('schedulingJson: $schedulingJson, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $AnkiPrerenderedHtmlTable extends AnkiPrerenderedHtml
    with TableInfo<$AnkiPrerenderedHtmlTable, AnkiPrerenderedHtmlRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $AnkiPrerenderedHtmlTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _wordIdMeta = const VerificationMeta('wordId');
  @override
  late final GeneratedColumn<String> wordId = GeneratedColumn<String>(
      'word_id', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _frontHtmlMeta =
      const VerificationMeta('frontHtml');
  @override
  late final GeneratedColumn<String> frontHtml = GeneratedColumn<String>(
      'front_html', aliasedName, true,
      type: DriftSqlType.string, requiredDuringInsert: false);
  static const VerificationMeta _backHtmlMeta =
      const VerificationMeta('backHtml');
  @override
  late final GeneratedColumn<String> backHtml = GeneratedColumn<String>(
      'back_html', aliasedName, true,
      type: DriftSqlType.string, requiredDuringInsert: false);
  static const VerificationMeta _capturedAtMeta =
      const VerificationMeta('capturedAt');
  @override
  late final GeneratedColumn<int> capturedAt = GeneratedColumn<int>(
      'captured_at', aliasedName, false,
      type: DriftSqlType.int,
      requiredDuringInsert: false,
      defaultValue: const Constant(0));
  @override
  List<GeneratedColumn> get $columns =>
      [wordId, frontHtml, backHtml, capturedAt];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'anki_prerendered_html';
  @override
  VerificationContext validateIntegrity(
      Insertable<AnkiPrerenderedHtmlRow> instance,
      {bool isInserting = false}) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('word_id')) {
      context.handle(_wordIdMeta,
          wordId.isAcceptableOrUnknown(data['word_id']!, _wordIdMeta));
    } else if (isInserting) {
      context.missing(_wordIdMeta);
    }
    if (data.containsKey('front_html')) {
      context.handle(_frontHtmlMeta,
          frontHtml.isAcceptableOrUnknown(data['front_html']!, _frontHtmlMeta));
    }
    if (data.containsKey('back_html')) {
      context.handle(_backHtmlMeta,
          backHtml.isAcceptableOrUnknown(data['back_html']!, _backHtmlMeta));
    }
    if (data.containsKey('captured_at')) {
      context.handle(
          _capturedAtMeta,
          capturedAt.isAcceptableOrUnknown(
              data['captured_at']!, _capturedAtMeta));
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {wordId};
  @override
  AnkiPrerenderedHtmlRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return AnkiPrerenderedHtmlRow(
      wordId: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}word_id'])!,
      frontHtml: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}front_html']),
      backHtml: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}back_html']),
      capturedAt: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}captured_at'])!,
    );
  }

  @override
  $AnkiPrerenderedHtmlTable createAlias(String alias) {
    return $AnkiPrerenderedHtmlTable(attachedDatabase, alias);
  }
}

class AnkiPrerenderedHtmlRow extends DataClass
    implements Insertable<AnkiPrerenderedHtmlRow> {
  final String wordId;
  final String? frontHtml;
  final String? backHtml;
  final int capturedAt;
  const AnkiPrerenderedHtmlRow(
      {required this.wordId,
      this.frontHtml,
      this.backHtml,
      required this.capturedAt});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['word_id'] = Variable<String>(wordId);
    if (!nullToAbsent || frontHtml != null) {
      map['front_html'] = Variable<String>(frontHtml);
    }
    if (!nullToAbsent || backHtml != null) {
      map['back_html'] = Variable<String>(backHtml);
    }
    map['captured_at'] = Variable<int>(capturedAt);
    return map;
  }

  AnkiPrerenderedHtmlCompanion toCompanion(bool nullToAbsent) {
    return AnkiPrerenderedHtmlCompanion(
      wordId: Value(wordId),
      frontHtml: frontHtml == null && nullToAbsent
          ? const Value.absent()
          : Value(frontHtml),
      backHtml: backHtml == null && nullToAbsent
          ? const Value.absent()
          : Value(backHtml),
      capturedAt: Value(capturedAt),
    );
  }

  factory AnkiPrerenderedHtmlRow.fromJson(Map<String, dynamic> json,
      {ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return AnkiPrerenderedHtmlRow(
      wordId: serializer.fromJson<String>(json['wordId']),
      frontHtml: serializer.fromJson<String?>(json['frontHtml']),
      backHtml: serializer.fromJson<String?>(json['backHtml']),
      capturedAt: serializer.fromJson<int>(json['capturedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'wordId': serializer.toJson<String>(wordId),
      'frontHtml': serializer.toJson<String?>(frontHtml),
      'backHtml': serializer.toJson<String?>(backHtml),
      'capturedAt': serializer.toJson<int>(capturedAt),
    };
  }

  AnkiPrerenderedHtmlRow copyWith(
          {String? wordId,
          Value<String?> frontHtml = const Value.absent(),
          Value<String?> backHtml = const Value.absent(),
          int? capturedAt}) =>
      AnkiPrerenderedHtmlRow(
        wordId: wordId ?? this.wordId,
        frontHtml: frontHtml.present ? frontHtml.value : this.frontHtml,
        backHtml: backHtml.present ? backHtml.value : this.backHtml,
        capturedAt: capturedAt ?? this.capturedAt,
      );
  AnkiPrerenderedHtmlRow copyWithCompanion(AnkiPrerenderedHtmlCompanion data) {
    return AnkiPrerenderedHtmlRow(
      wordId: data.wordId.present ? data.wordId.value : this.wordId,
      frontHtml: data.frontHtml.present ? data.frontHtml.value : this.frontHtml,
      backHtml: data.backHtml.present ? data.backHtml.value : this.backHtml,
      capturedAt:
          data.capturedAt.present ? data.capturedAt.value : this.capturedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('AnkiPrerenderedHtmlRow(')
          ..write('wordId: $wordId, ')
          ..write('frontHtml: $frontHtml, ')
          ..write('backHtml: $backHtml, ')
          ..write('capturedAt: $capturedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(wordId, frontHtml, backHtml, capturedAt);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is AnkiPrerenderedHtmlRow &&
          other.wordId == this.wordId &&
          other.frontHtml == this.frontHtml &&
          other.backHtml == this.backHtml &&
          other.capturedAt == this.capturedAt);
}

class AnkiPrerenderedHtmlCompanion
    extends UpdateCompanion<AnkiPrerenderedHtmlRow> {
  final Value<String> wordId;
  final Value<String?> frontHtml;
  final Value<String?> backHtml;
  final Value<int> capturedAt;
  final Value<int> rowid;
  const AnkiPrerenderedHtmlCompanion({
    this.wordId = const Value.absent(),
    this.frontHtml = const Value.absent(),
    this.backHtml = const Value.absent(),
    this.capturedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  AnkiPrerenderedHtmlCompanion.insert({
    required String wordId,
    this.frontHtml = const Value.absent(),
    this.backHtml = const Value.absent(),
    this.capturedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : wordId = Value(wordId);
  static Insertable<AnkiPrerenderedHtmlRow> custom({
    Expression<String>? wordId,
    Expression<String>? frontHtml,
    Expression<String>? backHtml,
    Expression<int>? capturedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (wordId != null) 'word_id': wordId,
      if (frontHtml != null) 'front_html': frontHtml,
      if (backHtml != null) 'back_html': backHtml,
      if (capturedAt != null) 'captured_at': capturedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  AnkiPrerenderedHtmlCompanion copyWith(
      {Value<String>? wordId,
      Value<String?>? frontHtml,
      Value<String?>? backHtml,
      Value<int>? capturedAt,
      Value<int>? rowid}) {
    return AnkiPrerenderedHtmlCompanion(
      wordId: wordId ?? this.wordId,
      frontHtml: frontHtml ?? this.frontHtml,
      backHtml: backHtml ?? this.backHtml,
      capturedAt: capturedAt ?? this.capturedAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (wordId.present) {
      map['word_id'] = Variable<String>(wordId.value);
    }
    if (frontHtml.present) {
      map['front_html'] = Variable<String>(frontHtml.value);
    }
    if (backHtml.present) {
      map['back_html'] = Variable<String>(backHtml.value);
    }
    if (capturedAt.present) {
      map['captured_at'] = Variable<int>(capturedAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('AnkiPrerenderedHtmlCompanion(')
          ..write('wordId: $wordId, ')
          ..write('frontHtml: $frontHtml, ')
          ..write('backHtml: $backHtml, ')
          ..write('capturedAt: $capturedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $SrsStatesTable extends SrsStates
    with TableInfo<$SrsStatesTable, SrsState> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $SrsStatesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _wordIdMeta = const VerificationMeta('wordId');
  @override
  late final GeneratedColumn<String> wordId = GeneratedColumn<String>(
      'word_id', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _queueMeta = const VerificationMeta('queue');
  @override
  late final GeneratedColumn<String> queue = GeneratedColumn<String>(
      'queue', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _dueAtMeta = const VerificationMeta('dueAt');
  @override
  late final GeneratedColumn<int> dueAt = GeneratedColumn<int>(
      'due_at', aliasedName, false,
      type: DriftSqlType.int, requiredDuringInsert: true);
  static const VerificationMeta _intervalDaysMeta =
      const VerificationMeta('intervalDays');
  @override
  late final GeneratedColumn<int> intervalDays = GeneratedColumn<int>(
      'interval_days', aliasedName, false,
      type: DriftSqlType.int,
      requiredDuringInsert: false,
      defaultValue: const Constant(1));
  static const VerificationMeta _easeMeta = const VerificationMeta('ease');
  @override
  late final GeneratedColumn<double> ease = GeneratedColumn<double>(
      'ease', aliasedName, false,
      type: DriftSqlType.double,
      requiredDuringInsert: false,
      defaultValue: const Constant(2.5));
  static const VerificationMeta _repsMeta = const VerificationMeta('reps');
  @override
  late final GeneratedColumn<int> reps = GeneratedColumn<int>(
      'reps', aliasedName, false,
      type: DriftSqlType.int,
      requiredDuringInsert: false,
      defaultValue: const Constant(0));
  static const VerificationMeta _lapsesMeta = const VerificationMeta('lapses');
  @override
  late final GeneratedColumn<int> lapses = GeneratedColumn<int>(
      'lapses', aliasedName, false,
      type: DriftSqlType.int,
      requiredDuringInsert: false,
      defaultValue: const Constant(0));
  static const VerificationMeta _isLeechMeta =
      const VerificationMeta('isLeech');
  @override
  late final GeneratedColumn<bool> isLeech = GeneratedColumn<bool>(
      'is_leech', aliasedName, false,
      type: DriftSqlType.bool,
      requiredDuringInsert: false,
      defaultConstraints:
          GeneratedColumn.constraintIsAlways('CHECK ("is_leech" IN (0, 1))'),
      defaultValue: const Constant(false));
  static const VerificationMeta _isSuspendedMeta =
      const VerificationMeta('isSuspended');
  @override
  late final GeneratedColumn<bool> isSuspended = GeneratedColumn<bool>(
      'is_suspended', aliasedName, false,
      type: DriftSqlType.bool,
      requiredDuringInsert: false,
      defaultConstraints: GeneratedColumn.constraintIsAlways(
          'CHECK ("is_suspended" IN (0, 1))'),
      defaultValue: const Constant(false));
  static const VerificationMeta _isBuriedMeta =
      const VerificationMeta('isBuried');
  @override
  late final GeneratedColumn<bool> isBuried = GeneratedColumn<bool>(
      'is_buried', aliasedName, false,
      type: DriftSqlType.bool,
      requiredDuringInsert: false,
      defaultConstraints:
          GeneratedColumn.constraintIsAlways('CHECK ("is_buried" IN (0, 1))'),
      defaultValue: const Constant(false));
  static const VerificationMeta _typeMeta = const VerificationMeta('type');
  @override
  late final GeneratedColumn<String> type = GeneratedColumn<String>(
      'type', aliasedName, false,
      type: DriftSqlType.string,
      requiredDuringInsert: false,
      defaultValue: const Constant('word'));
  static const VerificationMeta _lastReviewedAtMeta =
      const VerificationMeta('lastReviewedAt');
  @override
  late final GeneratedColumn<int> lastReviewedAt = GeneratedColumn<int>(
      'last_reviewed_at', aliasedName, true,
      type: DriftSqlType.int, requiredDuringInsert: false);
  static const VerificationMeta _stabilityMeta =
      const VerificationMeta('stability');
  @override
  late final GeneratedColumn<double> stability = GeneratedColumn<double>(
      'stability', aliasedName, true,
      type: DriftSqlType.double, requiredDuringInsert: false);
  static const VerificationMeta _difficultyMeta =
      const VerificationMeta('difficulty');
  @override
  late final GeneratedColumn<double> difficulty = GeneratedColumn<double>(
      'difficulty', aliasedName, true,
      type: DriftSqlType.double, requiredDuringInsert: false);
  static const VerificationMeta _fsrsStateMeta =
      const VerificationMeta('fsrsState');
  @override
  late final GeneratedColumn<int> fsrsState = GeneratedColumn<int>(
      'fsrs_state', aliasedName, false,
      type: DriftSqlType.int,
      requiredDuringInsert: false,
      defaultValue: const Constant(1));
  static const VerificationMeta _learningStepMeta =
      const VerificationMeta('learningStep');
  @override
  late final GeneratedColumn<int> learningStep = GeneratedColumn<int>(
      'learning_step', aliasedName, true,
      type: DriftSqlType.int, requiredDuringInsert: false);
  static const VerificationMeta _sourceKindMeta =
      const VerificationMeta('sourceKind');
  @override
  late final GeneratedColumn<String> sourceKind = GeneratedColumn<String>(
      'source_kind', aliasedName, true,
      type: DriftSqlType.string, requiredDuringInsert: false);
  static const VerificationMeta _sourceIdMeta =
      const VerificationMeta('sourceId');
  @override
  late final GeneratedColumn<String> sourceId = GeneratedColumn<String>(
      'source_id', aliasedName, true,
      type: DriftSqlType.string, requiredDuringInsert: false);
  static const VerificationMeta _ownerIdMeta =
      const VerificationMeta('ownerId');
  @override
  late final GeneratedColumn<String> ownerId = GeneratedColumn<String>(
      'owner_id', aliasedName, true,
      type: DriftSqlType.string, requiredDuringInsert: false);
  @override
  List<GeneratedColumn> get $columns => [
        wordId,
        queue,
        dueAt,
        intervalDays,
        ease,
        reps,
        lapses,
        isLeech,
        isSuspended,
        isBuried,
        type,
        lastReviewedAt,
        stability,
        difficulty,
        fsrsState,
        learningStep,
        sourceKind,
        sourceId,
        ownerId
      ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'srs_states';
  @override
  VerificationContext validateIntegrity(Insertable<SrsState> instance,
      {bool isInserting = false}) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('word_id')) {
      context.handle(_wordIdMeta,
          wordId.isAcceptableOrUnknown(data['word_id']!, _wordIdMeta));
    } else if (isInserting) {
      context.missing(_wordIdMeta);
    }
    if (data.containsKey('queue')) {
      context.handle(
          _queueMeta, queue.isAcceptableOrUnknown(data['queue']!, _queueMeta));
    } else if (isInserting) {
      context.missing(_queueMeta);
    }
    if (data.containsKey('due_at')) {
      context.handle(
          _dueAtMeta, dueAt.isAcceptableOrUnknown(data['due_at']!, _dueAtMeta));
    } else if (isInserting) {
      context.missing(_dueAtMeta);
    }
    if (data.containsKey('interval_days')) {
      context.handle(
          _intervalDaysMeta,
          intervalDays.isAcceptableOrUnknown(
              data['interval_days']!, _intervalDaysMeta));
    }
    if (data.containsKey('ease')) {
      context.handle(
          _easeMeta, ease.isAcceptableOrUnknown(data['ease']!, _easeMeta));
    }
    if (data.containsKey('reps')) {
      context.handle(
          _repsMeta, reps.isAcceptableOrUnknown(data['reps']!, _repsMeta));
    }
    if (data.containsKey('lapses')) {
      context.handle(_lapsesMeta,
          lapses.isAcceptableOrUnknown(data['lapses']!, _lapsesMeta));
    }
    if (data.containsKey('is_leech')) {
      context.handle(_isLeechMeta,
          isLeech.isAcceptableOrUnknown(data['is_leech']!, _isLeechMeta));
    }
    if (data.containsKey('is_suspended')) {
      context.handle(
          _isSuspendedMeta,
          isSuspended.isAcceptableOrUnknown(
              data['is_suspended']!, _isSuspendedMeta));
    }
    if (data.containsKey('is_buried')) {
      context.handle(_isBuriedMeta,
          isBuried.isAcceptableOrUnknown(data['is_buried']!, _isBuriedMeta));
    }
    if (data.containsKey('type')) {
      context.handle(
          _typeMeta, type.isAcceptableOrUnknown(data['type']!, _typeMeta));
    }
    if (data.containsKey('last_reviewed_at')) {
      context.handle(
          _lastReviewedAtMeta,
          lastReviewedAt.isAcceptableOrUnknown(
              data['last_reviewed_at']!, _lastReviewedAtMeta));
    }
    if (data.containsKey('stability')) {
      context.handle(_stabilityMeta,
          stability.isAcceptableOrUnknown(data['stability']!, _stabilityMeta));
    }
    if (data.containsKey('difficulty')) {
      context.handle(
          _difficultyMeta,
          difficulty.isAcceptableOrUnknown(
              data['difficulty']!, _difficultyMeta));
    }
    if (data.containsKey('fsrs_state')) {
      context.handle(_fsrsStateMeta,
          fsrsState.isAcceptableOrUnknown(data['fsrs_state']!, _fsrsStateMeta));
    }
    if (data.containsKey('learning_step')) {
      context.handle(
          _learningStepMeta,
          learningStep.isAcceptableOrUnknown(
              data['learning_step']!, _learningStepMeta));
    }
    if (data.containsKey('source_kind')) {
      context.handle(
          _sourceKindMeta,
          sourceKind.isAcceptableOrUnknown(
              data['source_kind']!, _sourceKindMeta));
    }
    if (data.containsKey('source_id')) {
      context.handle(_sourceIdMeta,
          sourceId.isAcceptableOrUnknown(data['source_id']!, _sourceIdMeta));
    }
    if (data.containsKey('owner_id')) {
      context.handle(_ownerIdMeta,
          ownerId.isAcceptableOrUnknown(data['owner_id']!, _ownerIdMeta));
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {wordId};
  @override
  SrsState map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return SrsState(
      wordId: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}word_id'])!,
      queue: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}queue'])!,
      dueAt: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}due_at'])!,
      intervalDays: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}interval_days'])!,
      ease: attachedDatabase.typeMapping
          .read(DriftSqlType.double, data['${effectivePrefix}ease'])!,
      reps: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}reps'])!,
      lapses: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}lapses'])!,
      isLeech: attachedDatabase.typeMapping
          .read(DriftSqlType.bool, data['${effectivePrefix}is_leech'])!,
      isSuspended: attachedDatabase.typeMapping
          .read(DriftSqlType.bool, data['${effectivePrefix}is_suspended'])!,
      isBuried: attachedDatabase.typeMapping
          .read(DriftSqlType.bool, data['${effectivePrefix}is_buried'])!,
      type: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}type'])!,
      lastReviewedAt: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}last_reviewed_at']),
      stability: attachedDatabase.typeMapping
          .read(DriftSqlType.double, data['${effectivePrefix}stability']),
      difficulty: attachedDatabase.typeMapping
          .read(DriftSqlType.double, data['${effectivePrefix}difficulty']),
      fsrsState: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}fsrs_state'])!,
      learningStep: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}learning_step']),
      sourceKind: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}source_kind']),
      sourceId: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}source_id']),
      ownerId: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}owner_id']),
    );
  }

  @override
  $SrsStatesTable createAlias(String alias) {
    return $SrsStatesTable(attachedDatabase, alias);
  }
}

class SrsState extends DataClass implements Insertable<SrsState> {
  final String wordId;
  final String queue;
  final int dueAt;
  final int intervalDays;
  final double ease;
  final int reps;
  final int lapses;
  final bool isLeech;
  final bool isSuspended;
  final bool isBuried;
  final String type;
  final int? lastReviewedAt;
  final double? stability;
  final double? difficulty;
  final int fsrsState;
  final int? learningStep;
  final String? sourceKind;
  final String? sourceId;
  final String? ownerId;
  const SrsState(
      {required this.wordId,
      required this.queue,
      required this.dueAt,
      required this.intervalDays,
      required this.ease,
      required this.reps,
      required this.lapses,
      required this.isLeech,
      required this.isSuspended,
      required this.isBuried,
      required this.type,
      this.lastReviewedAt,
      this.stability,
      this.difficulty,
      required this.fsrsState,
      this.learningStep,
      this.sourceKind,
      this.sourceId,
      this.ownerId});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['word_id'] = Variable<String>(wordId);
    map['queue'] = Variable<String>(queue);
    map['due_at'] = Variable<int>(dueAt);
    map['interval_days'] = Variable<int>(intervalDays);
    map['ease'] = Variable<double>(ease);
    map['reps'] = Variable<int>(reps);
    map['lapses'] = Variable<int>(lapses);
    map['is_leech'] = Variable<bool>(isLeech);
    map['is_suspended'] = Variable<bool>(isSuspended);
    map['is_buried'] = Variable<bool>(isBuried);
    map['type'] = Variable<String>(type);
    if (!nullToAbsent || lastReviewedAt != null) {
      map['last_reviewed_at'] = Variable<int>(lastReviewedAt);
    }
    if (!nullToAbsent || stability != null) {
      map['stability'] = Variable<double>(stability);
    }
    if (!nullToAbsent || difficulty != null) {
      map['difficulty'] = Variable<double>(difficulty);
    }
    map['fsrs_state'] = Variable<int>(fsrsState);
    if (!nullToAbsent || learningStep != null) {
      map['learning_step'] = Variable<int>(learningStep);
    }
    if (!nullToAbsent || sourceKind != null) {
      map['source_kind'] = Variable<String>(sourceKind);
    }
    if (!nullToAbsent || sourceId != null) {
      map['source_id'] = Variable<String>(sourceId);
    }
    if (!nullToAbsent || ownerId != null) {
      map['owner_id'] = Variable<String>(ownerId);
    }
    return map;
  }

  SrsStatesCompanion toCompanion(bool nullToAbsent) {
    return SrsStatesCompanion(
      wordId: Value(wordId),
      queue: Value(queue),
      dueAt: Value(dueAt),
      intervalDays: Value(intervalDays),
      ease: Value(ease),
      reps: Value(reps),
      lapses: Value(lapses),
      isLeech: Value(isLeech),
      isSuspended: Value(isSuspended),
      isBuried: Value(isBuried),
      type: Value(type),
      lastReviewedAt: lastReviewedAt == null && nullToAbsent
          ? const Value.absent()
          : Value(lastReviewedAt),
      stability: stability == null && nullToAbsent
          ? const Value.absent()
          : Value(stability),
      difficulty: difficulty == null && nullToAbsent
          ? const Value.absent()
          : Value(difficulty),
      fsrsState: Value(fsrsState),
      learningStep: learningStep == null && nullToAbsent
          ? const Value.absent()
          : Value(learningStep),
      sourceKind: sourceKind == null && nullToAbsent
          ? const Value.absent()
          : Value(sourceKind),
      sourceId: sourceId == null && nullToAbsent
          ? const Value.absent()
          : Value(sourceId),
      ownerId: ownerId == null && nullToAbsent
          ? const Value.absent()
          : Value(ownerId),
    );
  }

  factory SrsState.fromJson(Map<String, dynamic> json,
      {ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return SrsState(
      wordId: serializer.fromJson<String>(json['wordId']),
      queue: serializer.fromJson<String>(json['queue']),
      dueAt: serializer.fromJson<int>(json['dueAt']),
      intervalDays: serializer.fromJson<int>(json['intervalDays']),
      ease: serializer.fromJson<double>(json['ease']),
      reps: serializer.fromJson<int>(json['reps']),
      lapses: serializer.fromJson<int>(json['lapses']),
      isLeech: serializer.fromJson<bool>(json['isLeech']),
      isSuspended: serializer.fromJson<bool>(json['isSuspended']),
      isBuried: serializer.fromJson<bool>(json['isBuried']),
      type: serializer.fromJson<String>(json['type']),
      lastReviewedAt: serializer.fromJson<int?>(json['lastReviewedAt']),
      stability: serializer.fromJson<double?>(json['stability']),
      difficulty: serializer.fromJson<double?>(json['difficulty']),
      fsrsState: serializer.fromJson<int>(json['fsrsState']),
      learningStep: serializer.fromJson<int?>(json['learningStep']),
      sourceKind: serializer.fromJson<String?>(json['sourceKind']),
      sourceId: serializer.fromJson<String?>(json['sourceId']),
      ownerId: serializer.fromJson<String?>(json['ownerId']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'wordId': serializer.toJson<String>(wordId),
      'queue': serializer.toJson<String>(queue),
      'dueAt': serializer.toJson<int>(dueAt),
      'intervalDays': serializer.toJson<int>(intervalDays),
      'ease': serializer.toJson<double>(ease),
      'reps': serializer.toJson<int>(reps),
      'lapses': serializer.toJson<int>(lapses),
      'isLeech': serializer.toJson<bool>(isLeech),
      'isSuspended': serializer.toJson<bool>(isSuspended),
      'isBuried': serializer.toJson<bool>(isBuried),
      'type': serializer.toJson<String>(type),
      'lastReviewedAt': serializer.toJson<int?>(lastReviewedAt),
      'stability': serializer.toJson<double?>(stability),
      'difficulty': serializer.toJson<double?>(difficulty),
      'fsrsState': serializer.toJson<int>(fsrsState),
      'learningStep': serializer.toJson<int?>(learningStep),
      'sourceKind': serializer.toJson<String?>(sourceKind),
      'sourceId': serializer.toJson<String?>(sourceId),
      'ownerId': serializer.toJson<String?>(ownerId),
    };
  }

  SrsState copyWith(
          {String? wordId,
          String? queue,
          int? dueAt,
          int? intervalDays,
          double? ease,
          int? reps,
          int? lapses,
          bool? isLeech,
          bool? isSuspended,
          bool? isBuried,
          String? type,
          Value<int?> lastReviewedAt = const Value.absent(),
          Value<double?> stability = const Value.absent(),
          Value<double?> difficulty = const Value.absent(),
          int? fsrsState,
          Value<int?> learningStep = const Value.absent(),
          Value<String?> sourceKind = const Value.absent(),
          Value<String?> sourceId = const Value.absent(),
          Value<String?> ownerId = const Value.absent()}) =>
      SrsState(
        wordId: wordId ?? this.wordId,
        queue: queue ?? this.queue,
        dueAt: dueAt ?? this.dueAt,
        intervalDays: intervalDays ?? this.intervalDays,
        ease: ease ?? this.ease,
        reps: reps ?? this.reps,
        lapses: lapses ?? this.lapses,
        isLeech: isLeech ?? this.isLeech,
        isSuspended: isSuspended ?? this.isSuspended,
        isBuried: isBuried ?? this.isBuried,
        type: type ?? this.type,
        lastReviewedAt:
            lastReviewedAt.present ? lastReviewedAt.value : this.lastReviewedAt,
        stability: stability.present ? stability.value : this.stability,
        difficulty: difficulty.present ? difficulty.value : this.difficulty,
        fsrsState: fsrsState ?? this.fsrsState,
        learningStep:
            learningStep.present ? learningStep.value : this.learningStep,
        sourceKind: sourceKind.present ? sourceKind.value : this.sourceKind,
        sourceId: sourceId.present ? sourceId.value : this.sourceId,
        ownerId: ownerId.present ? ownerId.value : this.ownerId,
      );
  SrsState copyWithCompanion(SrsStatesCompanion data) {
    return SrsState(
      wordId: data.wordId.present ? data.wordId.value : this.wordId,
      queue: data.queue.present ? data.queue.value : this.queue,
      dueAt: data.dueAt.present ? data.dueAt.value : this.dueAt,
      intervalDays: data.intervalDays.present
          ? data.intervalDays.value
          : this.intervalDays,
      ease: data.ease.present ? data.ease.value : this.ease,
      reps: data.reps.present ? data.reps.value : this.reps,
      lapses: data.lapses.present ? data.lapses.value : this.lapses,
      isLeech: data.isLeech.present ? data.isLeech.value : this.isLeech,
      isSuspended:
          data.isSuspended.present ? data.isSuspended.value : this.isSuspended,
      isBuried: data.isBuried.present ? data.isBuried.value : this.isBuried,
      type: data.type.present ? data.type.value : this.type,
      lastReviewedAt: data.lastReviewedAt.present
          ? data.lastReviewedAt.value
          : this.lastReviewedAt,
      stability: data.stability.present ? data.stability.value : this.stability,
      difficulty:
          data.difficulty.present ? data.difficulty.value : this.difficulty,
      fsrsState: data.fsrsState.present ? data.fsrsState.value : this.fsrsState,
      learningStep: data.learningStep.present
          ? data.learningStep.value
          : this.learningStep,
      sourceKind:
          data.sourceKind.present ? data.sourceKind.value : this.sourceKind,
      sourceId: data.sourceId.present ? data.sourceId.value : this.sourceId,
      ownerId: data.ownerId.present ? data.ownerId.value : this.ownerId,
    );
  }

  @override
  String toString() {
    return (StringBuffer('SrsState(')
          ..write('wordId: $wordId, ')
          ..write('queue: $queue, ')
          ..write('dueAt: $dueAt, ')
          ..write('intervalDays: $intervalDays, ')
          ..write('ease: $ease, ')
          ..write('reps: $reps, ')
          ..write('lapses: $lapses, ')
          ..write('isLeech: $isLeech, ')
          ..write('isSuspended: $isSuspended, ')
          ..write('isBuried: $isBuried, ')
          ..write('type: $type, ')
          ..write('lastReviewedAt: $lastReviewedAt, ')
          ..write('stability: $stability, ')
          ..write('difficulty: $difficulty, ')
          ..write('fsrsState: $fsrsState, ')
          ..write('learningStep: $learningStep, ')
          ..write('sourceKind: $sourceKind, ')
          ..write('sourceId: $sourceId, ')
          ..write('ownerId: $ownerId')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
      wordId,
      queue,
      dueAt,
      intervalDays,
      ease,
      reps,
      lapses,
      isLeech,
      isSuspended,
      isBuried,
      type,
      lastReviewedAt,
      stability,
      difficulty,
      fsrsState,
      learningStep,
      sourceKind,
      sourceId,
      ownerId);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is SrsState &&
          other.wordId == this.wordId &&
          other.queue == this.queue &&
          other.dueAt == this.dueAt &&
          other.intervalDays == this.intervalDays &&
          other.ease == this.ease &&
          other.reps == this.reps &&
          other.lapses == this.lapses &&
          other.isLeech == this.isLeech &&
          other.isSuspended == this.isSuspended &&
          other.isBuried == this.isBuried &&
          other.type == this.type &&
          other.lastReviewedAt == this.lastReviewedAt &&
          other.stability == this.stability &&
          other.difficulty == this.difficulty &&
          other.fsrsState == this.fsrsState &&
          other.learningStep == this.learningStep &&
          other.sourceKind == this.sourceKind &&
          other.sourceId == this.sourceId &&
          other.ownerId == this.ownerId);
}

class SrsStatesCompanion extends UpdateCompanion<SrsState> {
  final Value<String> wordId;
  final Value<String> queue;
  final Value<int> dueAt;
  final Value<int> intervalDays;
  final Value<double> ease;
  final Value<int> reps;
  final Value<int> lapses;
  final Value<bool> isLeech;
  final Value<bool> isSuspended;
  final Value<bool> isBuried;
  final Value<String> type;
  final Value<int?> lastReviewedAt;
  final Value<double?> stability;
  final Value<double?> difficulty;
  final Value<int> fsrsState;
  final Value<int?> learningStep;
  final Value<String?> sourceKind;
  final Value<String?> sourceId;
  final Value<String?> ownerId;
  final Value<int> rowid;
  const SrsStatesCompanion({
    this.wordId = const Value.absent(),
    this.queue = const Value.absent(),
    this.dueAt = const Value.absent(),
    this.intervalDays = const Value.absent(),
    this.ease = const Value.absent(),
    this.reps = const Value.absent(),
    this.lapses = const Value.absent(),
    this.isLeech = const Value.absent(),
    this.isSuspended = const Value.absent(),
    this.isBuried = const Value.absent(),
    this.type = const Value.absent(),
    this.lastReviewedAt = const Value.absent(),
    this.stability = const Value.absent(),
    this.difficulty = const Value.absent(),
    this.fsrsState = const Value.absent(),
    this.learningStep = const Value.absent(),
    this.sourceKind = const Value.absent(),
    this.sourceId = const Value.absent(),
    this.ownerId = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  SrsStatesCompanion.insert({
    required String wordId,
    required String queue,
    required int dueAt,
    this.intervalDays = const Value.absent(),
    this.ease = const Value.absent(),
    this.reps = const Value.absent(),
    this.lapses = const Value.absent(),
    this.isLeech = const Value.absent(),
    this.isSuspended = const Value.absent(),
    this.isBuried = const Value.absent(),
    this.type = const Value.absent(),
    this.lastReviewedAt = const Value.absent(),
    this.stability = const Value.absent(),
    this.difficulty = const Value.absent(),
    this.fsrsState = const Value.absent(),
    this.learningStep = const Value.absent(),
    this.sourceKind = const Value.absent(),
    this.sourceId = const Value.absent(),
    this.ownerId = const Value.absent(),
    this.rowid = const Value.absent(),
  })  : wordId = Value(wordId),
        queue = Value(queue),
        dueAt = Value(dueAt);
  static Insertable<SrsState> custom({
    Expression<String>? wordId,
    Expression<String>? queue,
    Expression<int>? dueAt,
    Expression<int>? intervalDays,
    Expression<double>? ease,
    Expression<int>? reps,
    Expression<int>? lapses,
    Expression<bool>? isLeech,
    Expression<bool>? isSuspended,
    Expression<bool>? isBuried,
    Expression<String>? type,
    Expression<int>? lastReviewedAt,
    Expression<double>? stability,
    Expression<double>? difficulty,
    Expression<int>? fsrsState,
    Expression<int>? learningStep,
    Expression<String>? sourceKind,
    Expression<String>? sourceId,
    Expression<String>? ownerId,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (wordId != null) 'word_id': wordId,
      if (queue != null) 'queue': queue,
      if (dueAt != null) 'due_at': dueAt,
      if (intervalDays != null) 'interval_days': intervalDays,
      if (ease != null) 'ease': ease,
      if (reps != null) 'reps': reps,
      if (lapses != null) 'lapses': lapses,
      if (isLeech != null) 'is_leech': isLeech,
      if (isSuspended != null) 'is_suspended': isSuspended,
      if (isBuried != null) 'is_buried': isBuried,
      if (type != null) 'type': type,
      if (lastReviewedAt != null) 'last_reviewed_at': lastReviewedAt,
      if (stability != null) 'stability': stability,
      if (difficulty != null) 'difficulty': difficulty,
      if (fsrsState != null) 'fsrs_state': fsrsState,
      if (learningStep != null) 'learning_step': learningStep,
      if (sourceKind != null) 'source_kind': sourceKind,
      if (sourceId != null) 'source_id': sourceId,
      if (ownerId != null) 'owner_id': ownerId,
      if (rowid != null) 'rowid': rowid,
    });
  }

  SrsStatesCompanion copyWith(
      {Value<String>? wordId,
      Value<String>? queue,
      Value<int>? dueAt,
      Value<int>? intervalDays,
      Value<double>? ease,
      Value<int>? reps,
      Value<int>? lapses,
      Value<bool>? isLeech,
      Value<bool>? isSuspended,
      Value<bool>? isBuried,
      Value<String>? type,
      Value<int?>? lastReviewedAt,
      Value<double?>? stability,
      Value<double?>? difficulty,
      Value<int>? fsrsState,
      Value<int?>? learningStep,
      Value<String?>? sourceKind,
      Value<String?>? sourceId,
      Value<String?>? ownerId,
      Value<int>? rowid}) {
    return SrsStatesCompanion(
      wordId: wordId ?? this.wordId,
      queue: queue ?? this.queue,
      dueAt: dueAt ?? this.dueAt,
      intervalDays: intervalDays ?? this.intervalDays,
      ease: ease ?? this.ease,
      reps: reps ?? this.reps,
      lapses: lapses ?? this.lapses,
      isLeech: isLeech ?? this.isLeech,
      isSuspended: isSuspended ?? this.isSuspended,
      isBuried: isBuried ?? this.isBuried,
      type: type ?? this.type,
      lastReviewedAt: lastReviewedAt ?? this.lastReviewedAt,
      stability: stability ?? this.stability,
      difficulty: difficulty ?? this.difficulty,
      fsrsState: fsrsState ?? this.fsrsState,
      learningStep: learningStep ?? this.learningStep,
      sourceKind: sourceKind ?? this.sourceKind,
      sourceId: sourceId ?? this.sourceId,
      ownerId: ownerId ?? this.ownerId,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (wordId.present) {
      map['word_id'] = Variable<String>(wordId.value);
    }
    if (queue.present) {
      map['queue'] = Variable<String>(queue.value);
    }
    if (dueAt.present) {
      map['due_at'] = Variable<int>(dueAt.value);
    }
    if (intervalDays.present) {
      map['interval_days'] = Variable<int>(intervalDays.value);
    }
    if (ease.present) {
      map['ease'] = Variable<double>(ease.value);
    }
    if (reps.present) {
      map['reps'] = Variable<int>(reps.value);
    }
    if (lapses.present) {
      map['lapses'] = Variable<int>(lapses.value);
    }
    if (isLeech.present) {
      map['is_leech'] = Variable<bool>(isLeech.value);
    }
    if (isSuspended.present) {
      map['is_suspended'] = Variable<bool>(isSuspended.value);
    }
    if (isBuried.present) {
      map['is_buried'] = Variable<bool>(isBuried.value);
    }
    if (type.present) {
      map['type'] = Variable<String>(type.value);
    }
    if (lastReviewedAt.present) {
      map['last_reviewed_at'] = Variable<int>(lastReviewedAt.value);
    }
    if (stability.present) {
      map['stability'] = Variable<double>(stability.value);
    }
    if (difficulty.present) {
      map['difficulty'] = Variable<double>(difficulty.value);
    }
    if (fsrsState.present) {
      map['fsrs_state'] = Variable<int>(fsrsState.value);
    }
    if (learningStep.present) {
      map['learning_step'] = Variable<int>(learningStep.value);
    }
    if (sourceKind.present) {
      map['source_kind'] = Variable<String>(sourceKind.value);
    }
    if (sourceId.present) {
      map['source_id'] = Variable<String>(sourceId.value);
    }
    if (ownerId.present) {
      map['owner_id'] = Variable<String>(ownerId.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('SrsStatesCompanion(')
          ..write('wordId: $wordId, ')
          ..write('queue: $queue, ')
          ..write('dueAt: $dueAt, ')
          ..write('intervalDays: $intervalDays, ')
          ..write('ease: $ease, ')
          ..write('reps: $reps, ')
          ..write('lapses: $lapses, ')
          ..write('isLeech: $isLeech, ')
          ..write('isSuspended: $isSuspended, ')
          ..write('isBuried: $isBuried, ')
          ..write('type: $type, ')
          ..write('lastReviewedAt: $lastReviewedAt, ')
          ..write('stability: $stability, ')
          ..write('difficulty: $difficulty, ')
          ..write('fsrsState: $fsrsState, ')
          ..write('learningStep: $learningStep, ')
          ..write('sourceKind: $sourceKind, ')
          ..write('sourceId: $sourceId, ')
          ..write('ownerId: $ownerId, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $ReviewEventsTable extends ReviewEvents
    with TableInfo<$ReviewEventsTable, ReviewEvent> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $ReviewEventsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<int> id = GeneratedColumn<int>(
      'id', aliasedName, false,
      hasAutoIncrement: true,
      type: DriftSqlType.int,
      requiredDuringInsert: false,
      defaultConstraints:
          GeneratedColumn.constraintIsAlways('PRIMARY KEY AUTOINCREMENT'));
  static const VerificationMeta _cardIdMeta = const VerificationMeta('cardId');
  @override
  late final GeneratedColumn<String> cardId = GeneratedColumn<String>(
      'card_id', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _queueMeta = const VerificationMeta('queue');
  @override
  late final GeneratedColumn<String> queue = GeneratedColumn<String>(
      'queue', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _reviewedAtMeta =
      const VerificationMeta('reviewedAt');
  @override
  late final GeneratedColumn<int> reviewedAt = GeneratedColumn<int>(
      'reviewed_at', aliasedName, false,
      type: DriftSqlType.int, requiredDuringInsert: true);
  static const VerificationMeta _qualityMeta =
      const VerificationMeta('quality');
  @override
  late final GeneratedColumn<int> quality = GeneratedColumn<int>(
      'quality', aliasedName, false,
      type: DriftSqlType.int, requiredDuringInsert: true);
  static const VerificationMeta _prevIntervalDaysMeta =
      const VerificationMeta('prevIntervalDays');
  @override
  late final GeneratedColumn<int> prevIntervalDays = GeneratedColumn<int>(
      'prev_interval_days', aliasedName, false,
      type: DriftSqlType.int, requiredDuringInsert: true);
  static const VerificationMeta _nextIntervalDaysMeta =
      const VerificationMeta('nextIntervalDays');
  @override
  late final GeneratedColumn<int> nextIntervalDays = GeneratedColumn<int>(
      'next_interval_days', aliasedName, false,
      type: DriftSqlType.int, requiredDuringInsert: true);
  static const VerificationMeta _prevEaseMeta =
      const VerificationMeta('prevEase');
  @override
  late final GeneratedColumn<double> prevEase = GeneratedColumn<double>(
      'prev_ease', aliasedName, false,
      type: DriftSqlType.double, requiredDuringInsert: true);
  static const VerificationMeta _nextEaseMeta =
      const VerificationMeta('nextEase');
  @override
  late final GeneratedColumn<double> nextEase = GeneratedColumn<double>(
      'next_ease', aliasedName, false,
      type: DriftSqlType.double, requiredDuringInsert: true);
  static const VerificationMeta _repsMeta = const VerificationMeta('reps');
  @override
  late final GeneratedColumn<int> reps = GeneratedColumn<int>(
      'reps', aliasedName, false,
      type: DriftSqlType.int, requiredDuringInsert: true);
  static const VerificationMeta _lapsesMeta = const VerificationMeta('lapses');
  @override
  late final GeneratedColumn<int> lapses = GeneratedColumn<int>(
      'lapses', aliasedName, false,
      type: DriftSqlType.int, requiredDuringInsert: true);
  static const VerificationMeta _typeMeta = const VerificationMeta('type');
  @override
  late final GeneratedColumn<String> type = GeneratedColumn<String>(
      'type', aliasedName, false,
      type: DriftSqlType.string,
      requiredDuringInsert: false,
      defaultValue: const Constant('word'));
  static const VerificationMeta _sourceKeyMeta =
      const VerificationMeta('sourceKey');
  @override
  late final GeneratedColumn<String> sourceKey = GeneratedColumn<String>(
      'source_key', aliasedName, true,
      type: DriftSqlType.string, requiredDuringInsert: false);
  static const VerificationMeta _sourceKindMeta =
      const VerificationMeta('sourceKind');
  @override
  late final GeneratedColumn<String> sourceKind = GeneratedColumn<String>(
      'source_kind', aliasedName, true,
      type: DriftSqlType.string, requiredDuringInsert: false);
  static const VerificationMeta _sourceIdMeta =
      const VerificationMeta('sourceId');
  @override
  late final GeneratedColumn<String> sourceId = GeneratedColumn<String>(
      'source_id', aliasedName, true,
      type: DriftSqlType.string, requiredDuringInsert: false);
  static const VerificationMeta _ownerIdMeta =
      const VerificationMeta('ownerId');
  @override
  late final GeneratedColumn<String> ownerId = GeneratedColumn<String>(
      'owner_id', aliasedName, true,
      type: DriftSqlType.string, requiredDuringInsert: false);
  @override
  List<GeneratedColumn> get $columns => [
        id,
        cardId,
        queue,
        reviewedAt,
        quality,
        prevIntervalDays,
        nextIntervalDays,
        prevEase,
        nextEase,
        reps,
        lapses,
        type,
        sourceKey,
        sourceKind,
        sourceId,
        ownerId
      ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'review_events';
  @override
  VerificationContext validateIntegrity(Insertable<ReviewEvent> instance,
      {bool isInserting = false}) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('card_id')) {
      context.handle(_cardIdMeta,
          cardId.isAcceptableOrUnknown(data['card_id']!, _cardIdMeta));
    } else if (isInserting) {
      context.missing(_cardIdMeta);
    }
    if (data.containsKey('queue')) {
      context.handle(
          _queueMeta, queue.isAcceptableOrUnknown(data['queue']!, _queueMeta));
    } else if (isInserting) {
      context.missing(_queueMeta);
    }
    if (data.containsKey('reviewed_at')) {
      context.handle(
          _reviewedAtMeta,
          reviewedAt.isAcceptableOrUnknown(
              data['reviewed_at']!, _reviewedAtMeta));
    } else if (isInserting) {
      context.missing(_reviewedAtMeta);
    }
    if (data.containsKey('quality')) {
      context.handle(_qualityMeta,
          quality.isAcceptableOrUnknown(data['quality']!, _qualityMeta));
    } else if (isInserting) {
      context.missing(_qualityMeta);
    }
    if (data.containsKey('prev_interval_days')) {
      context.handle(
          _prevIntervalDaysMeta,
          prevIntervalDays.isAcceptableOrUnknown(
              data['prev_interval_days']!, _prevIntervalDaysMeta));
    } else if (isInserting) {
      context.missing(_prevIntervalDaysMeta);
    }
    if (data.containsKey('next_interval_days')) {
      context.handle(
          _nextIntervalDaysMeta,
          nextIntervalDays.isAcceptableOrUnknown(
              data['next_interval_days']!, _nextIntervalDaysMeta));
    } else if (isInserting) {
      context.missing(_nextIntervalDaysMeta);
    }
    if (data.containsKey('prev_ease')) {
      context.handle(_prevEaseMeta,
          prevEase.isAcceptableOrUnknown(data['prev_ease']!, _prevEaseMeta));
    } else if (isInserting) {
      context.missing(_prevEaseMeta);
    }
    if (data.containsKey('next_ease')) {
      context.handle(_nextEaseMeta,
          nextEase.isAcceptableOrUnknown(data['next_ease']!, _nextEaseMeta));
    } else if (isInserting) {
      context.missing(_nextEaseMeta);
    }
    if (data.containsKey('reps')) {
      context.handle(
          _repsMeta, reps.isAcceptableOrUnknown(data['reps']!, _repsMeta));
    } else if (isInserting) {
      context.missing(_repsMeta);
    }
    if (data.containsKey('lapses')) {
      context.handle(_lapsesMeta,
          lapses.isAcceptableOrUnknown(data['lapses']!, _lapsesMeta));
    } else if (isInserting) {
      context.missing(_lapsesMeta);
    }
    if (data.containsKey('type')) {
      context.handle(
          _typeMeta, type.isAcceptableOrUnknown(data['type']!, _typeMeta));
    }
    if (data.containsKey('source_key')) {
      context.handle(_sourceKeyMeta,
          sourceKey.isAcceptableOrUnknown(data['source_key']!, _sourceKeyMeta));
    }
    if (data.containsKey('source_kind')) {
      context.handle(
          _sourceKindMeta,
          sourceKind.isAcceptableOrUnknown(
              data['source_kind']!, _sourceKindMeta));
    }
    if (data.containsKey('source_id')) {
      context.handle(_sourceIdMeta,
          sourceId.isAcceptableOrUnknown(data['source_id']!, _sourceIdMeta));
    }
    if (data.containsKey('owner_id')) {
      context.handle(_ownerIdMeta,
          ownerId.isAcceptableOrUnknown(data['owner_id']!, _ownerIdMeta));
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  ReviewEvent map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return ReviewEvent(
      id: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}id'])!,
      cardId: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}card_id'])!,
      queue: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}queue'])!,
      reviewedAt: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}reviewed_at'])!,
      quality: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}quality'])!,
      prevIntervalDays: attachedDatabase.typeMapping.read(
          DriftSqlType.int, data['${effectivePrefix}prev_interval_days'])!,
      nextIntervalDays: attachedDatabase.typeMapping.read(
          DriftSqlType.int, data['${effectivePrefix}next_interval_days'])!,
      prevEase: attachedDatabase.typeMapping
          .read(DriftSqlType.double, data['${effectivePrefix}prev_ease'])!,
      nextEase: attachedDatabase.typeMapping
          .read(DriftSqlType.double, data['${effectivePrefix}next_ease'])!,
      reps: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}reps'])!,
      lapses: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}lapses'])!,
      type: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}type'])!,
      sourceKey: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}source_key']),
      sourceKind: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}source_kind']),
      sourceId: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}source_id']),
      ownerId: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}owner_id']),
    );
  }

  @override
  $ReviewEventsTable createAlias(String alias) {
    return $ReviewEventsTable(attachedDatabase, alias);
  }
}

class ReviewEvent extends DataClass implements Insertable<ReviewEvent> {
  final int id;
  final String cardId;
  final String queue;
  final int reviewedAt;
  final int quality;
  final int prevIntervalDays;
  final int nextIntervalDays;
  final double prevEase;
  final double nextEase;
  final int reps;
  final int lapses;
  final String type;
  final String? sourceKey;
  final String? sourceKind;
  final String? sourceId;
  final String? ownerId;
  const ReviewEvent(
      {required this.id,
      required this.cardId,
      required this.queue,
      required this.reviewedAt,
      required this.quality,
      required this.prevIntervalDays,
      required this.nextIntervalDays,
      required this.prevEase,
      required this.nextEase,
      required this.reps,
      required this.lapses,
      required this.type,
      this.sourceKey,
      this.sourceKind,
      this.sourceId,
      this.ownerId});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    map['card_id'] = Variable<String>(cardId);
    map['queue'] = Variable<String>(queue);
    map['reviewed_at'] = Variable<int>(reviewedAt);
    map['quality'] = Variable<int>(quality);
    map['prev_interval_days'] = Variable<int>(prevIntervalDays);
    map['next_interval_days'] = Variable<int>(nextIntervalDays);
    map['prev_ease'] = Variable<double>(prevEase);
    map['next_ease'] = Variable<double>(nextEase);
    map['reps'] = Variable<int>(reps);
    map['lapses'] = Variable<int>(lapses);
    map['type'] = Variable<String>(type);
    if (!nullToAbsent || sourceKey != null) {
      map['source_key'] = Variable<String>(sourceKey);
    }
    if (!nullToAbsent || sourceKind != null) {
      map['source_kind'] = Variable<String>(sourceKind);
    }
    if (!nullToAbsent || sourceId != null) {
      map['source_id'] = Variable<String>(sourceId);
    }
    if (!nullToAbsent || ownerId != null) {
      map['owner_id'] = Variable<String>(ownerId);
    }
    return map;
  }

  ReviewEventsCompanion toCompanion(bool nullToAbsent) {
    return ReviewEventsCompanion(
      id: Value(id),
      cardId: Value(cardId),
      queue: Value(queue),
      reviewedAt: Value(reviewedAt),
      quality: Value(quality),
      prevIntervalDays: Value(prevIntervalDays),
      nextIntervalDays: Value(nextIntervalDays),
      prevEase: Value(prevEase),
      nextEase: Value(nextEase),
      reps: Value(reps),
      lapses: Value(lapses),
      type: Value(type),
      sourceKey: sourceKey == null && nullToAbsent
          ? const Value.absent()
          : Value(sourceKey),
      sourceKind: sourceKind == null && nullToAbsent
          ? const Value.absent()
          : Value(sourceKind),
      sourceId: sourceId == null && nullToAbsent
          ? const Value.absent()
          : Value(sourceId),
      ownerId: ownerId == null && nullToAbsent
          ? const Value.absent()
          : Value(ownerId),
    );
  }

  factory ReviewEvent.fromJson(Map<String, dynamic> json,
      {ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return ReviewEvent(
      id: serializer.fromJson<int>(json['id']),
      cardId: serializer.fromJson<String>(json['cardId']),
      queue: serializer.fromJson<String>(json['queue']),
      reviewedAt: serializer.fromJson<int>(json['reviewedAt']),
      quality: serializer.fromJson<int>(json['quality']),
      prevIntervalDays: serializer.fromJson<int>(json['prevIntervalDays']),
      nextIntervalDays: serializer.fromJson<int>(json['nextIntervalDays']),
      prevEase: serializer.fromJson<double>(json['prevEase']),
      nextEase: serializer.fromJson<double>(json['nextEase']),
      reps: serializer.fromJson<int>(json['reps']),
      lapses: serializer.fromJson<int>(json['lapses']),
      type: serializer.fromJson<String>(json['type']),
      sourceKey: serializer.fromJson<String?>(json['sourceKey']),
      sourceKind: serializer.fromJson<String?>(json['sourceKind']),
      sourceId: serializer.fromJson<String?>(json['sourceId']),
      ownerId: serializer.fromJson<String?>(json['ownerId']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'cardId': serializer.toJson<String>(cardId),
      'queue': serializer.toJson<String>(queue),
      'reviewedAt': serializer.toJson<int>(reviewedAt),
      'quality': serializer.toJson<int>(quality),
      'prevIntervalDays': serializer.toJson<int>(prevIntervalDays),
      'nextIntervalDays': serializer.toJson<int>(nextIntervalDays),
      'prevEase': serializer.toJson<double>(prevEase),
      'nextEase': serializer.toJson<double>(nextEase),
      'reps': serializer.toJson<int>(reps),
      'lapses': serializer.toJson<int>(lapses),
      'type': serializer.toJson<String>(type),
      'sourceKey': serializer.toJson<String?>(sourceKey),
      'sourceKind': serializer.toJson<String?>(sourceKind),
      'sourceId': serializer.toJson<String?>(sourceId),
      'ownerId': serializer.toJson<String?>(ownerId),
    };
  }

  ReviewEvent copyWith(
          {int? id,
          String? cardId,
          String? queue,
          int? reviewedAt,
          int? quality,
          int? prevIntervalDays,
          int? nextIntervalDays,
          double? prevEase,
          double? nextEase,
          int? reps,
          int? lapses,
          String? type,
          Value<String?> sourceKey = const Value.absent(),
          Value<String?> sourceKind = const Value.absent(),
          Value<String?> sourceId = const Value.absent(),
          Value<String?> ownerId = const Value.absent()}) =>
      ReviewEvent(
        id: id ?? this.id,
        cardId: cardId ?? this.cardId,
        queue: queue ?? this.queue,
        reviewedAt: reviewedAt ?? this.reviewedAt,
        quality: quality ?? this.quality,
        prevIntervalDays: prevIntervalDays ?? this.prevIntervalDays,
        nextIntervalDays: nextIntervalDays ?? this.nextIntervalDays,
        prevEase: prevEase ?? this.prevEase,
        nextEase: nextEase ?? this.nextEase,
        reps: reps ?? this.reps,
        lapses: lapses ?? this.lapses,
        type: type ?? this.type,
        sourceKey: sourceKey.present ? sourceKey.value : this.sourceKey,
        sourceKind: sourceKind.present ? sourceKind.value : this.sourceKind,
        sourceId: sourceId.present ? sourceId.value : this.sourceId,
        ownerId: ownerId.present ? ownerId.value : this.ownerId,
      );
  ReviewEvent copyWithCompanion(ReviewEventsCompanion data) {
    return ReviewEvent(
      id: data.id.present ? data.id.value : this.id,
      cardId: data.cardId.present ? data.cardId.value : this.cardId,
      queue: data.queue.present ? data.queue.value : this.queue,
      reviewedAt:
          data.reviewedAt.present ? data.reviewedAt.value : this.reviewedAt,
      quality: data.quality.present ? data.quality.value : this.quality,
      prevIntervalDays: data.prevIntervalDays.present
          ? data.prevIntervalDays.value
          : this.prevIntervalDays,
      nextIntervalDays: data.nextIntervalDays.present
          ? data.nextIntervalDays.value
          : this.nextIntervalDays,
      prevEase: data.prevEase.present ? data.prevEase.value : this.prevEase,
      nextEase: data.nextEase.present ? data.nextEase.value : this.nextEase,
      reps: data.reps.present ? data.reps.value : this.reps,
      lapses: data.lapses.present ? data.lapses.value : this.lapses,
      type: data.type.present ? data.type.value : this.type,
      sourceKey: data.sourceKey.present ? data.sourceKey.value : this.sourceKey,
      sourceKind:
          data.sourceKind.present ? data.sourceKind.value : this.sourceKind,
      sourceId: data.sourceId.present ? data.sourceId.value : this.sourceId,
      ownerId: data.ownerId.present ? data.ownerId.value : this.ownerId,
    );
  }

  @override
  String toString() {
    return (StringBuffer('ReviewEvent(')
          ..write('id: $id, ')
          ..write('cardId: $cardId, ')
          ..write('queue: $queue, ')
          ..write('reviewedAt: $reviewedAt, ')
          ..write('quality: $quality, ')
          ..write('prevIntervalDays: $prevIntervalDays, ')
          ..write('nextIntervalDays: $nextIntervalDays, ')
          ..write('prevEase: $prevEase, ')
          ..write('nextEase: $nextEase, ')
          ..write('reps: $reps, ')
          ..write('lapses: $lapses, ')
          ..write('type: $type, ')
          ..write('sourceKey: $sourceKey, ')
          ..write('sourceKind: $sourceKind, ')
          ..write('sourceId: $sourceId, ')
          ..write('ownerId: $ownerId')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
      id,
      cardId,
      queue,
      reviewedAt,
      quality,
      prevIntervalDays,
      nextIntervalDays,
      prevEase,
      nextEase,
      reps,
      lapses,
      type,
      sourceKey,
      sourceKind,
      sourceId,
      ownerId);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is ReviewEvent &&
          other.id == this.id &&
          other.cardId == this.cardId &&
          other.queue == this.queue &&
          other.reviewedAt == this.reviewedAt &&
          other.quality == this.quality &&
          other.prevIntervalDays == this.prevIntervalDays &&
          other.nextIntervalDays == this.nextIntervalDays &&
          other.prevEase == this.prevEase &&
          other.nextEase == this.nextEase &&
          other.reps == this.reps &&
          other.lapses == this.lapses &&
          other.type == this.type &&
          other.sourceKey == this.sourceKey &&
          other.sourceKind == this.sourceKind &&
          other.sourceId == this.sourceId &&
          other.ownerId == this.ownerId);
}

class ReviewEventsCompanion extends UpdateCompanion<ReviewEvent> {
  final Value<int> id;
  final Value<String> cardId;
  final Value<String> queue;
  final Value<int> reviewedAt;
  final Value<int> quality;
  final Value<int> prevIntervalDays;
  final Value<int> nextIntervalDays;
  final Value<double> prevEase;
  final Value<double> nextEase;
  final Value<int> reps;
  final Value<int> lapses;
  final Value<String> type;
  final Value<String?> sourceKey;
  final Value<String?> sourceKind;
  final Value<String?> sourceId;
  final Value<String?> ownerId;
  const ReviewEventsCompanion({
    this.id = const Value.absent(),
    this.cardId = const Value.absent(),
    this.queue = const Value.absent(),
    this.reviewedAt = const Value.absent(),
    this.quality = const Value.absent(),
    this.prevIntervalDays = const Value.absent(),
    this.nextIntervalDays = const Value.absent(),
    this.prevEase = const Value.absent(),
    this.nextEase = const Value.absent(),
    this.reps = const Value.absent(),
    this.lapses = const Value.absent(),
    this.type = const Value.absent(),
    this.sourceKey = const Value.absent(),
    this.sourceKind = const Value.absent(),
    this.sourceId = const Value.absent(),
    this.ownerId = const Value.absent(),
  });
  ReviewEventsCompanion.insert({
    this.id = const Value.absent(),
    required String cardId,
    required String queue,
    required int reviewedAt,
    required int quality,
    required int prevIntervalDays,
    required int nextIntervalDays,
    required double prevEase,
    required double nextEase,
    required int reps,
    required int lapses,
    this.type = const Value.absent(),
    this.sourceKey = const Value.absent(),
    this.sourceKind = const Value.absent(),
    this.sourceId = const Value.absent(),
    this.ownerId = const Value.absent(),
  })  : cardId = Value(cardId),
        queue = Value(queue),
        reviewedAt = Value(reviewedAt),
        quality = Value(quality),
        prevIntervalDays = Value(prevIntervalDays),
        nextIntervalDays = Value(nextIntervalDays),
        prevEase = Value(prevEase),
        nextEase = Value(nextEase),
        reps = Value(reps),
        lapses = Value(lapses);
  static Insertable<ReviewEvent> custom({
    Expression<int>? id,
    Expression<String>? cardId,
    Expression<String>? queue,
    Expression<int>? reviewedAt,
    Expression<int>? quality,
    Expression<int>? prevIntervalDays,
    Expression<int>? nextIntervalDays,
    Expression<double>? prevEase,
    Expression<double>? nextEase,
    Expression<int>? reps,
    Expression<int>? lapses,
    Expression<String>? type,
    Expression<String>? sourceKey,
    Expression<String>? sourceKind,
    Expression<String>? sourceId,
    Expression<String>? ownerId,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (cardId != null) 'card_id': cardId,
      if (queue != null) 'queue': queue,
      if (reviewedAt != null) 'reviewed_at': reviewedAt,
      if (quality != null) 'quality': quality,
      if (prevIntervalDays != null) 'prev_interval_days': prevIntervalDays,
      if (nextIntervalDays != null) 'next_interval_days': nextIntervalDays,
      if (prevEase != null) 'prev_ease': prevEase,
      if (nextEase != null) 'next_ease': nextEase,
      if (reps != null) 'reps': reps,
      if (lapses != null) 'lapses': lapses,
      if (type != null) 'type': type,
      if (sourceKey != null) 'source_key': sourceKey,
      if (sourceKind != null) 'source_kind': sourceKind,
      if (sourceId != null) 'source_id': sourceId,
      if (ownerId != null) 'owner_id': ownerId,
    });
  }

  ReviewEventsCompanion copyWith(
      {Value<int>? id,
      Value<String>? cardId,
      Value<String>? queue,
      Value<int>? reviewedAt,
      Value<int>? quality,
      Value<int>? prevIntervalDays,
      Value<int>? nextIntervalDays,
      Value<double>? prevEase,
      Value<double>? nextEase,
      Value<int>? reps,
      Value<int>? lapses,
      Value<String>? type,
      Value<String?>? sourceKey,
      Value<String?>? sourceKind,
      Value<String?>? sourceId,
      Value<String?>? ownerId}) {
    return ReviewEventsCompanion(
      id: id ?? this.id,
      cardId: cardId ?? this.cardId,
      queue: queue ?? this.queue,
      reviewedAt: reviewedAt ?? this.reviewedAt,
      quality: quality ?? this.quality,
      prevIntervalDays: prevIntervalDays ?? this.prevIntervalDays,
      nextIntervalDays: nextIntervalDays ?? this.nextIntervalDays,
      prevEase: prevEase ?? this.prevEase,
      nextEase: nextEase ?? this.nextEase,
      reps: reps ?? this.reps,
      lapses: lapses ?? this.lapses,
      type: type ?? this.type,
      sourceKey: sourceKey ?? this.sourceKey,
      sourceKind: sourceKind ?? this.sourceKind,
      sourceId: sourceId ?? this.sourceId,
      ownerId: ownerId ?? this.ownerId,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (cardId.present) {
      map['card_id'] = Variable<String>(cardId.value);
    }
    if (queue.present) {
      map['queue'] = Variable<String>(queue.value);
    }
    if (reviewedAt.present) {
      map['reviewed_at'] = Variable<int>(reviewedAt.value);
    }
    if (quality.present) {
      map['quality'] = Variable<int>(quality.value);
    }
    if (prevIntervalDays.present) {
      map['prev_interval_days'] = Variable<int>(prevIntervalDays.value);
    }
    if (nextIntervalDays.present) {
      map['next_interval_days'] = Variable<int>(nextIntervalDays.value);
    }
    if (prevEase.present) {
      map['prev_ease'] = Variable<double>(prevEase.value);
    }
    if (nextEase.present) {
      map['next_ease'] = Variable<double>(nextEase.value);
    }
    if (reps.present) {
      map['reps'] = Variable<int>(reps.value);
    }
    if (lapses.present) {
      map['lapses'] = Variable<int>(lapses.value);
    }
    if (type.present) {
      map['type'] = Variable<String>(type.value);
    }
    if (sourceKey.present) {
      map['source_key'] = Variable<String>(sourceKey.value);
    }
    if (sourceKind.present) {
      map['source_kind'] = Variable<String>(sourceKind.value);
    }
    if (sourceId.present) {
      map['source_id'] = Variable<String>(sourceId.value);
    }
    if (ownerId.present) {
      map['owner_id'] = Variable<String>(ownerId.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('ReviewEventsCompanion(')
          ..write('id: $id, ')
          ..write('cardId: $cardId, ')
          ..write('queue: $queue, ')
          ..write('reviewedAt: $reviewedAt, ')
          ..write('quality: $quality, ')
          ..write('prevIntervalDays: $prevIntervalDays, ')
          ..write('nextIntervalDays: $nextIntervalDays, ')
          ..write('prevEase: $prevEase, ')
          ..write('nextEase: $nextEase, ')
          ..write('reps: $reps, ')
          ..write('lapses: $lapses, ')
          ..write('type: $type, ')
          ..write('sourceKey: $sourceKey, ')
          ..write('sourceKind: $sourceKind, ')
          ..write('sourceId: $sourceId, ')
          ..write('ownerId: $ownerId')
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
  late final $AnkiImportsTable ankiImports = $AnkiImportsTable(this);
  late final $AnkiNotetypesTable ankiNotetypes = $AnkiNotetypesTable(this);
  late final $AnkiNotesTable ankiNotes = $AnkiNotesTable(this);
  late final $AnkiCardsMetaTable ankiCardsMeta = $AnkiCardsMetaTable(this);
  late final $AnkiPrerenderedHtmlTable ankiPrerenderedHtml =
      $AnkiPrerenderedHtmlTable(this);
  late final $SrsStatesTable srsStates = $SrsStatesTable(this);
  late final $ReviewEventsTable reviewEvents = $ReviewEventsTable(this);
  late final Index reviewEventsCardIdx = Index('review_events_card_idx',
      'CREATE INDEX review_events_card_idx ON review_events (card_id)');
  late final Index reviewEventsTimeIdx = Index('review_events_time_idx',
      'CREATE INDEX review_events_time_idx ON review_events (reviewed_at)');
  late final Index reviewEventsSourceIdx = Index('review_events_source_idx',
      'CREATE UNIQUE INDEX review_events_source_idx ON review_events (source_key)');
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
        expressions,
        ankiImports,
        ankiNotetypes,
        ankiNotes,
        ankiCardsMeta,
        ankiPrerenderedHtml,
        srsStates,
        reviewEvents,
        reviewEventsCardIdx,
        reviewEventsTimeIdx,
        reviewEventsSourceIdx
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
          WritePropagation(
            on: TableUpdateQuery.onTableName('anki_imports',
                limitUpdateKind: UpdateKind.delete),
            result: [
              TableUpdate('anki_notetypes', kind: UpdateKind.delete),
            ],
          ),
          WritePropagation(
            on: TableUpdateQuery.onTableName('anki_imports',
                limitUpdateKind: UpdateKind.delete),
            result: [
              TableUpdate('anki_notes', kind: UpdateKind.delete),
            ],
          ),
          WritePropagation(
            on: TableUpdateQuery.onTableName('anki_imports',
                limitUpdateKind: UpdateKind.delete),
            result: [
              TableUpdate('anki_cards_meta', kind: UpdateKind.delete),
            ],
          ),
        ],
      );
}

typedef $$SectionsTableCreateCompanionBuilder = SectionsCompanion Function({
  required String id,
  required String name,
  Value<String> description,
  Value<String> level,
  Value<String> prerequisiteSectionIds,
  Value<int> sortOrder,
  Value<int> rowid,
});
typedef $$SectionsTableUpdateCompanionBuilder = SectionsCompanion Function({
  Value<String> id,
  Value<String> name,
  Value<String> description,
  Value<String> level,
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
        .filter((f) => f.sectionId.id.sqlEquals($_itemColumn<String>('id')!));

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

  ColumnFilters<String> get level => $composableBuilder(
      column: $table.level, builder: (column) => ColumnFilters(column));

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

  ColumnOrderings<String> get level => $composableBuilder(
      column: $table.level, builder: (column) => ColumnOrderings(column));

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

  GeneratedColumn<String> get level =>
      $composableBuilder(column: $table.level, builder: (column) => column);

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
            Value<String> level = const Value.absent(),
            Value<String> prerequisiteSectionIds = const Value.absent(),
            Value<int> sortOrder = const Value.absent(),
            Value<int> rowid = const Value.absent(),
          }) =>
              SectionsCompanion(
            id: id,
            name: name,
            description: description,
            level: level,
            prerequisiteSectionIds: prerequisiteSectionIds,
            sortOrder: sortOrder,
            rowid: rowid,
          ),
          createCompanionCallback: ({
            required String id,
            required String name,
            Value<String> description = const Value.absent(),
            Value<String> level = const Value.absent(),
            Value<String> prerequisiteSectionIds = const Value.absent(),
            Value<int> sortOrder = const Value.absent(),
            Value<int> rowid = const Value.absent(),
          }) =>
              SectionsCompanion.insert(
            id: id,
            name: name,
            description: description,
            level: level,
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
                    await $_getPrefetchedData<Section, $SectionsTable, Unit>(
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

  $$SectionsTableProcessedTableManager get sectionId {
    final $_column = $_itemColumn<String>('section_id')!;

    final manager = $$SectionsTableTableManager($_db, $_db.sections)
        .filter((f) => f.id.sqlEquals($_column));
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
        .filter((f) => f.unitId.id.sqlEquals($_itemColumn<String>('id')!));

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
                    await $_getPrefetchedData<Unit, $UnitsTable, Lesson>(
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

  $$UnitsTableProcessedTableManager get unitId {
    final $_column = $_itemColumn<String>('unit_id')!;

    final manager = $$UnitsTableTableManager($_db, $_db.units)
        .filter((f) => f.id.sqlEquals($_column));
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
        .filter((f) => f.lessonId.id.sqlEquals($_itemColumn<String>('id')!));

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
                    await $_getPrefetchedData<Lesson, $LessonsTable,
                            LessonContent>(
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

  $$LessonsTableProcessedTableManager get lessonId {
    final $_column = $_itemColumn<String>('lesson_id')!;

    final manager = $$LessonsTableTableManager($_db, $_db.lessons)
        .filter((f) => f.id.sqlEquals($_column));
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
typedef $$AnkiImportsTableCreateCompanionBuilder = AnkiImportsCompanion
    Function({
  required String importId,
  required String sourcePath,
  required String sourceHash,
  required int importedAt,
  Value<int> deckCount,
  Value<int> noteCount,
  Value<int> cardCount,
  Value<int> mediaCount,
  Value<String> notetypesJson,
  Value<bool> aiEnhanced,
  Value<int> version,
  Value<int> rowid,
});
typedef $$AnkiImportsTableUpdateCompanionBuilder = AnkiImportsCompanion
    Function({
  Value<String> importId,
  Value<String> sourcePath,
  Value<String> sourceHash,
  Value<int> importedAt,
  Value<int> deckCount,
  Value<int> noteCount,
  Value<int> cardCount,
  Value<int> mediaCount,
  Value<String> notetypesJson,
  Value<bool> aiEnhanced,
  Value<int> version,
  Value<int> rowid,
});

final class $$AnkiImportsTableReferences
    extends BaseReferences<_$CourseDatabase, $AnkiImportsTable, AnkiImport> {
  $$AnkiImportsTableReferences(super.$_db, super.$_table, super.$_typedResult);

  static MultiTypedResultKey<$AnkiNotetypesTable, List<AnkiNotetypeRow>>
      _ankiNotetypesRefsTable(_$CourseDatabase db) =>
          MultiTypedResultKey.fromTable(db.ankiNotetypes,
              aliasName: $_aliasNameGenerator(
                  db.ankiImports.importId, db.ankiNotetypes.importId));

  $$AnkiNotetypesTableProcessedTableManager get ankiNotetypesRefs {
    final manager = $$AnkiNotetypesTableTableManager($_db, $_db.ankiNotetypes)
        .filter((f) =>
            f.importId.importId.sqlEquals($_itemColumn<String>('import_id')!));

    final cache = $_typedResult.readTableOrNull(_ankiNotetypesRefsTable($_db));
    return ProcessedTableManager(
        manager.$state.copyWith(prefetchedData: cache));
  }

  static MultiTypedResultKey<$AnkiNotesTable, List<AnkiNoteRow>>
      _ankiNotesRefsTable(_$CourseDatabase db) =>
          MultiTypedResultKey.fromTable(db.ankiNotes,
              aliasName: $_aliasNameGenerator(
                  db.ankiImports.importId, db.ankiNotes.importId));

  $$AnkiNotesTableProcessedTableManager get ankiNotesRefs {
    final manager = $$AnkiNotesTableTableManager($_db, $_db.ankiNotes).filter(
        (f) =>
            f.importId.importId.sqlEquals($_itemColumn<String>('import_id')!));

    final cache = $_typedResult.readTableOrNull(_ankiNotesRefsTable($_db));
    return ProcessedTableManager(
        manager.$state.copyWith(prefetchedData: cache));
  }

  static MultiTypedResultKey<$AnkiCardsMetaTable, List<AnkiCardMetaRow>>
      _ankiCardsMetaRefsTable(_$CourseDatabase db) =>
          MultiTypedResultKey.fromTable(db.ankiCardsMeta,
              aliasName: $_aliasNameGenerator(
                  db.ankiImports.importId, db.ankiCardsMeta.importId));

  $$AnkiCardsMetaTableProcessedTableManager get ankiCardsMetaRefs {
    final manager = $$AnkiCardsMetaTableTableManager($_db, $_db.ankiCardsMeta)
        .filter((f) =>
            f.importId.importId.sqlEquals($_itemColumn<String>('import_id')!));

    final cache = $_typedResult.readTableOrNull(_ankiCardsMetaRefsTable($_db));
    return ProcessedTableManager(
        manager.$state.copyWith(prefetchedData: cache));
  }
}

class $$AnkiImportsTableFilterComposer
    extends Composer<_$CourseDatabase, $AnkiImportsTable> {
  $$AnkiImportsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get importId => $composableBuilder(
      column: $table.importId, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get sourcePath => $composableBuilder(
      column: $table.sourcePath, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get sourceHash => $composableBuilder(
      column: $table.sourceHash, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get importedAt => $composableBuilder(
      column: $table.importedAt, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get deckCount => $composableBuilder(
      column: $table.deckCount, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get noteCount => $composableBuilder(
      column: $table.noteCount, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get cardCount => $composableBuilder(
      column: $table.cardCount, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get mediaCount => $composableBuilder(
      column: $table.mediaCount, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get notetypesJson => $composableBuilder(
      column: $table.notetypesJson, builder: (column) => ColumnFilters(column));

  ColumnFilters<bool> get aiEnhanced => $composableBuilder(
      column: $table.aiEnhanced, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get version => $composableBuilder(
      column: $table.version, builder: (column) => ColumnFilters(column));

  Expression<bool> ankiNotetypesRefs(
      Expression<bool> Function($$AnkiNotetypesTableFilterComposer f) f) {
    final $$AnkiNotetypesTableFilterComposer composer = $composerBuilder(
        composer: this,
        getCurrentColumn: (t) => t.importId,
        referencedTable: $db.ankiNotetypes,
        getReferencedColumn: (t) => t.importId,
        builder: (joinBuilder,
                {$addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer}) =>
            $$AnkiNotetypesTableFilterComposer(
              $db: $db,
              $table: $db.ankiNotetypes,
              $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
              joinBuilder: joinBuilder,
              $removeJoinBuilderFromRootComposer:
                  $removeJoinBuilderFromRootComposer,
            ));
    return f(composer);
  }

  Expression<bool> ankiNotesRefs(
      Expression<bool> Function($$AnkiNotesTableFilterComposer f) f) {
    final $$AnkiNotesTableFilterComposer composer = $composerBuilder(
        composer: this,
        getCurrentColumn: (t) => t.importId,
        referencedTable: $db.ankiNotes,
        getReferencedColumn: (t) => t.importId,
        builder: (joinBuilder,
                {$addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer}) =>
            $$AnkiNotesTableFilterComposer(
              $db: $db,
              $table: $db.ankiNotes,
              $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
              joinBuilder: joinBuilder,
              $removeJoinBuilderFromRootComposer:
                  $removeJoinBuilderFromRootComposer,
            ));
    return f(composer);
  }

  Expression<bool> ankiCardsMetaRefs(
      Expression<bool> Function($$AnkiCardsMetaTableFilterComposer f) f) {
    final $$AnkiCardsMetaTableFilterComposer composer = $composerBuilder(
        composer: this,
        getCurrentColumn: (t) => t.importId,
        referencedTable: $db.ankiCardsMeta,
        getReferencedColumn: (t) => t.importId,
        builder: (joinBuilder,
                {$addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer}) =>
            $$AnkiCardsMetaTableFilterComposer(
              $db: $db,
              $table: $db.ankiCardsMeta,
              $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
              joinBuilder: joinBuilder,
              $removeJoinBuilderFromRootComposer:
                  $removeJoinBuilderFromRootComposer,
            ));
    return f(composer);
  }
}

class $$AnkiImportsTableOrderingComposer
    extends Composer<_$CourseDatabase, $AnkiImportsTable> {
  $$AnkiImportsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get importId => $composableBuilder(
      column: $table.importId, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get sourcePath => $composableBuilder(
      column: $table.sourcePath, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get sourceHash => $composableBuilder(
      column: $table.sourceHash, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get importedAt => $composableBuilder(
      column: $table.importedAt, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get deckCount => $composableBuilder(
      column: $table.deckCount, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get noteCount => $composableBuilder(
      column: $table.noteCount, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get cardCount => $composableBuilder(
      column: $table.cardCount, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get mediaCount => $composableBuilder(
      column: $table.mediaCount, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get notetypesJson => $composableBuilder(
      column: $table.notetypesJson,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<bool> get aiEnhanced => $composableBuilder(
      column: $table.aiEnhanced, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get version => $composableBuilder(
      column: $table.version, builder: (column) => ColumnOrderings(column));
}

class $$AnkiImportsTableAnnotationComposer
    extends Composer<_$CourseDatabase, $AnkiImportsTable> {
  $$AnkiImportsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get importId =>
      $composableBuilder(column: $table.importId, builder: (column) => column);

  GeneratedColumn<String> get sourcePath => $composableBuilder(
      column: $table.sourcePath, builder: (column) => column);

  GeneratedColumn<String> get sourceHash => $composableBuilder(
      column: $table.sourceHash, builder: (column) => column);

  GeneratedColumn<int> get importedAt => $composableBuilder(
      column: $table.importedAt, builder: (column) => column);

  GeneratedColumn<int> get deckCount =>
      $composableBuilder(column: $table.deckCount, builder: (column) => column);

  GeneratedColumn<int> get noteCount =>
      $composableBuilder(column: $table.noteCount, builder: (column) => column);

  GeneratedColumn<int> get cardCount =>
      $composableBuilder(column: $table.cardCount, builder: (column) => column);

  GeneratedColumn<int> get mediaCount => $composableBuilder(
      column: $table.mediaCount, builder: (column) => column);

  GeneratedColumn<String> get notetypesJson => $composableBuilder(
      column: $table.notetypesJson, builder: (column) => column);

  GeneratedColumn<bool> get aiEnhanced => $composableBuilder(
      column: $table.aiEnhanced, builder: (column) => column);

  GeneratedColumn<int> get version =>
      $composableBuilder(column: $table.version, builder: (column) => column);

  Expression<T> ankiNotetypesRefs<T extends Object>(
      Expression<T> Function($$AnkiNotetypesTableAnnotationComposer a) f) {
    final $$AnkiNotetypesTableAnnotationComposer composer = $composerBuilder(
        composer: this,
        getCurrentColumn: (t) => t.importId,
        referencedTable: $db.ankiNotetypes,
        getReferencedColumn: (t) => t.importId,
        builder: (joinBuilder,
                {$addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer}) =>
            $$AnkiNotetypesTableAnnotationComposer(
              $db: $db,
              $table: $db.ankiNotetypes,
              $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
              joinBuilder: joinBuilder,
              $removeJoinBuilderFromRootComposer:
                  $removeJoinBuilderFromRootComposer,
            ));
    return f(composer);
  }

  Expression<T> ankiNotesRefs<T extends Object>(
      Expression<T> Function($$AnkiNotesTableAnnotationComposer a) f) {
    final $$AnkiNotesTableAnnotationComposer composer = $composerBuilder(
        composer: this,
        getCurrentColumn: (t) => t.importId,
        referencedTable: $db.ankiNotes,
        getReferencedColumn: (t) => t.importId,
        builder: (joinBuilder,
                {$addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer}) =>
            $$AnkiNotesTableAnnotationComposer(
              $db: $db,
              $table: $db.ankiNotes,
              $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
              joinBuilder: joinBuilder,
              $removeJoinBuilderFromRootComposer:
                  $removeJoinBuilderFromRootComposer,
            ));
    return f(composer);
  }

  Expression<T> ankiCardsMetaRefs<T extends Object>(
      Expression<T> Function($$AnkiCardsMetaTableAnnotationComposer a) f) {
    final $$AnkiCardsMetaTableAnnotationComposer composer = $composerBuilder(
        composer: this,
        getCurrentColumn: (t) => t.importId,
        referencedTable: $db.ankiCardsMeta,
        getReferencedColumn: (t) => t.importId,
        builder: (joinBuilder,
                {$addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer}) =>
            $$AnkiCardsMetaTableAnnotationComposer(
              $db: $db,
              $table: $db.ankiCardsMeta,
              $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
              joinBuilder: joinBuilder,
              $removeJoinBuilderFromRootComposer:
                  $removeJoinBuilderFromRootComposer,
            ));
    return f(composer);
  }
}

class $$AnkiImportsTableTableManager extends RootTableManager<
    _$CourseDatabase,
    $AnkiImportsTable,
    AnkiImport,
    $$AnkiImportsTableFilterComposer,
    $$AnkiImportsTableOrderingComposer,
    $$AnkiImportsTableAnnotationComposer,
    $$AnkiImportsTableCreateCompanionBuilder,
    $$AnkiImportsTableUpdateCompanionBuilder,
    (AnkiImport, $$AnkiImportsTableReferences),
    AnkiImport,
    PrefetchHooks Function(
        {bool ankiNotetypesRefs, bool ankiNotesRefs, bool ankiCardsMetaRefs})> {
  $$AnkiImportsTableTableManager(_$CourseDatabase db, $AnkiImportsTable table)
      : super(TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$AnkiImportsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$AnkiImportsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$AnkiImportsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback: ({
            Value<String> importId = const Value.absent(),
            Value<String> sourcePath = const Value.absent(),
            Value<String> sourceHash = const Value.absent(),
            Value<int> importedAt = const Value.absent(),
            Value<int> deckCount = const Value.absent(),
            Value<int> noteCount = const Value.absent(),
            Value<int> cardCount = const Value.absent(),
            Value<int> mediaCount = const Value.absent(),
            Value<String> notetypesJson = const Value.absent(),
            Value<bool> aiEnhanced = const Value.absent(),
            Value<int> version = const Value.absent(),
            Value<int> rowid = const Value.absent(),
          }) =>
              AnkiImportsCompanion(
            importId: importId,
            sourcePath: sourcePath,
            sourceHash: sourceHash,
            importedAt: importedAt,
            deckCount: deckCount,
            noteCount: noteCount,
            cardCount: cardCount,
            mediaCount: mediaCount,
            notetypesJson: notetypesJson,
            aiEnhanced: aiEnhanced,
            version: version,
            rowid: rowid,
          ),
          createCompanionCallback: ({
            required String importId,
            required String sourcePath,
            required String sourceHash,
            required int importedAt,
            Value<int> deckCount = const Value.absent(),
            Value<int> noteCount = const Value.absent(),
            Value<int> cardCount = const Value.absent(),
            Value<int> mediaCount = const Value.absent(),
            Value<String> notetypesJson = const Value.absent(),
            Value<bool> aiEnhanced = const Value.absent(),
            Value<int> version = const Value.absent(),
            Value<int> rowid = const Value.absent(),
          }) =>
              AnkiImportsCompanion.insert(
            importId: importId,
            sourcePath: sourcePath,
            sourceHash: sourceHash,
            importedAt: importedAt,
            deckCount: deckCount,
            noteCount: noteCount,
            cardCount: cardCount,
            mediaCount: mediaCount,
            notetypesJson: notetypesJson,
            aiEnhanced: aiEnhanced,
            version: version,
            rowid: rowid,
          ),
          withReferenceMapper: (p0) => p0
              .map((e) => (
                    e.readTable(table),
                    $$AnkiImportsTableReferences(db, table, e)
                  ))
              .toList(),
          prefetchHooksCallback: (
              {ankiNotetypesRefs = false,
              ankiNotesRefs = false,
              ankiCardsMetaRefs = false}) {
            return PrefetchHooks(
              db: db,
              explicitlyWatchedTables: [
                if (ankiNotetypesRefs) db.ankiNotetypes,
                if (ankiNotesRefs) db.ankiNotes,
                if (ankiCardsMetaRefs) db.ankiCardsMeta
              ],
              addJoins: null,
              getPrefetchedDataCallback: (items) async {
                return [
                  if (ankiNotetypesRefs)
                    await $_getPrefetchedData<AnkiImport, $AnkiImportsTable,
                            AnkiNotetypeRow>(
                        currentTable: table,
                        referencedTable: $$AnkiImportsTableReferences
                            ._ankiNotetypesRefsTable(db),
                        managerFromTypedResult: (p0) =>
                            $$AnkiImportsTableReferences(db, table, p0)
                                .ankiNotetypesRefs,
                        referencedItemsForCurrentItem:
                            (item, referencedItems) => referencedItems
                                .where((e) => e.importId == item.importId),
                        typedResults: items),
                  if (ankiNotesRefs)
                    await $_getPrefetchedData<AnkiImport, $AnkiImportsTable,
                            AnkiNoteRow>(
                        currentTable: table,
                        referencedTable: $$AnkiImportsTableReferences
                            ._ankiNotesRefsTable(db),
                        managerFromTypedResult: (p0) =>
                            $$AnkiImportsTableReferences(db, table, p0)
                                .ankiNotesRefs,
                        referencedItemsForCurrentItem:
                            (item, referencedItems) => referencedItems
                                .where((e) => e.importId == item.importId),
                        typedResults: items),
                  if (ankiCardsMetaRefs)
                    await $_getPrefetchedData<AnkiImport, $AnkiImportsTable,
                            AnkiCardMetaRow>(
                        currentTable: table,
                        referencedTable: $$AnkiImportsTableReferences
                            ._ankiCardsMetaRefsTable(db),
                        managerFromTypedResult: (p0) =>
                            $$AnkiImportsTableReferences(db, table, p0)
                                .ankiCardsMetaRefs,
                        referencedItemsForCurrentItem:
                            (item, referencedItems) => referencedItems
                                .where((e) => e.importId == item.importId),
                        typedResults: items)
                ];
              },
            );
          },
        ));
}

typedef $$AnkiImportsTableProcessedTableManager = ProcessedTableManager<
    _$CourseDatabase,
    $AnkiImportsTable,
    AnkiImport,
    $$AnkiImportsTableFilterComposer,
    $$AnkiImportsTableOrderingComposer,
    $$AnkiImportsTableAnnotationComposer,
    $$AnkiImportsTableCreateCompanionBuilder,
    $$AnkiImportsTableUpdateCompanionBuilder,
    (AnkiImport, $$AnkiImportsTableReferences),
    AnkiImport,
    PrefetchHooks Function(
        {bool ankiNotetypesRefs, bool ankiNotesRefs, bool ankiCardsMetaRefs})>;
typedef $$AnkiNotetypesTableCreateCompanionBuilder = AnkiNotetypesCompanion
    Function({
  required String importId,
  required int mid,
  Value<String> name,
  Value<bool> isCloze,
  Value<String> fieldNamesJson,
  Value<String> templatesJson,
  Value<String> css,
  Value<bool> allowJs,
  Value<int> rowid,
});
typedef $$AnkiNotetypesTableUpdateCompanionBuilder = AnkiNotetypesCompanion
    Function({
  Value<String> importId,
  Value<int> mid,
  Value<String> name,
  Value<bool> isCloze,
  Value<String> fieldNamesJson,
  Value<String> templatesJson,
  Value<String> css,
  Value<bool> allowJs,
  Value<int> rowid,
});

final class $$AnkiNotetypesTableReferences extends BaseReferences<
    _$CourseDatabase, $AnkiNotetypesTable, AnkiNotetypeRow> {
  $$AnkiNotetypesTableReferences(
      super.$_db, super.$_table, super.$_typedResult);

  static $AnkiImportsTable _importIdTable(_$CourseDatabase db) =>
      db.ankiImports.createAlias($_aliasNameGenerator(
          db.ankiNotetypes.importId, db.ankiImports.importId));

  $$AnkiImportsTableProcessedTableManager get importId {
    final $_column = $_itemColumn<String>('import_id')!;

    final manager = $$AnkiImportsTableTableManager($_db, $_db.ankiImports)
        .filter((f) => f.importId.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_importIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
        manager.$state.copyWith(prefetchedData: [item]));
  }
}

class $$AnkiNotetypesTableFilterComposer
    extends Composer<_$CourseDatabase, $AnkiNotetypesTable> {
  $$AnkiNotetypesTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get mid => $composableBuilder(
      column: $table.mid, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get name => $composableBuilder(
      column: $table.name, builder: (column) => ColumnFilters(column));

  ColumnFilters<bool> get isCloze => $composableBuilder(
      column: $table.isCloze, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get fieldNamesJson => $composableBuilder(
      column: $table.fieldNamesJson,
      builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get templatesJson => $composableBuilder(
      column: $table.templatesJson, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get css => $composableBuilder(
      column: $table.css, builder: (column) => ColumnFilters(column));

  ColumnFilters<bool> get allowJs => $composableBuilder(
      column: $table.allowJs, builder: (column) => ColumnFilters(column));

  $$AnkiImportsTableFilterComposer get importId {
    final $$AnkiImportsTableFilterComposer composer = $composerBuilder(
        composer: this,
        getCurrentColumn: (t) => t.importId,
        referencedTable: $db.ankiImports,
        getReferencedColumn: (t) => t.importId,
        builder: (joinBuilder,
                {$addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer}) =>
            $$AnkiImportsTableFilterComposer(
              $db: $db,
              $table: $db.ankiImports,
              $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
              joinBuilder: joinBuilder,
              $removeJoinBuilderFromRootComposer:
                  $removeJoinBuilderFromRootComposer,
            ));
    return composer;
  }
}

class $$AnkiNotetypesTableOrderingComposer
    extends Composer<_$CourseDatabase, $AnkiNotetypesTable> {
  $$AnkiNotetypesTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get mid => $composableBuilder(
      column: $table.mid, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get name => $composableBuilder(
      column: $table.name, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<bool> get isCloze => $composableBuilder(
      column: $table.isCloze, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get fieldNamesJson => $composableBuilder(
      column: $table.fieldNamesJson,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get templatesJson => $composableBuilder(
      column: $table.templatesJson,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get css => $composableBuilder(
      column: $table.css, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<bool> get allowJs => $composableBuilder(
      column: $table.allowJs, builder: (column) => ColumnOrderings(column));

  $$AnkiImportsTableOrderingComposer get importId {
    final $$AnkiImportsTableOrderingComposer composer = $composerBuilder(
        composer: this,
        getCurrentColumn: (t) => t.importId,
        referencedTable: $db.ankiImports,
        getReferencedColumn: (t) => t.importId,
        builder: (joinBuilder,
                {$addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer}) =>
            $$AnkiImportsTableOrderingComposer(
              $db: $db,
              $table: $db.ankiImports,
              $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
              joinBuilder: joinBuilder,
              $removeJoinBuilderFromRootComposer:
                  $removeJoinBuilderFromRootComposer,
            ));
    return composer;
  }
}

class $$AnkiNotetypesTableAnnotationComposer
    extends Composer<_$CourseDatabase, $AnkiNotetypesTable> {
  $$AnkiNotetypesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get mid =>
      $composableBuilder(column: $table.mid, builder: (column) => column);

  GeneratedColumn<String> get name =>
      $composableBuilder(column: $table.name, builder: (column) => column);

  GeneratedColumn<bool> get isCloze =>
      $composableBuilder(column: $table.isCloze, builder: (column) => column);

  GeneratedColumn<String> get fieldNamesJson => $composableBuilder(
      column: $table.fieldNamesJson, builder: (column) => column);

  GeneratedColumn<String> get templatesJson => $composableBuilder(
      column: $table.templatesJson, builder: (column) => column);

  GeneratedColumn<String> get css =>
      $composableBuilder(column: $table.css, builder: (column) => column);

  GeneratedColumn<bool> get allowJs =>
      $composableBuilder(column: $table.allowJs, builder: (column) => column);

  $$AnkiImportsTableAnnotationComposer get importId {
    final $$AnkiImportsTableAnnotationComposer composer = $composerBuilder(
        composer: this,
        getCurrentColumn: (t) => t.importId,
        referencedTable: $db.ankiImports,
        getReferencedColumn: (t) => t.importId,
        builder: (joinBuilder,
                {$addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer}) =>
            $$AnkiImportsTableAnnotationComposer(
              $db: $db,
              $table: $db.ankiImports,
              $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
              joinBuilder: joinBuilder,
              $removeJoinBuilderFromRootComposer:
                  $removeJoinBuilderFromRootComposer,
            ));
    return composer;
  }
}

class $$AnkiNotetypesTableTableManager extends RootTableManager<
    _$CourseDatabase,
    $AnkiNotetypesTable,
    AnkiNotetypeRow,
    $$AnkiNotetypesTableFilterComposer,
    $$AnkiNotetypesTableOrderingComposer,
    $$AnkiNotetypesTableAnnotationComposer,
    $$AnkiNotetypesTableCreateCompanionBuilder,
    $$AnkiNotetypesTableUpdateCompanionBuilder,
    (AnkiNotetypeRow, $$AnkiNotetypesTableReferences),
    AnkiNotetypeRow,
    PrefetchHooks Function({bool importId})> {
  $$AnkiNotetypesTableTableManager(
      _$CourseDatabase db, $AnkiNotetypesTable table)
      : super(TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$AnkiNotetypesTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$AnkiNotetypesTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$AnkiNotetypesTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback: ({
            Value<String> importId = const Value.absent(),
            Value<int> mid = const Value.absent(),
            Value<String> name = const Value.absent(),
            Value<bool> isCloze = const Value.absent(),
            Value<String> fieldNamesJson = const Value.absent(),
            Value<String> templatesJson = const Value.absent(),
            Value<String> css = const Value.absent(),
            Value<bool> allowJs = const Value.absent(),
            Value<int> rowid = const Value.absent(),
          }) =>
              AnkiNotetypesCompanion(
            importId: importId,
            mid: mid,
            name: name,
            isCloze: isCloze,
            fieldNamesJson: fieldNamesJson,
            templatesJson: templatesJson,
            css: css,
            allowJs: allowJs,
            rowid: rowid,
          ),
          createCompanionCallback: ({
            required String importId,
            required int mid,
            Value<String> name = const Value.absent(),
            Value<bool> isCloze = const Value.absent(),
            Value<String> fieldNamesJson = const Value.absent(),
            Value<String> templatesJson = const Value.absent(),
            Value<String> css = const Value.absent(),
            Value<bool> allowJs = const Value.absent(),
            Value<int> rowid = const Value.absent(),
          }) =>
              AnkiNotetypesCompanion.insert(
            importId: importId,
            mid: mid,
            name: name,
            isCloze: isCloze,
            fieldNamesJson: fieldNamesJson,
            templatesJson: templatesJson,
            css: css,
            allowJs: allowJs,
            rowid: rowid,
          ),
          withReferenceMapper: (p0) => p0
              .map((e) => (
                    e.readTable(table),
                    $$AnkiNotetypesTableReferences(db, table, e)
                  ))
              .toList(),
          prefetchHooksCallback: ({importId = false}) {
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
                if (importId) {
                  state = state.withJoin(
                    currentTable: table,
                    currentColumn: table.importId,
                    referencedTable:
                        $$AnkiNotetypesTableReferences._importIdTable(db),
                    referencedColumn: $$AnkiNotetypesTableReferences
                        ._importIdTable(db)
                        .importId,
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

typedef $$AnkiNotetypesTableProcessedTableManager = ProcessedTableManager<
    _$CourseDatabase,
    $AnkiNotetypesTable,
    AnkiNotetypeRow,
    $$AnkiNotetypesTableFilterComposer,
    $$AnkiNotetypesTableOrderingComposer,
    $$AnkiNotetypesTableAnnotationComposer,
    $$AnkiNotetypesTableCreateCompanionBuilder,
    $$AnkiNotetypesTableUpdateCompanionBuilder,
    (AnkiNotetypeRow, $$AnkiNotetypesTableReferences),
    AnkiNotetypeRow,
    PrefetchHooks Function({bool importId})>;
typedef $$AnkiNotesTableCreateCompanionBuilder = AnkiNotesCompanion Function({
  required String importId,
  required int noteId,
  required int mid,
  Value<String> tags,
  Value<String> fieldsJson,
  Value<String> sfld,
  Value<String> guid,
  Value<int> mod,
  Value<int> rowid,
});
typedef $$AnkiNotesTableUpdateCompanionBuilder = AnkiNotesCompanion Function({
  Value<String> importId,
  Value<int> noteId,
  Value<int> mid,
  Value<String> tags,
  Value<String> fieldsJson,
  Value<String> sfld,
  Value<String> guid,
  Value<int> mod,
  Value<int> rowid,
});

final class $$AnkiNotesTableReferences
    extends BaseReferences<_$CourseDatabase, $AnkiNotesTable, AnkiNoteRow> {
  $$AnkiNotesTableReferences(super.$_db, super.$_table, super.$_typedResult);

  static $AnkiImportsTable _importIdTable(_$CourseDatabase db) =>
      db.ankiImports.createAlias(
          $_aliasNameGenerator(db.ankiNotes.importId, db.ankiImports.importId));

  $$AnkiImportsTableProcessedTableManager get importId {
    final $_column = $_itemColumn<String>('import_id')!;

    final manager = $$AnkiImportsTableTableManager($_db, $_db.ankiImports)
        .filter((f) => f.importId.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_importIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
        manager.$state.copyWith(prefetchedData: [item]));
  }
}

class $$AnkiNotesTableFilterComposer
    extends Composer<_$CourseDatabase, $AnkiNotesTable> {
  $$AnkiNotesTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get noteId => $composableBuilder(
      column: $table.noteId, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get mid => $composableBuilder(
      column: $table.mid, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get tags => $composableBuilder(
      column: $table.tags, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get fieldsJson => $composableBuilder(
      column: $table.fieldsJson, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get sfld => $composableBuilder(
      column: $table.sfld, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get guid => $composableBuilder(
      column: $table.guid, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get mod => $composableBuilder(
      column: $table.mod, builder: (column) => ColumnFilters(column));

  $$AnkiImportsTableFilterComposer get importId {
    final $$AnkiImportsTableFilterComposer composer = $composerBuilder(
        composer: this,
        getCurrentColumn: (t) => t.importId,
        referencedTable: $db.ankiImports,
        getReferencedColumn: (t) => t.importId,
        builder: (joinBuilder,
                {$addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer}) =>
            $$AnkiImportsTableFilterComposer(
              $db: $db,
              $table: $db.ankiImports,
              $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
              joinBuilder: joinBuilder,
              $removeJoinBuilderFromRootComposer:
                  $removeJoinBuilderFromRootComposer,
            ));
    return composer;
  }
}

class $$AnkiNotesTableOrderingComposer
    extends Composer<_$CourseDatabase, $AnkiNotesTable> {
  $$AnkiNotesTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get noteId => $composableBuilder(
      column: $table.noteId, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get mid => $composableBuilder(
      column: $table.mid, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get tags => $composableBuilder(
      column: $table.tags, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get fieldsJson => $composableBuilder(
      column: $table.fieldsJson, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get sfld => $composableBuilder(
      column: $table.sfld, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get guid => $composableBuilder(
      column: $table.guid, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get mod => $composableBuilder(
      column: $table.mod, builder: (column) => ColumnOrderings(column));

  $$AnkiImportsTableOrderingComposer get importId {
    final $$AnkiImportsTableOrderingComposer composer = $composerBuilder(
        composer: this,
        getCurrentColumn: (t) => t.importId,
        referencedTable: $db.ankiImports,
        getReferencedColumn: (t) => t.importId,
        builder: (joinBuilder,
                {$addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer}) =>
            $$AnkiImportsTableOrderingComposer(
              $db: $db,
              $table: $db.ankiImports,
              $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
              joinBuilder: joinBuilder,
              $removeJoinBuilderFromRootComposer:
                  $removeJoinBuilderFromRootComposer,
            ));
    return composer;
  }
}

class $$AnkiNotesTableAnnotationComposer
    extends Composer<_$CourseDatabase, $AnkiNotesTable> {
  $$AnkiNotesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get noteId =>
      $composableBuilder(column: $table.noteId, builder: (column) => column);

  GeneratedColumn<int> get mid =>
      $composableBuilder(column: $table.mid, builder: (column) => column);

  GeneratedColumn<String> get tags =>
      $composableBuilder(column: $table.tags, builder: (column) => column);

  GeneratedColumn<String> get fieldsJson => $composableBuilder(
      column: $table.fieldsJson, builder: (column) => column);

  GeneratedColumn<String> get sfld =>
      $composableBuilder(column: $table.sfld, builder: (column) => column);

  GeneratedColumn<String> get guid =>
      $composableBuilder(column: $table.guid, builder: (column) => column);

  GeneratedColumn<int> get mod =>
      $composableBuilder(column: $table.mod, builder: (column) => column);

  $$AnkiImportsTableAnnotationComposer get importId {
    final $$AnkiImportsTableAnnotationComposer composer = $composerBuilder(
        composer: this,
        getCurrentColumn: (t) => t.importId,
        referencedTable: $db.ankiImports,
        getReferencedColumn: (t) => t.importId,
        builder: (joinBuilder,
                {$addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer}) =>
            $$AnkiImportsTableAnnotationComposer(
              $db: $db,
              $table: $db.ankiImports,
              $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
              joinBuilder: joinBuilder,
              $removeJoinBuilderFromRootComposer:
                  $removeJoinBuilderFromRootComposer,
            ));
    return composer;
  }
}

class $$AnkiNotesTableTableManager extends RootTableManager<
    _$CourseDatabase,
    $AnkiNotesTable,
    AnkiNoteRow,
    $$AnkiNotesTableFilterComposer,
    $$AnkiNotesTableOrderingComposer,
    $$AnkiNotesTableAnnotationComposer,
    $$AnkiNotesTableCreateCompanionBuilder,
    $$AnkiNotesTableUpdateCompanionBuilder,
    (AnkiNoteRow, $$AnkiNotesTableReferences),
    AnkiNoteRow,
    PrefetchHooks Function({bool importId})> {
  $$AnkiNotesTableTableManager(_$CourseDatabase db, $AnkiNotesTable table)
      : super(TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$AnkiNotesTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$AnkiNotesTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$AnkiNotesTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback: ({
            Value<String> importId = const Value.absent(),
            Value<int> noteId = const Value.absent(),
            Value<int> mid = const Value.absent(),
            Value<String> tags = const Value.absent(),
            Value<String> fieldsJson = const Value.absent(),
            Value<String> sfld = const Value.absent(),
            Value<String> guid = const Value.absent(),
            Value<int> mod = const Value.absent(),
            Value<int> rowid = const Value.absent(),
          }) =>
              AnkiNotesCompanion(
            importId: importId,
            noteId: noteId,
            mid: mid,
            tags: tags,
            fieldsJson: fieldsJson,
            sfld: sfld,
            guid: guid,
            mod: mod,
            rowid: rowid,
          ),
          createCompanionCallback: ({
            required String importId,
            required int noteId,
            required int mid,
            Value<String> tags = const Value.absent(),
            Value<String> fieldsJson = const Value.absent(),
            Value<String> sfld = const Value.absent(),
            Value<String> guid = const Value.absent(),
            Value<int> mod = const Value.absent(),
            Value<int> rowid = const Value.absent(),
          }) =>
              AnkiNotesCompanion.insert(
            importId: importId,
            noteId: noteId,
            mid: mid,
            tags: tags,
            fieldsJson: fieldsJson,
            sfld: sfld,
            guid: guid,
            mod: mod,
            rowid: rowid,
          ),
          withReferenceMapper: (p0) => p0
              .map((e) => (
                    e.readTable(table),
                    $$AnkiNotesTableReferences(db, table, e)
                  ))
              .toList(),
          prefetchHooksCallback: ({importId = false}) {
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
                if (importId) {
                  state = state.withJoin(
                    currentTable: table,
                    currentColumn: table.importId,
                    referencedTable:
                        $$AnkiNotesTableReferences._importIdTable(db),
                    referencedColumn:
                        $$AnkiNotesTableReferences._importIdTable(db).importId,
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

typedef $$AnkiNotesTableProcessedTableManager = ProcessedTableManager<
    _$CourseDatabase,
    $AnkiNotesTable,
    AnkiNoteRow,
    $$AnkiNotesTableFilterComposer,
    $$AnkiNotesTableOrderingComposer,
    $$AnkiNotesTableAnnotationComposer,
    $$AnkiNotesTableCreateCompanionBuilder,
    $$AnkiNotesTableUpdateCompanionBuilder,
    (AnkiNoteRow, $$AnkiNotesTableReferences),
    AnkiNoteRow,
    PrefetchHooks Function({bool importId})>;
typedef $$AnkiCardsMetaTableCreateCompanionBuilder = AnkiCardsMetaCompanion
    Function({
  required String importId,
  required int cardId,
  required int noteId,
  Value<int> ord,
  Value<int> did,
  required String wordId,
  Value<String> renderMode,
  Value<String> schedulingJson,
  Value<int> rowid,
});
typedef $$AnkiCardsMetaTableUpdateCompanionBuilder = AnkiCardsMetaCompanion
    Function({
  Value<String> importId,
  Value<int> cardId,
  Value<int> noteId,
  Value<int> ord,
  Value<int> did,
  Value<String> wordId,
  Value<String> renderMode,
  Value<String> schedulingJson,
  Value<int> rowid,
});

final class $$AnkiCardsMetaTableReferences extends BaseReferences<
    _$CourseDatabase, $AnkiCardsMetaTable, AnkiCardMetaRow> {
  $$AnkiCardsMetaTableReferences(
      super.$_db, super.$_table, super.$_typedResult);

  static $AnkiImportsTable _importIdTable(_$CourseDatabase db) =>
      db.ankiImports.createAlias($_aliasNameGenerator(
          db.ankiCardsMeta.importId, db.ankiImports.importId));

  $$AnkiImportsTableProcessedTableManager get importId {
    final $_column = $_itemColumn<String>('import_id')!;

    final manager = $$AnkiImportsTableTableManager($_db, $_db.ankiImports)
        .filter((f) => f.importId.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_importIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
        manager.$state.copyWith(prefetchedData: [item]));
  }
}

class $$AnkiCardsMetaTableFilterComposer
    extends Composer<_$CourseDatabase, $AnkiCardsMetaTable> {
  $$AnkiCardsMetaTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get cardId => $composableBuilder(
      column: $table.cardId, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get noteId => $composableBuilder(
      column: $table.noteId, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get ord => $composableBuilder(
      column: $table.ord, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get did => $composableBuilder(
      column: $table.did, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get wordId => $composableBuilder(
      column: $table.wordId, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get renderMode => $composableBuilder(
      column: $table.renderMode, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get schedulingJson => $composableBuilder(
      column: $table.schedulingJson,
      builder: (column) => ColumnFilters(column));

  $$AnkiImportsTableFilterComposer get importId {
    final $$AnkiImportsTableFilterComposer composer = $composerBuilder(
        composer: this,
        getCurrentColumn: (t) => t.importId,
        referencedTable: $db.ankiImports,
        getReferencedColumn: (t) => t.importId,
        builder: (joinBuilder,
                {$addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer}) =>
            $$AnkiImportsTableFilterComposer(
              $db: $db,
              $table: $db.ankiImports,
              $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
              joinBuilder: joinBuilder,
              $removeJoinBuilderFromRootComposer:
                  $removeJoinBuilderFromRootComposer,
            ));
    return composer;
  }
}

class $$AnkiCardsMetaTableOrderingComposer
    extends Composer<_$CourseDatabase, $AnkiCardsMetaTable> {
  $$AnkiCardsMetaTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get cardId => $composableBuilder(
      column: $table.cardId, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get noteId => $composableBuilder(
      column: $table.noteId, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get ord => $composableBuilder(
      column: $table.ord, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get did => $composableBuilder(
      column: $table.did, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get wordId => $composableBuilder(
      column: $table.wordId, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get renderMode => $composableBuilder(
      column: $table.renderMode, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get schedulingJson => $composableBuilder(
      column: $table.schedulingJson,
      builder: (column) => ColumnOrderings(column));

  $$AnkiImportsTableOrderingComposer get importId {
    final $$AnkiImportsTableOrderingComposer composer = $composerBuilder(
        composer: this,
        getCurrentColumn: (t) => t.importId,
        referencedTable: $db.ankiImports,
        getReferencedColumn: (t) => t.importId,
        builder: (joinBuilder,
                {$addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer}) =>
            $$AnkiImportsTableOrderingComposer(
              $db: $db,
              $table: $db.ankiImports,
              $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
              joinBuilder: joinBuilder,
              $removeJoinBuilderFromRootComposer:
                  $removeJoinBuilderFromRootComposer,
            ));
    return composer;
  }
}

class $$AnkiCardsMetaTableAnnotationComposer
    extends Composer<_$CourseDatabase, $AnkiCardsMetaTable> {
  $$AnkiCardsMetaTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get cardId =>
      $composableBuilder(column: $table.cardId, builder: (column) => column);

  GeneratedColumn<int> get noteId =>
      $composableBuilder(column: $table.noteId, builder: (column) => column);

  GeneratedColumn<int> get ord =>
      $composableBuilder(column: $table.ord, builder: (column) => column);

  GeneratedColumn<int> get did =>
      $composableBuilder(column: $table.did, builder: (column) => column);

  GeneratedColumn<String> get wordId =>
      $composableBuilder(column: $table.wordId, builder: (column) => column);

  GeneratedColumn<String> get renderMode => $composableBuilder(
      column: $table.renderMode, builder: (column) => column);

  GeneratedColumn<String> get schedulingJson => $composableBuilder(
      column: $table.schedulingJson, builder: (column) => column);

  $$AnkiImportsTableAnnotationComposer get importId {
    final $$AnkiImportsTableAnnotationComposer composer = $composerBuilder(
        composer: this,
        getCurrentColumn: (t) => t.importId,
        referencedTable: $db.ankiImports,
        getReferencedColumn: (t) => t.importId,
        builder: (joinBuilder,
                {$addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer}) =>
            $$AnkiImportsTableAnnotationComposer(
              $db: $db,
              $table: $db.ankiImports,
              $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
              joinBuilder: joinBuilder,
              $removeJoinBuilderFromRootComposer:
                  $removeJoinBuilderFromRootComposer,
            ));
    return composer;
  }
}

class $$AnkiCardsMetaTableTableManager extends RootTableManager<
    _$CourseDatabase,
    $AnkiCardsMetaTable,
    AnkiCardMetaRow,
    $$AnkiCardsMetaTableFilterComposer,
    $$AnkiCardsMetaTableOrderingComposer,
    $$AnkiCardsMetaTableAnnotationComposer,
    $$AnkiCardsMetaTableCreateCompanionBuilder,
    $$AnkiCardsMetaTableUpdateCompanionBuilder,
    (AnkiCardMetaRow, $$AnkiCardsMetaTableReferences),
    AnkiCardMetaRow,
    PrefetchHooks Function({bool importId})> {
  $$AnkiCardsMetaTableTableManager(
      _$CourseDatabase db, $AnkiCardsMetaTable table)
      : super(TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$AnkiCardsMetaTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$AnkiCardsMetaTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$AnkiCardsMetaTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback: ({
            Value<String> importId = const Value.absent(),
            Value<int> cardId = const Value.absent(),
            Value<int> noteId = const Value.absent(),
            Value<int> ord = const Value.absent(),
            Value<int> did = const Value.absent(),
            Value<String> wordId = const Value.absent(),
            Value<String> renderMode = const Value.absent(),
            Value<String> schedulingJson = const Value.absent(),
            Value<int> rowid = const Value.absent(),
          }) =>
              AnkiCardsMetaCompanion(
            importId: importId,
            cardId: cardId,
            noteId: noteId,
            ord: ord,
            did: did,
            wordId: wordId,
            renderMode: renderMode,
            schedulingJson: schedulingJson,
            rowid: rowid,
          ),
          createCompanionCallback: ({
            required String importId,
            required int cardId,
            required int noteId,
            Value<int> ord = const Value.absent(),
            Value<int> did = const Value.absent(),
            required String wordId,
            Value<String> renderMode = const Value.absent(),
            Value<String> schedulingJson = const Value.absent(),
            Value<int> rowid = const Value.absent(),
          }) =>
              AnkiCardsMetaCompanion.insert(
            importId: importId,
            cardId: cardId,
            noteId: noteId,
            ord: ord,
            did: did,
            wordId: wordId,
            renderMode: renderMode,
            schedulingJson: schedulingJson,
            rowid: rowid,
          ),
          withReferenceMapper: (p0) => p0
              .map((e) => (
                    e.readTable(table),
                    $$AnkiCardsMetaTableReferences(db, table, e)
                  ))
              .toList(),
          prefetchHooksCallback: ({importId = false}) {
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
                if (importId) {
                  state = state.withJoin(
                    currentTable: table,
                    currentColumn: table.importId,
                    referencedTable:
                        $$AnkiCardsMetaTableReferences._importIdTable(db),
                    referencedColumn: $$AnkiCardsMetaTableReferences
                        ._importIdTable(db)
                        .importId,
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

typedef $$AnkiCardsMetaTableProcessedTableManager = ProcessedTableManager<
    _$CourseDatabase,
    $AnkiCardsMetaTable,
    AnkiCardMetaRow,
    $$AnkiCardsMetaTableFilterComposer,
    $$AnkiCardsMetaTableOrderingComposer,
    $$AnkiCardsMetaTableAnnotationComposer,
    $$AnkiCardsMetaTableCreateCompanionBuilder,
    $$AnkiCardsMetaTableUpdateCompanionBuilder,
    (AnkiCardMetaRow, $$AnkiCardsMetaTableReferences),
    AnkiCardMetaRow,
    PrefetchHooks Function({bool importId})>;
typedef $$AnkiPrerenderedHtmlTableCreateCompanionBuilder
    = AnkiPrerenderedHtmlCompanion Function({
  required String wordId,
  Value<String?> frontHtml,
  Value<String?> backHtml,
  Value<int> capturedAt,
  Value<int> rowid,
});
typedef $$AnkiPrerenderedHtmlTableUpdateCompanionBuilder
    = AnkiPrerenderedHtmlCompanion Function({
  Value<String> wordId,
  Value<String?> frontHtml,
  Value<String?> backHtml,
  Value<int> capturedAt,
  Value<int> rowid,
});

class $$AnkiPrerenderedHtmlTableFilterComposer
    extends Composer<_$CourseDatabase, $AnkiPrerenderedHtmlTable> {
  $$AnkiPrerenderedHtmlTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get wordId => $composableBuilder(
      column: $table.wordId, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get frontHtml => $composableBuilder(
      column: $table.frontHtml, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get backHtml => $composableBuilder(
      column: $table.backHtml, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get capturedAt => $composableBuilder(
      column: $table.capturedAt, builder: (column) => ColumnFilters(column));
}

class $$AnkiPrerenderedHtmlTableOrderingComposer
    extends Composer<_$CourseDatabase, $AnkiPrerenderedHtmlTable> {
  $$AnkiPrerenderedHtmlTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get wordId => $composableBuilder(
      column: $table.wordId, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get frontHtml => $composableBuilder(
      column: $table.frontHtml, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get backHtml => $composableBuilder(
      column: $table.backHtml, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get capturedAt => $composableBuilder(
      column: $table.capturedAt, builder: (column) => ColumnOrderings(column));
}

class $$AnkiPrerenderedHtmlTableAnnotationComposer
    extends Composer<_$CourseDatabase, $AnkiPrerenderedHtmlTable> {
  $$AnkiPrerenderedHtmlTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get wordId =>
      $composableBuilder(column: $table.wordId, builder: (column) => column);

  GeneratedColumn<String> get frontHtml =>
      $composableBuilder(column: $table.frontHtml, builder: (column) => column);

  GeneratedColumn<String> get backHtml =>
      $composableBuilder(column: $table.backHtml, builder: (column) => column);

  GeneratedColumn<int> get capturedAt => $composableBuilder(
      column: $table.capturedAt, builder: (column) => column);
}

class $$AnkiPrerenderedHtmlTableTableManager extends RootTableManager<
    _$CourseDatabase,
    $AnkiPrerenderedHtmlTable,
    AnkiPrerenderedHtmlRow,
    $$AnkiPrerenderedHtmlTableFilterComposer,
    $$AnkiPrerenderedHtmlTableOrderingComposer,
    $$AnkiPrerenderedHtmlTableAnnotationComposer,
    $$AnkiPrerenderedHtmlTableCreateCompanionBuilder,
    $$AnkiPrerenderedHtmlTableUpdateCompanionBuilder,
    (
      AnkiPrerenderedHtmlRow,
      BaseReferences<_$CourseDatabase, $AnkiPrerenderedHtmlTable,
          AnkiPrerenderedHtmlRow>
    ),
    AnkiPrerenderedHtmlRow,
    PrefetchHooks Function()> {
  $$AnkiPrerenderedHtmlTableTableManager(
      _$CourseDatabase db, $AnkiPrerenderedHtmlTable table)
      : super(TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$AnkiPrerenderedHtmlTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$AnkiPrerenderedHtmlTableOrderingComposer(
                  $db: db, $table: table),
          createComputedFieldComposer: () =>
              $$AnkiPrerenderedHtmlTableAnnotationComposer(
                  $db: db, $table: table),
          updateCompanionCallback: ({
            Value<String> wordId = const Value.absent(),
            Value<String?> frontHtml = const Value.absent(),
            Value<String?> backHtml = const Value.absent(),
            Value<int> capturedAt = const Value.absent(),
            Value<int> rowid = const Value.absent(),
          }) =>
              AnkiPrerenderedHtmlCompanion(
            wordId: wordId,
            frontHtml: frontHtml,
            backHtml: backHtml,
            capturedAt: capturedAt,
            rowid: rowid,
          ),
          createCompanionCallback: ({
            required String wordId,
            Value<String?> frontHtml = const Value.absent(),
            Value<String?> backHtml = const Value.absent(),
            Value<int> capturedAt = const Value.absent(),
            Value<int> rowid = const Value.absent(),
          }) =>
              AnkiPrerenderedHtmlCompanion.insert(
            wordId: wordId,
            frontHtml: frontHtml,
            backHtml: backHtml,
            capturedAt: capturedAt,
            rowid: rowid,
          ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ));
}

typedef $$AnkiPrerenderedHtmlTableProcessedTableManager = ProcessedTableManager<
    _$CourseDatabase,
    $AnkiPrerenderedHtmlTable,
    AnkiPrerenderedHtmlRow,
    $$AnkiPrerenderedHtmlTableFilterComposer,
    $$AnkiPrerenderedHtmlTableOrderingComposer,
    $$AnkiPrerenderedHtmlTableAnnotationComposer,
    $$AnkiPrerenderedHtmlTableCreateCompanionBuilder,
    $$AnkiPrerenderedHtmlTableUpdateCompanionBuilder,
    (
      AnkiPrerenderedHtmlRow,
      BaseReferences<_$CourseDatabase, $AnkiPrerenderedHtmlTable,
          AnkiPrerenderedHtmlRow>
    ),
    AnkiPrerenderedHtmlRow,
    PrefetchHooks Function()>;
typedef $$SrsStatesTableCreateCompanionBuilder = SrsStatesCompanion Function({
  required String wordId,
  required String queue,
  required int dueAt,
  Value<int> intervalDays,
  Value<double> ease,
  Value<int> reps,
  Value<int> lapses,
  Value<bool> isLeech,
  Value<bool> isSuspended,
  Value<bool> isBuried,
  Value<String> type,
  Value<int?> lastReviewedAt,
  Value<double?> stability,
  Value<double?> difficulty,
  Value<int> fsrsState,
  Value<int?> learningStep,
  Value<String?> sourceKind,
  Value<String?> sourceId,
  Value<String?> ownerId,
  Value<int> rowid,
});
typedef $$SrsStatesTableUpdateCompanionBuilder = SrsStatesCompanion Function({
  Value<String> wordId,
  Value<String> queue,
  Value<int> dueAt,
  Value<int> intervalDays,
  Value<double> ease,
  Value<int> reps,
  Value<int> lapses,
  Value<bool> isLeech,
  Value<bool> isSuspended,
  Value<bool> isBuried,
  Value<String> type,
  Value<int?> lastReviewedAt,
  Value<double?> stability,
  Value<double?> difficulty,
  Value<int> fsrsState,
  Value<int?> learningStep,
  Value<String?> sourceKind,
  Value<String?> sourceId,
  Value<String?> ownerId,
  Value<int> rowid,
});

class $$SrsStatesTableFilterComposer
    extends Composer<_$CourseDatabase, $SrsStatesTable> {
  $$SrsStatesTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get wordId => $composableBuilder(
      column: $table.wordId, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get queue => $composableBuilder(
      column: $table.queue, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get dueAt => $composableBuilder(
      column: $table.dueAt, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get intervalDays => $composableBuilder(
      column: $table.intervalDays, builder: (column) => ColumnFilters(column));

  ColumnFilters<double> get ease => $composableBuilder(
      column: $table.ease, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get reps => $composableBuilder(
      column: $table.reps, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get lapses => $composableBuilder(
      column: $table.lapses, builder: (column) => ColumnFilters(column));

  ColumnFilters<bool> get isLeech => $composableBuilder(
      column: $table.isLeech, builder: (column) => ColumnFilters(column));

  ColumnFilters<bool> get isSuspended => $composableBuilder(
      column: $table.isSuspended, builder: (column) => ColumnFilters(column));

  ColumnFilters<bool> get isBuried => $composableBuilder(
      column: $table.isBuried, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get type => $composableBuilder(
      column: $table.type, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get lastReviewedAt => $composableBuilder(
      column: $table.lastReviewedAt,
      builder: (column) => ColumnFilters(column));

  ColumnFilters<double> get stability => $composableBuilder(
      column: $table.stability, builder: (column) => ColumnFilters(column));

  ColumnFilters<double> get difficulty => $composableBuilder(
      column: $table.difficulty, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get fsrsState => $composableBuilder(
      column: $table.fsrsState, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get learningStep => $composableBuilder(
      column: $table.learningStep, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get sourceKind => $composableBuilder(
      column: $table.sourceKind, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get sourceId => $composableBuilder(
      column: $table.sourceId, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get ownerId => $composableBuilder(
      column: $table.ownerId, builder: (column) => ColumnFilters(column));
}

class $$SrsStatesTableOrderingComposer
    extends Composer<_$CourseDatabase, $SrsStatesTable> {
  $$SrsStatesTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get wordId => $composableBuilder(
      column: $table.wordId, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get queue => $composableBuilder(
      column: $table.queue, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get dueAt => $composableBuilder(
      column: $table.dueAt, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get intervalDays => $composableBuilder(
      column: $table.intervalDays,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<double> get ease => $composableBuilder(
      column: $table.ease, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get reps => $composableBuilder(
      column: $table.reps, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get lapses => $composableBuilder(
      column: $table.lapses, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<bool> get isLeech => $composableBuilder(
      column: $table.isLeech, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<bool> get isSuspended => $composableBuilder(
      column: $table.isSuspended, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<bool> get isBuried => $composableBuilder(
      column: $table.isBuried, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get type => $composableBuilder(
      column: $table.type, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get lastReviewedAt => $composableBuilder(
      column: $table.lastReviewedAt,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<double> get stability => $composableBuilder(
      column: $table.stability, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<double> get difficulty => $composableBuilder(
      column: $table.difficulty, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get fsrsState => $composableBuilder(
      column: $table.fsrsState, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get learningStep => $composableBuilder(
      column: $table.learningStep,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get sourceKind => $composableBuilder(
      column: $table.sourceKind, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get sourceId => $composableBuilder(
      column: $table.sourceId, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get ownerId => $composableBuilder(
      column: $table.ownerId, builder: (column) => ColumnOrderings(column));
}

class $$SrsStatesTableAnnotationComposer
    extends Composer<_$CourseDatabase, $SrsStatesTable> {
  $$SrsStatesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get wordId =>
      $composableBuilder(column: $table.wordId, builder: (column) => column);

  GeneratedColumn<String> get queue =>
      $composableBuilder(column: $table.queue, builder: (column) => column);

  GeneratedColumn<int> get dueAt =>
      $composableBuilder(column: $table.dueAt, builder: (column) => column);

  GeneratedColumn<int> get intervalDays => $composableBuilder(
      column: $table.intervalDays, builder: (column) => column);

  GeneratedColumn<double> get ease =>
      $composableBuilder(column: $table.ease, builder: (column) => column);

  GeneratedColumn<int> get reps =>
      $composableBuilder(column: $table.reps, builder: (column) => column);

  GeneratedColumn<int> get lapses =>
      $composableBuilder(column: $table.lapses, builder: (column) => column);

  GeneratedColumn<bool> get isLeech =>
      $composableBuilder(column: $table.isLeech, builder: (column) => column);

  GeneratedColumn<bool> get isSuspended => $composableBuilder(
      column: $table.isSuspended, builder: (column) => column);

  GeneratedColumn<bool> get isBuried =>
      $composableBuilder(column: $table.isBuried, builder: (column) => column);

  GeneratedColumn<String> get type =>
      $composableBuilder(column: $table.type, builder: (column) => column);

  GeneratedColumn<int> get lastReviewedAt => $composableBuilder(
      column: $table.lastReviewedAt, builder: (column) => column);

  GeneratedColumn<double> get stability =>
      $composableBuilder(column: $table.stability, builder: (column) => column);

  GeneratedColumn<double> get difficulty => $composableBuilder(
      column: $table.difficulty, builder: (column) => column);

  GeneratedColumn<int> get fsrsState =>
      $composableBuilder(column: $table.fsrsState, builder: (column) => column);

  GeneratedColumn<int> get learningStep => $composableBuilder(
      column: $table.learningStep, builder: (column) => column);

  GeneratedColumn<String> get sourceKind => $composableBuilder(
      column: $table.sourceKind, builder: (column) => column);

  GeneratedColumn<String> get sourceId =>
      $composableBuilder(column: $table.sourceId, builder: (column) => column);

  GeneratedColumn<String> get ownerId =>
      $composableBuilder(column: $table.ownerId, builder: (column) => column);
}

class $$SrsStatesTableTableManager extends RootTableManager<
    _$CourseDatabase,
    $SrsStatesTable,
    SrsState,
    $$SrsStatesTableFilterComposer,
    $$SrsStatesTableOrderingComposer,
    $$SrsStatesTableAnnotationComposer,
    $$SrsStatesTableCreateCompanionBuilder,
    $$SrsStatesTableUpdateCompanionBuilder,
    (SrsState, BaseReferences<_$CourseDatabase, $SrsStatesTable, SrsState>),
    SrsState,
    PrefetchHooks Function()> {
  $$SrsStatesTableTableManager(_$CourseDatabase db, $SrsStatesTable table)
      : super(TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$SrsStatesTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$SrsStatesTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$SrsStatesTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback: ({
            Value<String> wordId = const Value.absent(),
            Value<String> queue = const Value.absent(),
            Value<int> dueAt = const Value.absent(),
            Value<int> intervalDays = const Value.absent(),
            Value<double> ease = const Value.absent(),
            Value<int> reps = const Value.absent(),
            Value<int> lapses = const Value.absent(),
            Value<bool> isLeech = const Value.absent(),
            Value<bool> isSuspended = const Value.absent(),
            Value<bool> isBuried = const Value.absent(),
            Value<String> type = const Value.absent(),
            Value<int?> lastReviewedAt = const Value.absent(),
            Value<double?> stability = const Value.absent(),
            Value<double?> difficulty = const Value.absent(),
            Value<int> fsrsState = const Value.absent(),
            Value<int?> learningStep = const Value.absent(),
            Value<String?> sourceKind = const Value.absent(),
            Value<String?> sourceId = const Value.absent(),
            Value<String?> ownerId = const Value.absent(),
            Value<int> rowid = const Value.absent(),
          }) =>
              SrsStatesCompanion(
            wordId: wordId,
            queue: queue,
            dueAt: dueAt,
            intervalDays: intervalDays,
            ease: ease,
            reps: reps,
            lapses: lapses,
            isLeech: isLeech,
            isSuspended: isSuspended,
            isBuried: isBuried,
            type: type,
            lastReviewedAt: lastReviewedAt,
            stability: stability,
            difficulty: difficulty,
            fsrsState: fsrsState,
            learningStep: learningStep,
            sourceKind: sourceKind,
            sourceId: sourceId,
            ownerId: ownerId,
            rowid: rowid,
          ),
          createCompanionCallback: ({
            required String wordId,
            required String queue,
            required int dueAt,
            Value<int> intervalDays = const Value.absent(),
            Value<double> ease = const Value.absent(),
            Value<int> reps = const Value.absent(),
            Value<int> lapses = const Value.absent(),
            Value<bool> isLeech = const Value.absent(),
            Value<bool> isSuspended = const Value.absent(),
            Value<bool> isBuried = const Value.absent(),
            Value<String> type = const Value.absent(),
            Value<int?> lastReviewedAt = const Value.absent(),
            Value<double?> stability = const Value.absent(),
            Value<double?> difficulty = const Value.absent(),
            Value<int> fsrsState = const Value.absent(),
            Value<int?> learningStep = const Value.absent(),
            Value<String?> sourceKind = const Value.absent(),
            Value<String?> sourceId = const Value.absent(),
            Value<String?> ownerId = const Value.absent(),
            Value<int> rowid = const Value.absent(),
          }) =>
              SrsStatesCompanion.insert(
            wordId: wordId,
            queue: queue,
            dueAt: dueAt,
            intervalDays: intervalDays,
            ease: ease,
            reps: reps,
            lapses: lapses,
            isLeech: isLeech,
            isSuspended: isSuspended,
            isBuried: isBuried,
            type: type,
            lastReviewedAt: lastReviewedAt,
            stability: stability,
            difficulty: difficulty,
            fsrsState: fsrsState,
            learningStep: learningStep,
            sourceKind: sourceKind,
            sourceId: sourceId,
            ownerId: ownerId,
            rowid: rowid,
          ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ));
}

typedef $$SrsStatesTableProcessedTableManager = ProcessedTableManager<
    _$CourseDatabase,
    $SrsStatesTable,
    SrsState,
    $$SrsStatesTableFilterComposer,
    $$SrsStatesTableOrderingComposer,
    $$SrsStatesTableAnnotationComposer,
    $$SrsStatesTableCreateCompanionBuilder,
    $$SrsStatesTableUpdateCompanionBuilder,
    (SrsState, BaseReferences<_$CourseDatabase, $SrsStatesTable, SrsState>),
    SrsState,
    PrefetchHooks Function()>;
typedef $$ReviewEventsTableCreateCompanionBuilder = ReviewEventsCompanion
    Function({
  Value<int> id,
  required String cardId,
  required String queue,
  required int reviewedAt,
  required int quality,
  required int prevIntervalDays,
  required int nextIntervalDays,
  required double prevEase,
  required double nextEase,
  required int reps,
  required int lapses,
  Value<String> type,
  Value<String?> sourceKey,
  Value<String?> sourceKind,
  Value<String?> sourceId,
  Value<String?> ownerId,
});
typedef $$ReviewEventsTableUpdateCompanionBuilder = ReviewEventsCompanion
    Function({
  Value<int> id,
  Value<String> cardId,
  Value<String> queue,
  Value<int> reviewedAt,
  Value<int> quality,
  Value<int> prevIntervalDays,
  Value<int> nextIntervalDays,
  Value<double> prevEase,
  Value<double> nextEase,
  Value<int> reps,
  Value<int> lapses,
  Value<String> type,
  Value<String?> sourceKey,
  Value<String?> sourceKind,
  Value<String?> sourceId,
  Value<String?> ownerId,
});

class $$ReviewEventsTableFilterComposer
    extends Composer<_$CourseDatabase, $ReviewEventsTable> {
  $$ReviewEventsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get id => $composableBuilder(
      column: $table.id, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get cardId => $composableBuilder(
      column: $table.cardId, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get queue => $composableBuilder(
      column: $table.queue, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get reviewedAt => $composableBuilder(
      column: $table.reviewedAt, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get quality => $composableBuilder(
      column: $table.quality, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get prevIntervalDays => $composableBuilder(
      column: $table.prevIntervalDays,
      builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get nextIntervalDays => $composableBuilder(
      column: $table.nextIntervalDays,
      builder: (column) => ColumnFilters(column));

  ColumnFilters<double> get prevEase => $composableBuilder(
      column: $table.prevEase, builder: (column) => ColumnFilters(column));

  ColumnFilters<double> get nextEase => $composableBuilder(
      column: $table.nextEase, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get reps => $composableBuilder(
      column: $table.reps, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get lapses => $composableBuilder(
      column: $table.lapses, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get type => $composableBuilder(
      column: $table.type, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get sourceKey => $composableBuilder(
      column: $table.sourceKey, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get sourceKind => $composableBuilder(
      column: $table.sourceKind, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get sourceId => $composableBuilder(
      column: $table.sourceId, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get ownerId => $composableBuilder(
      column: $table.ownerId, builder: (column) => ColumnFilters(column));
}

class $$ReviewEventsTableOrderingComposer
    extends Composer<_$CourseDatabase, $ReviewEventsTable> {
  $$ReviewEventsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get id => $composableBuilder(
      column: $table.id, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get cardId => $composableBuilder(
      column: $table.cardId, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get queue => $composableBuilder(
      column: $table.queue, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get reviewedAt => $composableBuilder(
      column: $table.reviewedAt, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get quality => $composableBuilder(
      column: $table.quality, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get prevIntervalDays => $composableBuilder(
      column: $table.prevIntervalDays,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get nextIntervalDays => $composableBuilder(
      column: $table.nextIntervalDays,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<double> get prevEase => $composableBuilder(
      column: $table.prevEase, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<double> get nextEase => $composableBuilder(
      column: $table.nextEase, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get reps => $composableBuilder(
      column: $table.reps, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get lapses => $composableBuilder(
      column: $table.lapses, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get type => $composableBuilder(
      column: $table.type, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get sourceKey => $composableBuilder(
      column: $table.sourceKey, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get sourceKind => $composableBuilder(
      column: $table.sourceKind, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get sourceId => $composableBuilder(
      column: $table.sourceId, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get ownerId => $composableBuilder(
      column: $table.ownerId, builder: (column) => ColumnOrderings(column));
}

class $$ReviewEventsTableAnnotationComposer
    extends Composer<_$CourseDatabase, $ReviewEventsTable> {
  $$ReviewEventsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get cardId =>
      $composableBuilder(column: $table.cardId, builder: (column) => column);

  GeneratedColumn<String> get queue =>
      $composableBuilder(column: $table.queue, builder: (column) => column);

  GeneratedColumn<int> get reviewedAt => $composableBuilder(
      column: $table.reviewedAt, builder: (column) => column);

  GeneratedColumn<int> get quality =>
      $composableBuilder(column: $table.quality, builder: (column) => column);

  GeneratedColumn<int> get prevIntervalDays => $composableBuilder(
      column: $table.prevIntervalDays, builder: (column) => column);

  GeneratedColumn<int> get nextIntervalDays => $composableBuilder(
      column: $table.nextIntervalDays, builder: (column) => column);

  GeneratedColumn<double> get prevEase =>
      $composableBuilder(column: $table.prevEase, builder: (column) => column);

  GeneratedColumn<double> get nextEase =>
      $composableBuilder(column: $table.nextEase, builder: (column) => column);

  GeneratedColumn<int> get reps =>
      $composableBuilder(column: $table.reps, builder: (column) => column);

  GeneratedColumn<int> get lapses =>
      $composableBuilder(column: $table.lapses, builder: (column) => column);

  GeneratedColumn<String> get type =>
      $composableBuilder(column: $table.type, builder: (column) => column);

  GeneratedColumn<String> get sourceKey =>
      $composableBuilder(column: $table.sourceKey, builder: (column) => column);

  GeneratedColumn<String> get sourceKind => $composableBuilder(
      column: $table.sourceKind, builder: (column) => column);

  GeneratedColumn<String> get sourceId =>
      $composableBuilder(column: $table.sourceId, builder: (column) => column);

  GeneratedColumn<String> get ownerId =>
      $composableBuilder(column: $table.ownerId, builder: (column) => column);
}

class $$ReviewEventsTableTableManager extends RootTableManager<
    _$CourseDatabase,
    $ReviewEventsTable,
    ReviewEvent,
    $$ReviewEventsTableFilterComposer,
    $$ReviewEventsTableOrderingComposer,
    $$ReviewEventsTableAnnotationComposer,
    $$ReviewEventsTableCreateCompanionBuilder,
    $$ReviewEventsTableUpdateCompanionBuilder,
    (
      ReviewEvent,
      BaseReferences<_$CourseDatabase, $ReviewEventsTable, ReviewEvent>
    ),
    ReviewEvent,
    PrefetchHooks Function()> {
  $$ReviewEventsTableTableManager(_$CourseDatabase db, $ReviewEventsTable table)
      : super(TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$ReviewEventsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$ReviewEventsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$ReviewEventsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback: ({
            Value<int> id = const Value.absent(),
            Value<String> cardId = const Value.absent(),
            Value<String> queue = const Value.absent(),
            Value<int> reviewedAt = const Value.absent(),
            Value<int> quality = const Value.absent(),
            Value<int> prevIntervalDays = const Value.absent(),
            Value<int> nextIntervalDays = const Value.absent(),
            Value<double> prevEase = const Value.absent(),
            Value<double> nextEase = const Value.absent(),
            Value<int> reps = const Value.absent(),
            Value<int> lapses = const Value.absent(),
            Value<String> type = const Value.absent(),
            Value<String?> sourceKey = const Value.absent(),
            Value<String?> sourceKind = const Value.absent(),
            Value<String?> sourceId = const Value.absent(),
            Value<String?> ownerId = const Value.absent(),
          }) =>
              ReviewEventsCompanion(
            id: id,
            cardId: cardId,
            queue: queue,
            reviewedAt: reviewedAt,
            quality: quality,
            prevIntervalDays: prevIntervalDays,
            nextIntervalDays: nextIntervalDays,
            prevEase: prevEase,
            nextEase: nextEase,
            reps: reps,
            lapses: lapses,
            type: type,
            sourceKey: sourceKey,
            sourceKind: sourceKind,
            sourceId: sourceId,
            ownerId: ownerId,
          ),
          createCompanionCallback: ({
            Value<int> id = const Value.absent(),
            required String cardId,
            required String queue,
            required int reviewedAt,
            required int quality,
            required int prevIntervalDays,
            required int nextIntervalDays,
            required double prevEase,
            required double nextEase,
            required int reps,
            required int lapses,
            Value<String> type = const Value.absent(),
            Value<String?> sourceKey = const Value.absent(),
            Value<String?> sourceKind = const Value.absent(),
            Value<String?> sourceId = const Value.absent(),
            Value<String?> ownerId = const Value.absent(),
          }) =>
              ReviewEventsCompanion.insert(
            id: id,
            cardId: cardId,
            queue: queue,
            reviewedAt: reviewedAt,
            quality: quality,
            prevIntervalDays: prevIntervalDays,
            nextIntervalDays: nextIntervalDays,
            prevEase: prevEase,
            nextEase: nextEase,
            reps: reps,
            lapses: lapses,
            type: type,
            sourceKey: sourceKey,
            sourceKind: sourceKind,
            sourceId: sourceId,
            ownerId: ownerId,
          ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ));
}

typedef $$ReviewEventsTableProcessedTableManager = ProcessedTableManager<
    _$CourseDatabase,
    $ReviewEventsTable,
    ReviewEvent,
    $$ReviewEventsTableFilterComposer,
    $$ReviewEventsTableOrderingComposer,
    $$ReviewEventsTableAnnotationComposer,
    $$ReviewEventsTableCreateCompanionBuilder,
    $$ReviewEventsTableUpdateCompanionBuilder,
    (
      ReviewEvent,
      BaseReferences<_$CourseDatabase, $ReviewEventsTable, ReviewEvent>
    ),
    ReviewEvent,
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
  $$AnkiImportsTableTableManager get ankiImports =>
      $$AnkiImportsTableTableManager(_db, _db.ankiImports);
  $$AnkiNotetypesTableTableManager get ankiNotetypes =>
      $$AnkiNotetypesTableTableManager(_db, _db.ankiNotetypes);
  $$AnkiNotesTableTableManager get ankiNotes =>
      $$AnkiNotesTableTableManager(_db, _db.ankiNotes);
  $$AnkiCardsMetaTableTableManager get ankiCardsMeta =>
      $$AnkiCardsMetaTableTableManager(_db, _db.ankiCardsMeta);
  $$AnkiPrerenderedHtmlTableTableManager get ankiPrerenderedHtml =>
      $$AnkiPrerenderedHtmlTableTableManager(_db, _db.ankiPrerenderedHtml);
  $$SrsStatesTableTableManager get srsStates =>
      $$SrsStatesTableTableManager(_db, _db.srsStates);
  $$ReviewEventsTableTableManager get reviewEvents =>
      $$ReviewEventsTableTableManager(_db, _db.reviewEvents);
}

import 'package:sqflite/sqflite.dart';
import 'package:mass_marsh_app/models/form_editor/custom_form_field.dart';
import 'package:mass_marsh_app/models/form/form_config.dart';
import 'dart:convert';

class CustomFormFieldDAO {
  final Database _db;

  CustomFormFieldDAO(this._db);

  Future<int> createCustomField(CustomFormField field) async {
    final json = field.toJson();
    json['validation_rules'] = field.validation != null
        ? jsonEncode(field.validation!.toJson())
        : null;
    json['options_json'] = field.options != null
        ? jsonEncode(field.options!.map((o) => o.toJson()).toList())
        : null;

    return _db.insert(
      'custom_form_fields',
      json,
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<CustomFormField?> getCustomFieldById(int id) async {
    final result = await _db.query(
      'custom_form_fields',
      where: 'id = ?',
      whereArgs: [id],
    );

    if (result.isEmpty) return null;
    return _fromDatabase(result.first);
  }

  Future<List<CustomFormField>> getCustomFieldsByForm(
    int orgId,
    String formName,
  ) async {
    final result = await _db.query(
      'custom_form_fields',
      where: 'org_id = ? AND form_name = ? AND is_active = 1',
      whereArgs: [orgId, formName],
      orderBy: 'order_index ASC, created_at ASC',
    );

    return result.map(_fromDatabase).toList();
  }

  Future<List<CustomFormField>> getAllCustomFieldsByOrg(int orgId) async {
    final result = await _db.query(
      'custom_form_fields',
      where: 'org_id = ? AND is_active = 1',
      whereArgs: [orgId],
      orderBy: 'form_name, order_index ASC',
    );

    return result.map(_fromDatabase).toList();
  }

  Future<int> updateCustomField(CustomFormField field) async {
    if (field.id == null) throw Exception('Cannot update field without ID');

    final json = field.toJson();
    json['validation_rules'] = field.validation != null
        ? jsonEncode(field.validation!.toJson())
        : null;
    json['options_json'] = field.options != null
        ? jsonEncode(field.options!.map((o) => o.toJson()).toList())
        : null;

    return _db.update(
      'custom_form_fields',
      json,
      where: 'id = ?',
      whereArgs: [field.id],
    );
  }

  Future<int> deleteCustomField(int id) async {
    return _db.delete(
      'custom_form_fields',
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<int> softDeleteCustomField(int id) async {
    return _db.update(
      'custom_form_fields',
      {'is_active': 0, 'updated_at': DateTime.now().toIso8601String()},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<void> reorderFields(int orgId, String formName, List<int> fieldIds) async {
    for (int i = 0; i < fieldIds.length; i++) {
      await _db.update(
        'custom_form_fields',
        {'order_index': i, 'updated_at': DateTime.now().toIso8601String()},
        where: 'id = ? AND org_id = ?',
        whereArgs: [fieldIds[i], orgId],
      );
    }
  }

  Future<int> getNextVersionNumber(int orgId, String formName) async {
    final result = await _db.rawQuery(
      'SELECT MAX(version_number) as max_version FROM form_versions WHERE org_id = ? AND form_name = ?',
      [orgId, formName],
    );

    final maxVersion = result.isNotEmpty ? result.first['max_version'] as int? : null;
    return (maxVersion ?? 0) + 1;
  }

  Future<int> publishFormVersion(FormVersion version) async {
    final json = version.toJson();
    json['published_at'] = version.publishedAt?.toIso8601String();
    json['created_at'] = version.createdAt?.toIso8601String();

    return _db.insert(
      'form_versions',
      json,
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<FormVersion?> getActiveFormVersion(int orgId, String formName) async {
    final result = await _db.query(
      'form_versions',
      where: 'org_id = ? AND form_name = ? AND is_active = 1',
      whereArgs: [orgId, formName],
      orderBy: 'version_number DESC',
      limit: 1,
    );

    if (result.isEmpty) return null;
    return _formVersionFromDatabase(result.first);
  }

  Future<List<FormVersion>> getFormVersionHistory(int orgId, String formName) async {
    final result = await _db.query(
      'form_versions',
      where: 'org_id = ? AND form_name = ?',
      whereArgs: [orgId, formName],
      orderBy: 'version_number DESC',
    );

    return result.map(_formVersionFromDatabase).toList();
  }

  CustomFormField _fromDatabase(Map<String, dynamic> map) {
    return CustomFormField(
      id: map['id'] as int?,
      orgId: map['org_id'] as int,
      formName: map['form_name'] as String,
      fieldId: map['field_id'] as String,
      fieldLabel: map['field_label'] as String,
      fieldType: map['field_type'] as String,
      required: (map['required'] as int?) == 1,
      validation: map['validation_rules'] != null
          ? ValidationRules.fromJson(jsonDecode(map['validation_rules'] as String))
          : null,
      options: map['options_json'] != null
          ? (jsonDecode(map['options_json'] as String) as List)
              .map((o) => DropdownOption.fromJson(o))
              .toList()
          : null,
      helpText: map['help_text'] as String?,
      orderIndex: map['order_index'] as int?,
      isActive: (map['is_active'] as int?) == 1,
      createdByUserId: map['created_by_user_id'] as int?,
      createdAt: map['created_at'] != null
          ? DateTime.parse(map['created_at'] as String)
          : null,
      updatedAt: map['updated_at'] != null
          ? DateTime.parse(map['updated_at'] as String)
          : null,
    );
  }

  FormVersion _formVersionFromDatabase(Map<String, dynamic> map) {
    return FormVersion(
      id: map['id'] as int?,
      orgId: map['org_id'] as int,
      formName: map['form_name'] as String,
      versionNumber: map['version_number'] as int,
      configHash: map['config_hash'] as String,
      publishedByUserId: map['published_by_user_id'] as int?,
      publishedAt: map['published_at'] != null
          ? DateTime.parse(map['published_at'] as String)
          : null,
      isActive: (map['is_active'] as int?) == 1,
      description: map['description'] as String?,
      createdAt: map['created_at'] != null
          ? DateTime.parse(map['created_at'] as String)
          : null,
    );
  }
}

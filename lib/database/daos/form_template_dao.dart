import 'dart:convert';
import 'package:sqflite/sqflite.dart';
import '../../models/form/form_template.dart';
import '../../models/form/org_form_template.dart';

/// Data Access Object for form templates and org-template associations
class FormTemplateDAO {
  final Database _db;

  FormTemplateDAO(this._db);

  // ============================================================================
  // FORM TEMPLATES
  // ============================================================================

  /// Get all active form templates
  Future<List<FormTemplate>> getAllTemplates() async {
    final rows = await _db.query(
      'form_templates',
      where: 'is_active = ?',
      whereArgs: [1],
    );
    return rows.map(_mapRowToFormTemplate).toList();
  }

  /// Get a template by its unique code
  Future<FormTemplate?> getTemplateByCode(String templateCode) async {
    final rows = await _db.query(
      'form_templates',
      where: 'template_code = ?',
      whereArgs: [templateCode],
    );
    if (rows.isEmpty) return null;
    return _mapRowToFormTemplate(rows.first);
  }

  /// Get a template by ID
  Future<FormTemplate?> getTemplateById(int id) async {
    final rows = await _db.query(
      'form_templates',
      where: 'id = ?',
      whereArgs: [id],
    );
    if (rows.isEmpty) return null;
    return _mapRowToFormTemplate(rows.first);
  }

  /// Insert a new form template
  Future<int> insertTemplate(FormTemplate template) async {
    return _db.insert(
      'form_templates',
      {
        'template_code': template.templateCode,
        'template_name': template.templateName,
        'description': template.description,
        'monitoring_type': template.monitoringType,
        'schema_json': jsonEncode(template.schema.toJson()),
        'is_active': template.isActive ? 1 : 0,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  /// Update an existing template
  Future<int> updateTemplate(FormTemplate template) async {
    return _db.update(
      'form_templates',
      {
        'template_name': template.templateName,
        'description': template.description,
        'monitoring_type': template.monitoringType,
        'schema_json': jsonEncode(template.schema.toJson()),
        'is_active': template.isActive ? 1 : 0,
      },
      where: 'id = ?',
      whereArgs: [template.id],
    );
  }

  /// Soft delete a template (set is_active = 0)
  Future<int> deactivateTemplate(int templateId) async {
    return _db.update(
      'form_templates',
      {'is_active': 0},
      where: 'id = ?',
      whereArgs: [templateId],
    );
  }

  // ============================================================================
  // ORG-TEMPLATE ASSOCIATIONS
  // ============================================================================

  /// Get all templates enabled for an organization (with template details)
  Future<List<OrgFormTemplate>> getTemplatesForOrg(int orgId) async {
    final rows = await _db.rawQuery('''
      SELECT
        oft.id, oft.org_id, oft.template_id, oft.customizations_json,
        oft.is_enabled, oft.enabled_at,
        ft.template_code, ft.template_name, ft.description,
        ft.monitoring_type, ft.schema_json, ft.is_active, ft.created_at
      FROM org_form_templates oft
      INNER JOIN form_templates ft ON oft.template_id = ft.id
      WHERE oft.org_id = ? AND oft.is_enabled = 1 AND ft.is_active = 1
      ORDER BY ft.template_name
    ''', [orgId]);

    return rows.map((row) {
      final template = _mapRowToFormTemplate({
        'id': row['template_id'],
        'template_code': row['template_code'],
        'template_name': row['template_name'],
        'description': row['description'],
        'monitoring_type': row['monitoring_type'],
        'schema_json': row['schema_json'],
        'is_active': row['is_active'],
        'created_at': row['created_at'],
      });

      return OrgFormTemplate(
        id: row['id'] as int?,
        orgId: row['org_id'] as int,
        templateId: row['template_id'] as int,
        customizations: row['customizations_json'] != null
            ? jsonDecode(row['customizations_json'] as String)
                as Map<String, dynamic>
            : null,
        isEnabled: (row['is_enabled'] as int) == 1,
        enabledAt: row['enabled_at'] != null
            ? DateTime.parse(row['enabled_at'] as String)
            : null,
        template: template,
      );
    }).toList();
  }

  /// Enable a template for an organization
  Future<int> enableTemplateForOrg(
    int orgId,
    int templateId, {
    Map<String, dynamic>? customizations,
  }) async {
    return _db.insert(
      'org_form_templates',
      {
        'org_id': orgId,
        'template_id': templateId,
        'customizations_json':
            customizations != null ? jsonEncode(customizations) : null,
        'is_enabled': 1,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  /// Disable a template for an organization
  Future<int> disableTemplateForOrg(int orgId, int templateId) async {
    return _db.update(
      'org_form_templates',
      {'is_enabled': 0},
      where: 'org_id = ? AND template_id = ?',
      whereArgs: [orgId, templateId],
    );
  }

  /// Update customizations for an org-template association
  Future<int> updateOrgTemplateCustomizations(
    int orgId,
    int templateId,
    Map<String, dynamic> customizations,
  ) async {
    return _db.update(
      'org_form_templates',
      {'customizations_json': jsonEncode(customizations)},
      where: 'org_id = ? AND template_id = ?',
      whereArgs: [orgId, templateId],
    );
  }

  /// Get a template with org customizations applied
  Future<FormTemplate?> getTemplateWithCustomizations(
    int orgId,
    int templateId,
  ) async {
    final rows = await _db.rawQuery('''
      SELECT
        ft.*, oft.customizations_json
      FROM form_templates ft
      LEFT JOIN org_form_templates oft
        ON ft.id = oft.template_id AND oft.org_id = ?
      WHERE ft.id = ?
    ''', [orgId, templateId]);

    if (rows.isEmpty) return null;

    final row = rows.first;
    final template = _mapRowToFormTemplate(row);

    // Apply customizations if present
    if (row['customizations_json'] != null) {
      final customizations =
          jsonDecode(row['customizations_json'] as String) as Map<String, dynamic>;
      return _applyCustomizations(template, customizations);
    }

    return template;
  }

  /// Check if a template is enabled for an organization
  Future<bool> isTemplateEnabledForOrg(int orgId, int templateId) async {
    final rows = await _db.query(
      'org_form_templates',
      where: 'org_id = ? AND template_id = ? AND is_enabled = 1',
      whereArgs: [orgId, templateId],
    );
    return rows.isNotEmpty;
  }

  // ============================================================================
  // HELPER METHODS
  // ============================================================================

  FormTemplate _mapRowToFormTemplate(Map<String, dynamic> row) {
    return FormTemplate(
      id: row['id'] as int?,
      templateCode: row['template_code'] as String,
      templateName: row['template_name'] as String,
      description: row['description'] as String?,
      monitoringType: row['monitoring_type'] as String,
      schema: FormSchema.fromJson(
        jsonDecode(row['schema_json'] as String) as Map<String, dynamic>,
      ),
      isActive: (row['is_active'] as int?) == 1,
      createdAt: row['created_at'] != null
          ? DateTime.parse(row['created_at'] as String)
          : null,
    );
  }

  /// Apply org-specific customizations to a template
  FormTemplate _applyCustomizations(
    FormTemplate template,
    Map<String, dynamic> customizations,
  ) {
    final hiddenFields =
        (customizations['hiddenFields'] as List<dynamic>?)?.cast<String>() ??
            [];
    final labelOverrides =
        (customizations['labelOverrides'] as Map<String, dynamic>?)
                ?.cast<String, String>() ??
            {};

    // Create modified sections with customizations applied
    final modifiedSections = template.schema.sections.map((section) {
      final modifiedFields = section.fields
          .where((field) => !hiddenFields.contains(field.id))
          .map((field) {
        if (labelOverrides.containsKey(field.id)) {
          return field.copyWith(label: labelOverrides[field.id]!);
        }
        return field;
      }).toList();

      return section.copyWith(fields: modifiedFields);
    }).toList();

    return template.copyWith(
      schema: template.schema.copyWith(sections: modifiedSections),
    );
  }
}

import 'dart:convert';
import 'package:sqflite/sqflite.dart';
import '../../models/form/form_config.dart';

/// Data Access Object for FormConfig operations.
///
/// Handles all database operations related to form configurations including
/// storing, retrieving, and validating form configs for different organizations.
class FormConfigDao {
  final Database _db;

  /// Creates a [FormConfigDao] with the given database instance.
  FormConfigDao(this._db);

  /// Saves or updates a form configuration for an organization.
  ///
  /// If a configuration already exists for the given [orgId], it will be updated.
  /// Otherwise, a new configuration will be inserted.
  ///
  /// Returns the ID of the inserted/updated configuration.
  Future<int> saveFormConfig(FormConfig config) async {
    final data = {
      'org_id': config.orgId,
      'config_version': config.configVersion,
      'config_hash': config.configHash,
      'common_form_json': jsonEncode(config.commonForm.toJson()),
      'vegetation_form_json': jsonEncode(config.vegetationForm.toJson()),
      'hydrology_form_json': jsonEncode(config.hydrologyForm.toJson()),
      'elevation_form_json': jsonEncode(config.elevationForm.toJson()),
      'downloaded_at': config.downloadedAt.toIso8601String(),
      'last_validated_at': config.lastValidatedAt?.toIso8601String(),
    };

    // Check if config exists for this org
    final existing = await getFormConfigByOrgId(config.orgId);

    if (existing != null) {
      // Update existing config
      await _db.update(
        'form_configs',
        data,
        where: 'org_id = ?',
        whereArgs: [config.orgId],
      );
      return existing.orgId;
    } else {
      // Insert new config
      return _db.insert(
        'form_configs',
        data,
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }
  }

  /// Retrieves the form configuration for a specific organization.
  ///
  /// Returns null if no configuration exists for the given [orgId].
  Future<FormConfig?> getFormConfigByOrgId(int orgId) async {
    final results = await _db.query(
      'form_configs',
      where: 'org_id = ?',
      whereArgs: [orgId],
      limit: 1,
    );

    if (results.isEmpty) {
      return null;
    }

    return _formConfigFromMap(results.first);
  }

  /// Retrieves all form configurations stored in the database.
  ///
  /// Returns an empty list if no configurations are stored.
  Future<List<FormConfig>> getAllFormConfigs() async {
    final results = await _db.query(
      'form_configs',
      orderBy: 'downloaded_at DESC',
    );

    return results.map(_formConfigFromMap).toList();
  }

  /// Deletes the form configuration for a specific organization.
  ///
  /// Returns the number of rows deleted (1 if successful, 0 if not found).
  Future<int> deleteFormConfig(int orgId) async {
    return _db.delete(
      'form_configs',
      where: 'org_id = ?',
      whereArgs: [orgId],
    );
  }

  /// Updates the last validated timestamp for a configuration.
  ///
  /// Used to track when the configuration was last validated against the server.
  Future<void> updateLastValidated(int orgId, DateTime validatedAt) async {
    await _db.update(
      'form_configs',
      {'last_validated_at': validatedAt.toIso8601String()},
      where: 'org_id = ?',
      whereArgs: [orgId],
    );
  }

  /// Checks if a configuration exists for the given organization.
  ///
  /// Returns true if a configuration exists, false otherwise.
  Future<bool> hasConfigForOrg(int orgId) async {
    final count = Sqflite.firstIntValue(
      await _db.rawQuery(
        'SELECT COUNT(*) FROM form_configs WHERE org_id = ?',
        [orgId],
      ),
    );
    return (count ?? 0) > 0;
  }

  /// Validates if the stored configuration matches the given hash.
  ///
  /// Used to check if the local configuration is up-to-date with the server.
  /// Returns true if the hashes match, false otherwise.
  Future<bool> validateConfigHash(int orgId, String expectedHash) async {
    final config = await getFormConfigByOrgId(orgId);
    return config?.configHash == expectedHash;
  }

  /// Gets the current version of the configuration for an organization.
  ///
  /// Returns null if no configuration exists for the given [orgId].
  Future<String?> getConfigVersion(int orgId) async {
    final results = await _db.query(
      'form_configs',
      columns: ['config_version'],
      where: 'org_id = ?',
      whereArgs: [orgId],
      limit: 1,
    );

    if (results.isEmpty) {
      return null;
    }

    return results.first['config_version'] as String?;
  }

  /// Converts a database map to a FormConfig object.
  ///
  /// Handles JSON deserialization of all form configuration components.
  FormConfig _formConfigFromMap(Map<String, dynamic> map) {
    return FormConfig(
      orgId: map['org_id'] as int,
      configVersion: map['config_version'] as String,
      configHash: map['config_hash'] as String,
      commonForm: CommonFormConfig.fromJson(
        jsonDecode(map['common_form_json'] as String) as Map<String, dynamic>,
      ),
      vegetationForm: VegetationFormConfig.fromJson(
        jsonDecode(map['vegetation_form_json'] as String)
            as Map<String, dynamic>,
      ),
      hydrologyForm: HydrologyFormConfig.fromJson(
        jsonDecode(map['hydrology_form_json'] as String)
            as Map<String, dynamic>,
      ),
      elevationForm: ElevationFormConfig.fromJson(
        jsonDecode(map['elevation_form_json'] as String)
            as Map<String, dynamic>,
      ),
      downloadedAt: DateTime.parse(map['downloaded_at'] as String),
      lastValidatedAt: map['last_validated_at'] != null
          ? DateTime.parse(map['last_validated_at'] as String)
          : null,
    );
  }
}

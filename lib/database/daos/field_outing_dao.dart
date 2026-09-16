import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';
import '../../models/field_outing/field_outing.dart';

/// Data Access Object for FieldOuting records
class FieldOutingDao {
  static const _uuid = Uuid();

  final Database db;

  FieldOutingDao(this.db);

  /// Create a new field outing (locally with local_id)
  /// Returns the local_id UUID for offline records
  Future<String> createFieldOuting(FieldOuting outing, {DatabaseExecutor? executor}) async {
    final localId = outing.localId ?? _generateUuid();

    await (executor ?? db).insert(
      'field_outings',
      {
        'local_id': localId,
        'org_id': outing.orgId,
        'created_by_user_id': outing.createdByUserId,
        'site_name': outing.siteName,
        'other_members': outing.otherMembers,
        'monitoring_type': outing.monitoringType,
        'start_time': outing.startTime?.toIso8601String(),
        'end_time': outing.endTime?.toIso8601String(),
        'latitude': outing.latitude,
        'longitude': outing.longitude,
        'visibility': outing.visibility,
        'embargo_until': outing.embargoUntil,
        'is_draft': outing.isDraft ? 1 : 0,
        'sync_status': 'pending',
        'approval_status': 'pending',
        'created_at': DateTime.now().toIso8601String(),
        'updated_at': DateTime.now().toIso8601String(),
      },
      conflictAlgorithm: ConflictAlgorithm.fail,
    );

    return localId;
  }

  /// Get field outing by local ID (for local records)
  Future<FieldOuting?> getByLocalId(String localId) async {
    final results = await db.query(
      'field_outings',
      where: 'local_id = ?',
      whereArgs: [localId],
    );

    if (results.isEmpty) return null;
    return _mapRowToFieldOuting(results.first);
  }

  /// Get field outing by server ID
  Future<FieldOuting?> getById(int id) async {
    final results = await db.query(
      'field_outings',
      where: 'id = ?',
      whereArgs: [id],
    );

    if (results.isEmpty) return null;
    return _mapRowToFieldOuting(results.first);
  }

  /// Get all field outings for an organization
  Future<List<FieldOuting>> getByOrgId(int orgId) async {
    final results = await db.query(
      'field_outings',
      where: 'org_id = ?',
      whereArgs: [orgId],
      orderBy: 'created_at DESC',
    );

    return results.map(_mapRowToFieldOuting).toList();
  }

  /// Get draft outings (not synced yet)
  Future<List<FieldOuting>> getDraftsByOrgId(int orgId) async {
    final results = await db.query(
      'field_outings',
      where: 'org_id = ? AND is_draft = 1',
      whereArgs: [orgId],
      orderBy: 'created_at DESC',
    );

    return results.map(_mapRowToFieldOuting).toList();
  }

  /// Get synced outings
  Future<List<FieldOuting>> getSyncedByOrgId(int orgId) async {
    final results = await db.query(
      'field_outings',
      where: 'org_id = ? AND is_draft = 0',
      whereArgs: [orgId],
      orderBy: 'created_at DESC',
    );

    return results.map(_mapRowToFieldOuting).toList();
  }

  /// Get outings by approval status
  Future<List<FieldOuting>> getByApprovalStatus(
    int orgId,
    String approvalStatus,
  ) async {
    final results = await db.query(
      'field_outings',
      where: 'org_id = ? AND approval_status = ?',
      whereArgs: [orgId, approvalStatus],
      orderBy: 'created_at DESC',
    );

    return results.map(_mapRowToFieldOuting).toList();
  }

  /// Update field outing (mark as submitted, update status, etc.)
  Future<void> updateFieldOuting(FieldOuting outing) async {
    final updates = <String, dynamic>{
      'monitoring_type': outing.monitoringType,
      'site_name': outing.siteName,
      'other_members': outing.otherMembers,
      'start_time': outing.startTime?.toIso8601String(),
      'end_time': outing.endTime?.toIso8601String(),
      'submission_time': outing.submissionTime?.toIso8601String(),
      'latitude': outing.latitude,
      'longitude': outing.longitude,
      'approval_status': outing.approvalStatus,
      'sync_status': outing.syncStatus,
      'is_draft': outing.isDraft ? 1 : 0,
      'updated_at': DateTime.now().toIso8601String(),
    };

    // Update by local_id if no server ID yet
    final whereClause = outing.id != null ? 'id = ?' : 'local_id = ?';
    final whereArgs = [outing.id ?? outing.localId];

    await db.update(
      'field_outings',
      updates,
      where: whereClause,
      whereArgs: whereArgs,
    );
  }

  /// Mark outing as synced (update with server ID)
  Future<void> markSynced(
    String localId, {
    required int serverId,
  }) async {
    await db.update(
      'field_outings',
      {
        'id': serverId,
        'sync_status': 'synced',
        'is_draft': 0,
        'updated_at': DateTime.now().toIso8601String(),
      },
      where: 'local_id = ?',
      whereArgs: [localId],
    );
  }

  /// Delete field outing (and cascade to all related records)
  Future<void> deleteFieldOuting(int id) async {
    await db.delete(
      'field_outings',
      where: 'id = ?',
      whereArgs: [id],
    );
    // Note: CASCADE delete will remove vegetation_records, hydrology_records, etc.
  }

  /// Get count of pending syncs
  Future<int> getPendingSyncCount(int orgId) async {
    final result = Sqflite.firstIntValue(
      await db.rawQuery(
        'SELECT COUNT(*) FROM field_outings WHERE org_id = ? AND sync_status = ?',
        [orgId, 'pending'],
      ),
    );
    return result ?? 0;
  }

  /// Get pending outings that need to sync
  Future<List<FieldOuting>> getPendingSyncs(int orgId) async {
    final results = await db.query(
      'field_outings',
      where: 'org_id = ? AND sync_status = ?',
      whereArgs: [orgId, 'pending'],
      orderBy: 'created_at ASC',
    );

    return results.map(_mapRowToFieldOuting).toList();
  }

  /// Helper: map database row to FieldOuting model
  FieldOuting _mapRowToFieldOuting(Map<String, dynamic> row) {
    return FieldOuting.fromMap(row);
  }

  String _generateUuid() => _uuid.v4();
}

import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sqflite/sqflite.dart';
import '../database/app_database.dart';
import '../models/field_outing/field_outing.dart';
import '../providers/auth_provider.dart';
import '../providers/org_provider.dart';
import '../services/app_logger.dart';
import '../services/sync_service.dart';

// Provide access to the database
final appDatabaseProvider = FutureProvider<AppDatabase>((ref) async {
  final db = AppDatabase.instance;
  await db.database; // Ensure it's initialized
  return db;
});

// Refresh trigger for sessions - using a simple counter that can be incremented
class _RefreshNotifier {
  int _counter = 0;

  int get value => _counter;

  void increment() {
    _counter++;
  }
}

final _refreshNotifier = _RefreshNotifier();

final fieldOutingRefreshProvider = FutureProvider<int>((ref) async {
  return _refreshNotifier.value;
});

// Count of vegetation records in one outing whose photo still needs uploading
final pendingPhotoUploadsCountProvider =
    FutureProvider.family<int, int>((ref, outingId) async {
  ref.watch(fieldOutingRefreshProvider);
  return SyncService.instance.getPendingPhotoUploadsCount(outingId: outingId);
});

// Get all field sessions for an organization
final fieldOutingsProvider = FutureProvider.family<List<FieldOuting>, int>((ref, orgId) async {
  // Watch refresh provider to trigger rebuilds
  ref.watch(fieldOutingRefreshProvider);

  final db = await ref.watch(appDatabaseProvider.future);
  return db.fieldOutingDao.getByOrgId(orgId);
});

// Get draft sessions
final draftOutingsProvider = FutureProvider.family<List<FieldOuting>, int>((ref, orgId) async {
  ref.watch(fieldOutingRefreshProvider);

  final db = await ref.watch(appDatabaseProvider.future);
  return db.fieldOutingDao.getDraftsByOrgId(orgId);
});

// Get synced sessions
final syncedOutingsProvider = FutureProvider.family<List<FieldOuting>, int>((ref, orgId) async {
  ref.watch(fieldOutingRefreshProvider);

  final db = await ref.watch(appDatabaseProvider.future);
  return db.fieldOutingDao.getSyncedByOrgId(orgId);
});

class FieldOutingService {
  final Ref ref;

  FieldOutingService(this.ref);

  /// Ensures the currently logged-in user exists in the local users table so
  /// that the created_by_user_id FK on field_outings is satisfied.
  // A real UPDATE, not INSERT OR REPLACE - REPLACE deletes+reinserts the row,
  // which violates the FK from field_outings.created_by_user_id once any
  // session already references this user
  Future<void> _upsertCurrentUser(Database database) async {
    final user = ref.read(authProvider).user;
    if (user == null) return;
    final values = {
      'email': user.email,
      'full_name': user.fullName,
      'is_active': user.isActive ? 1 : 0,
      'is_superadmin': user.isSuperadmin ? 1 : 0,
    };
    final updated = await database.update('users', values, where: 'id = ?', whereArgs: [user.id]);
    if (updated == 0) {
      await database.insert('users', {'id': user.id, ...values});
    }
  }

  Future<String> saveFieldOuting(FieldOuting session) async {
    final db = await ref.read(appDatabaseProvider.future);
    final database = await db.database;
    await _upsertCurrentUser(database);
    final localId = await db.fieldOutingDao.createFieldOuting(session);

    // Trigger a refresh
    _refreshNotifier.increment();

    // Trigger background sync (don't await - let it happen in background)
    // Get the database ID for the just-created session
    final result = await database.query(
      'field_outings',
      columns: ['id'],
      where: 'local_id = ?',
      whereArgs: [localId],
      limit: 1,
    );

    if (result.isNotEmpty && !session.isDraft) {
      final dbId = result.first['id'] as int;
      unawaited(SyncService.instance.uploadFieldOuting(dbId).then((serverId) {
        if (serverId != null) {
          // Refresh again to show sync status
          _refreshNotifier.increment();
        }
      }).catchError((error) {
        // Sync failed - record will stay as pending and retry later
      }));
    }

    return localId;
  }

  Future<String> saveFieldOutingWithChildren(
    FieldOuting session,
    List<Map<String, dynamic>> childRecords,
    String childTable,
  ) async {
    final db = await ref.read(appDatabaseProvider.future);
    final database = await db.database;
    await _upsertCurrentUser(database);

    // The outing row and its children must become visible together, not one
    // at a time, or a concurrent sync (connectivity change, background task)
    // can upload the outing before its plots exist and mark it synced anyway
    String localId = '';
    int? dbId;
    await database.transaction((txn) async {
      localId = await db.fieldOutingDao.createFieldOuting(session, executor: txn);
      final result = await txn.query(
        'field_outings',
        columns: ['id'],
        where: 'local_id = ?',
        whereArgs: [localId],
        limit: 1,
      );
      if (result.isEmpty) return;
      dbId = result.first['id'] as int;
      for (final record in childRecords) {
        await txn.insert(childTable, {...record, 'outing_id': dbId});
      }
    });

    _refreshNotifier.increment();

    if (dbId != null && !session.isDraft) {
      unawaited(SyncService.instance.uploadFieldOuting(dbId!).then((serverId) {
        if (serverId != null) {
          _refreshNotifier.increment();
        }
      }).catchError((_) {}));
    }

    return localId;
  }

  /// Looks up the local database id of an outing by its local_id.
  Future<int?> getDbIdByLocalId(String localId) async {
    final db = await ref.read(appDatabaseProvider.future);
    final database = await db.database;
    final result = await database.query(
      'field_outings',
      columns: ['id'],
      where: 'local_id = ?',
      whereArgs: [localId],
      limit: 1,
    );
    if (result.isEmpty) return null;
    return result.first['id'] as int?;
  }

  // Matches child rows on local_id rather than delete-then-reinsert, which
  // would wipe server_id and orphan anything already uploaded.
  // isDraft: false finalizes the draft in place - used when ending a
  // session, replacing what used to be a separate deleteDraft() followed by
  // a fresh insert, which could lose the draft entirely with nothing to
  // replace it if the process died between those two steps.
  Future<void> updateDraftWithChildren(
    int draftId,
    FieldOuting session,
    List<Map<String, dynamic>> childRecords,
    String childTable, {
    bool isDraft = true,
  }) async {
    final db = await ref.read(appDatabaseProvider.future);
    final database = await db.database;

    await database.transaction((txn) async {
      await txn.update(
        'field_outings',
        {
          'site_name': session.siteName,
          'other_members': session.otherMembers,
          'start_time': session.startTime?.toIso8601String(),
          'end_time': session.endTime?.toIso8601String(),
          'visibility': session.visibility,
          'embargo_until': session.embargoUntil,
          'is_draft': isDraft ? 1 : 0,
          'updated_at': DateTime.now().toIso8601String(),
        },
        where: 'id = ?',
        whereArgs: [draftId],
      );

      final keptLocalIds = <String>[];
      for (final record in childRecords) {
        final row = {...record, 'outing_id': draftId};
        final localId = row['local_id'] as String?;

        if (localId == null || localId.isEmpty) {
          await txn.insert(childTable, row);
          continue;
        }

        keptLocalIds.add(localId);
        final updates = Map<String, dynamic>.from(row)..remove('created_at');
        final updated = await txn.update(
          childTable,
          updates,
          where: 'local_id = ?',
          whereArgs: [localId],
        );
        if (updated == 0) {
          await txn.insert(childTable, row);
        }
      }

      // Rows the user removed from the form, but never one already on the server
      final placeholders = List.filled(keptLocalIds.length, '?').join(',');
      await txn.delete(
        childTable,
        where: keptLocalIds.isEmpty
            ? 'outing_id = ? AND server_id IS NULL'
            : 'outing_id = ? AND server_id IS NULL AND '
                '(local_id IS NULL OR local_id NOT IN ($placeholders))',
        whereArgs: [draftId, ...keptLocalIds],
      );
    });

    _refreshNotifier.increment();

    if (!isDraft) {
      unawaited(SyncService.instance.uploadFieldOuting(draftId).then((serverId) {
        if (serverId != null) {
          _refreshNotifier.increment();
        }
      }).catchError((_) {}));
    }
  }

  Future<void> updateFieldOuting(FieldOuting session) async {
    final db = await ref.read(appDatabaseProvider.future);
    await db.fieldOutingDao.updateFieldOuting(session);
    // Trigger a refresh
    _refreshNotifier.increment();
  }

  Future<void> deleteFieldOuting(int id) async {
    final db = await ref.read(appDatabaseProvider.future);
    await db.fieldOutingDao.deleteFieldOuting(id);
    // Trigger a refresh
    _refreshNotifier.increment();
  }

  Future<List<FieldOuting>> getDrafts() async {
    final db = await ref.read(appDatabaseProvider.future);
    final database = await db.database;
    final userId = ref.read(authProvider).user?.id;
    final orgId = ref.read(selectedOrgProvider)?.id;

    // Scoped to the same org and account combination the sessions list uses,
    // so a shared device never shows one crew another crew's drafts
    final conditions = <String>['is_draft = ?'];
    final args = <Object?>[1];
    if (userId != null) {
      conditions.add('created_by_user_id = ?');
      args.add(userId);
    }
    if (orgId != null) {
      conditions.add('org_id = ?');
      args.add(orgId);
    }

    final result = await database.query(
      'field_outings',
      where: conditions.join(' AND '),
      whereArgs: args,
      orderBy: 'updated_at DESC',
    );

    appLogger.i('[drafts] query: userId=$userId orgId=$orgId -> ${result.length} row(s)');
    return result.map(FieldOuting.fromMap).toList();
  }

  // Same org/account scoping as getDrafts(), plus monitoring type, so
  // tapping a monitoring card can offer to resume the relevant draft only
  Future<List<FieldOuting>> getDraftsByType(String monitoringType) async {
    final drafts = await getDrafts();
    return drafts.where((d) => d.monitoringType == monitoringType).toList();
  }

  Future<void> deleteDraft(int id) async {
    final db = await ref.read(appDatabaseProvider.future);
    final database = await db.database;

    // One transaction so an interruption partway through can't leave
    // orphaned child rows behind after only some deletes committed
    await database.transaction((txn) async {
      await txn.delete('vegetation_records', where: 'outing_id = ?', whereArgs: [id]);
      await txn.delete('hydrology_records', where: 'outing_id = ?', whereArgs: [id]);
      await txn.delete('elevation_records', where: 'outing_id = ?', whereArgs: [id]);
      await txn.delete('field_outings', where: 'id = ?', whereArgs: [id]);
    });

    _refreshNotifier.increment();
  }

  Future<FieldOuting?> getDraftById(int id) async {
    final db = await ref.read(appDatabaseProvider.future);
    final database = await db.database;
    
    final result = await database.query(
      'field_outings',
      where: 'id = ? AND is_draft = ?',
      whereArgs: [id, 1],
      limit: 1,
    );

    if (result.isEmpty) return null;
    return FieldOuting.fromMap(result.first);
  }
}

final fieldOutingServiceProvider = Provider((ref) {
  return FieldOutingService(ref);
});

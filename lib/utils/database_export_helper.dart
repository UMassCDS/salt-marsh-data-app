import 'dart:convert';
import 'dart:io';

import 'package:archive/archive_io.dart';
import 'package:file_picker/file_picker.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';

import '../database/app_database.dart';
import '../services/app_logger.dart';
import '../services/sync_log.dart';

class OutingSummary {
  final int? id;
  final String? localId;
  final int orgId;
  final int? createdByUserId;
  final String siteName;
  final String monitoringType;
  final bool isDraft;
  final String? syncStatus;
  final String? createdAt;
  final int recordCount;

  const OutingSummary({
    required this.id,
    required this.localId,
    required this.orgId,
    required this.createdByUserId,
    required this.siteName,
    required this.monitoringType,
    required this.isDraft,
    required this.syncStatus,
    required this.createdAt,
    required this.recordCount,
  });
}

class RecoverySummary {
  final Map<String, int> tableCounts;
  final List<OutingSummary> outings;
  final int photoFileCount;
  final int photoReferencedCount;
  final int photoOrphanCount;
  final int photoBytes;

  const RecoverySummary({
    required this.tableCounts,
    required this.outings,
    required this.photoFileCount,
    required this.photoReferencedCount,
    required this.photoOrphanCount,
    required this.photoBytes,
  });

  int get draftCount => outings.where((o) => o.isDraft).length;

  int get totalRecordCount => outings.fold(0, (sum, o) => sum + o.recordCount);
}

class DatabaseExportHelper {
  static Future<Directory> _photosDirectory() async {
    final docsDir = await getApplicationDocumentsDirectory();
    return Directory(p.join(docsDir.path, 'photos'));
  }

  // Best-effort per table: a recovery export must still run against a database
  // that is missing or has corrupted one of them
  static Future<Map<String, int>> _tableCounts(Database db) async {
    const tables = [
      'users',
      'organizations',
      'field_outings',
      'vegetation_records',
      'hydrology_records',
      'elevation_records',
      'sync_queue',
      'pending_uploads',
    ];

    final counts = <String, int>{};
    for (final table in tables) {
      try {
        counts[table] = Sqflite.firstIntValue(
              await db.rawQuery('SELECT COUNT(*) FROM $table'),
            ) ??
            0;
      } catch (_) {
        counts[table] = -1;
      }
    }
    return counts;
  }

  // Deliberately unscoped by user and org, unlike every other query in the app
  static Future<RecoverySummary> inspect() async {
    final db = await AppDatabase.instance.database;
    final tableCounts = await _tableCounts(db);

    final rows = await db.rawQuery('''
      SELECT o.id, o.local_id, o.org_id, o.created_by_user_id, o.site_name,
             o.monitoring_type, o.is_draft, o.sync_status, o.created_at,
             (SELECT COUNT(*) FROM vegetation_records v WHERE v.outing_id = o.id) AS veg,
             (SELECT COUNT(*) FROM hydrology_records h WHERE h.outing_id = o.id) AS hyd,
             (SELECT COUNT(*) FROM elevation_records e WHERE e.outing_id = o.id) AS elev
      FROM field_outings o
      ORDER BY o.created_at DESC
    ''');

    final outings = rows.map((row) {
      final recordCount = const ['veg', 'hyd', 'elev']
          .map((key) => (row[key] as int?) ?? 0)
          .fold(0, (a, b) => a + b);
      return OutingSummary(
        id: row['id'] as int?,
        localId: row['local_id'] as String?,
        orgId: (row['org_id'] as int?) ?? 0,
        createdByUserId: row['created_by_user_id'] as int?,
        siteName: (row['site_name'] as String?) ?? '',
        monitoringType: (row['monitoring_type'] as String?) ?? '',
        isDraft: (row['is_draft'] as int?) == 1,
        syncStatus: row['sync_status'] as String?,
        createdAt: row['created_at'] as String?,
        recordCount: recordCount,
      );
    }).toList();

    final referenced = <String>{};
    final photoRows = await db.query(
      'vegetation_records',
      columns: ['photo_local_path'],
      where: 'photo_local_path IS NOT NULL',
    );
    for (final row in photoRows) {
      final path = row['photo_local_path'] as String?;
      if (path != null && path.isNotEmpty) referenced.add(p.basename(path));
    }

    var fileCount = 0;
    var orphanCount = 0;
    var bytes = 0;
    final photosDir = await _photosDirectory();
    if (await photosDir.exists()) {
      await for (final entity in photosDir.list()) {
        if (entity is! File) continue;
        fileCount++;
        bytes += await entity.length();
        if (!referenced.contains(p.basename(entity.path))) orphanCount++;
      }
    }

    return RecoverySummary(
      tableCounts: tableCounts,
      outings: outings,
      photoFileCount: fileCount,
      photoReferencedCount: referenced.length,
      photoOrphanCount: orphanCount,
      photoBytes: bytes,
    );
  }

  static String buildReport(RecoverySummary summary) {
    final buffer = StringBuffer()
      ..writeln('Salt Marsh Data - recovery export')
      ..writeln('Generated: ${DateTime.now().toIso8601String()}')
      ..writeln()
      ..writeln('TABLE COUNTS');
    for (final entry in summary.tableCounts.entries) {
      buffer.writeln('  ${entry.key}: ${entry.value}');
    }

    buffer
      ..writeln()
      ..writeln('PHOTOS')
      ..writeln('  files on disk: ${summary.photoFileCount}')
      ..writeln('  referenced by a record: ${summary.photoReferencedCount}')
      ..writeln('  orphaned (no record): ${summary.photoOrphanCount}')
      ..writeln('  total size: '
          '${(summary.photoBytes / (1024 * 1024)).toStringAsFixed(1)} MB')
      ..writeln()
      ..writeln('SESSIONS (every account, every org)')
      ..writeln('  ${summary.outings.length} total, '
          '${summary.draftCount} draft(s), '
          '${summary.totalRecordCount} child record(s)')
      ..writeln();

    for (final outing in summary.outings) {
      buffer.writeln(
        '  id=${outing.id} local=${outing.localId} org=${outing.orgId} '
        'user=${outing.createdByUserId} '
        '${outing.isDraft ? 'DRAFT' : outing.syncStatus ?? 'unknown'} '
        '${outing.monitoringType} records=${outing.recordCount} '
        'created=${outing.createdAt} site="${outing.siteName}"',
      );
    }

    return buffer.toString();
  }

  // "ALL" rather than a date, so scope is never left to be inferred
  static String scopeLabel(DateTime? day) {
    if (day == null) return 'ALL';
    final y = day.year.toString().padLeft(4, '0');
    final m = day.month.toString().padLeft(2, '0');
    final d = day.day.toString().padLeft(2, '0');
    return '$y-$m-$d';
  }

  // Time only, not a date, so "for X at Y" never reads as two dates
  static String _exportedAtLabel() {
    final now = DateTime.now();
    String two(int n) => n.toString().padLeft(2, '0');
    return '${two(now.hour)}${two(now.minute)}${two(now.second)}';
  }

  // Never bundles photos - those upload separately in batches, since one
  // large request is what the server was cutting off
  static Future<File> buildBundle(RecoverySummary summary, String scope) async {
    final docsDir = await getApplicationDocumentsDirectory();

    final stagingDir = Directory(p.join(docsDir.path, 'recovery_staging'));
    if (await stagingDir.exists()) await stagingDir.delete(recursive: true);
    await stagingDir.create(recursive: true);

    try {
      await _copyDatabaseInto(stagingDir);

      final reportFile = File(p.join(stagingDir.path, 'summary.txt'));
      await reportFile.writeAsString(buildReport(summary));

      final logFile = File(p.join(stagingDir.path, 'recent_log.txt'));
      await logFile.writeAsString(dumpRecentLogs());

      final syncLogFile = File(p.join(stagingDir.path, 'sync_log.txt'));
      await syncLogFile.writeAsString(await SyncLog.persistent.dump());

      final zipPath = p.join(
          docsDir.path,
          'saltmarsh-database-for-$scope-at-${_exportedAtLabel()}.zip');
      final zipFile = File(zipPath);
      if (await zipFile.exists()) await zipFile.delete();

      final encoder = ZipFileEncoder();
      encoder.create(zipPath);
      try {
        await for (final entity in stagingDir.list()) {
          if (entity is File) {
            await encoder.addFile(entity, p.basename(entity.path));
          }
        }
      } finally {
        await encoder.close();
      }

      return zipFile;
    } finally {
      if (await stagingDir.exists()) {
        await stagingDir.delete(recursive: true);
      }
    }
  }

  static Future<void> _copyDatabaseInto(Directory destination) async {
    final dbPath = await AppDatabase.instance.getDatabasePath();
    // Closing checkpoints the WAL, so the copy is not missing recent commits
    await AppDatabase.instance.close();
    try {
      final target = p.join(destination.path, p.basename(dbPath));
      await File(dbPath).copy(target);
      for (final suffix in const ['-wal', '-shm']) {
        final sidecar = File('$dbPath$suffix');
        if (await sidecar.exists()) await sidecar.copy('$target$suffix');
      }
    } finally {
      await AppDatabase.instance.database;
    }
  }

  // Photos are named <epochMillis>.<ext> at capture time. Falls back to the
  // file's own timestamp so a photo saved under any other naming scheme still
  // lands on a date, rather than silently vanishing from every day filter.
  static Future<DateTime> photoTakenAt(File file) async {
    final millis = int.tryParse(p.basenameWithoutExtension(file.path));
    if (millis != null) return DateTime.fromMillisecondsSinceEpoch(millis);
    return file.lastModified();
  }

  static Future<List<File>> allPhotos() async {
    final dir = await _photosDirectory();
    if (!await dir.exists()) return [];

    final files = <File>[];
    await for (final entity in dir.list()) {
      if (entity is File) files.add(entity);
    }
    return files;
  }

  /// Photos on the device, newest first. Pass [day] to limit to one date.
  static Future<List<File>> photosForDay(DateTime? day) async {
    final files = await allPhotos();

    final takenAt = <String, DateTime>{};
    for (final f in files) {
      takenAt[f.path] = await photoTakenAt(f);
    }

    final filtered = day == null
        ? files
        : files.where((f) {
            final taken = takenAt[f.path]!;
            return taken.year == day.year &&
                taken.month == day.month &&
                taken.day == day.day;
          }).toList();

    // Path as tiebreak so an interrupted run re-batches identically on resume
    filtered.sort((a, b) {
      final byTime = takenAt[b.path]!.compareTo(takenAt[a.path]!);
      return byTime != 0 ? byTime : a.path.compareTo(b.path);
    });
    return filtered;
  }

  static Future<File> _runStateFile() async {
    final docs = await getApplicationDocumentsDirectory();
    return File(p.join(docs.path, 'photo_upload_run.json'));
  }

  // Cleared once a run completes, so the next upload sends everything again
  static Future<Set<String>> resumableFor(String scope) async {
    final file = await _runStateFile();
    if (!await file.exists()) return {};
    try {
      final decoded =
          jsonDecode(await file.readAsString()) as Map<String, dynamic>;
      if (decoded['scope'] != scope) return {};
      return (decoded['sent'] as List<dynamic>)
          .map((e) => e.toString())
          .toSet();
    } catch (_) {
      return {};
    }
  }

  static Future<void> recordRunProgress(
    String scope,
    Iterable<String> names,
  ) async {
    final file = await _runStateFile();
    final sent = await resumableFor(scope)
      ..addAll(names);
    await file.writeAsString(
        jsonEncode({'scope': scope, 'sent': sent.toList()}));
  }

  static Future<void> clearRunState() async {
    final file = await _runStateFile();
    if (await file.exists()) await file.delete();
  }

  static Future<List<List<File>>> batchBySize(
    List<File> files,
    int maxBytes,
  ) async {
    final batches = <List<File>>[];
    var current = <File>[];
    var size = 0;

    for (final file in files) {
      final length = await file.length();
      if (current.isNotEmpty && size + length > maxBytes) {
        batches.add(current);
        current = [];
        size = 0;
      }
      current.add(file);
      size += length;
    }
    if (current.isNotEmpty) batches.add(current);

    return batches;
  }

  // One batch at a time: zipping everything up front would need a second
  // copy of every photo, on a tablet that may not have the space
  static Future<File> buildPhotoBatch(
    List<File> photos,
    String scope,
    int index,
    int total,
  ) async {
    final docs = await getApplicationDocumentsDirectory();
    final path = p.join(
        docs.path, 'saltmarsh-photos-$scope-${index}of$total.zip');
    final existing = File(path);
    if (await existing.exists()) await existing.delete();

    final encoder = ZipFileEncoder();
    // Stored, not deflated: JPEGs do not compress, so it would burn battery
    encoder.create(path, level: ZipFileEncoder.store);
    try {
      for (final photo in photos) {
        await encoder.addFile(photo, p.basename(photo.path));
      }
    } finally {
      await encoder.close();
    }

    return File(path);
  }

  /// Replaces the current database. Caller must confirm with the user first.
  static Future<void> importDatabase() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['db'],
      dialogTitle: 'Select Salt Marsh Data database file',
    );

    final path = result?.files.single.path;
    if (path == null) throw Exception('No file selected');

    await AppDatabase.instance.importDatabase(path);
  }
}

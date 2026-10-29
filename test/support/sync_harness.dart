import 'dart:convert';
import 'dart:io';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mass_marsh_app/database/app_database.dart';
import 'package:mass_marsh_app/services/sync_log.dart';
import 'package:mass_marsh_app/services/sync_service.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:sqflite/sqflite.dart' show Sqflite;
import 'fake_backend.dart';
import 'fake_connectivity.dart';

void useInMemorySqlite() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;
}

class SyncHarness {
  final AppDatabase appDb;
  final FakeBackend backend;
  final FakeConnectivity connectivity;
  final SyncService sync;

  SyncHarness._(this.appDb, this.backend, this.connectivity, this.sync);

  static Future<SyncHarness> create({List<Fault> faults = const [], SyncLog? syncLog}) async {
    final appDb = AppDatabase.forTesting(path: inMemoryDatabasePath);
    await appDb.database;
    final backend = FakeBackend(faults: faults);
    final connectivity = FakeConnectivity();
    final dio = Dio()..httpClientAdapter = backend;
    final sync = SyncService.forTesting(dio: dio, db: appDb, connectivity: connectivity, syncLog: syncLog);
    return SyncHarness._(appDb, backend, connectivity, sync);
  }

  Future<Database> get db => appDb.database;

  Future<void> dispose() => appDb.close();

  Future<int> insertOuting({
    required String localId,
    int plots = 2,
    int orgId = 1,
    String? photoPathForFirstPlot,
  }) async {
    final database = await db;
    final outingId = await database.insert('field_outings', {
      'local_id': localId,
      'org_id': orgId,
      'site_name': 'Plum Island',
      'monitoring_type': 'vegetation',
      'start_time': '2026-07-01T09:00:00',
      'sync_status': 'pending',
      'is_draft': 0,
    });
    for (var plot = 1; plot <= plots; plot++) {
      await database.insert('vegetation_records', {
        'local_id': '$localId-veg-$plot',
        'outing_id': outingId,
        'transect_id': 'T1',
        'plot_number': plot,
        'latitude': 42.0,
        'longitude': -71.0,
        'species_observations': jsonEncode([
          {'species_code': 'SPAL', 'percentage_cover': 60.0},
        ]),
        'protocol_code': 'MassMarshVeg',
        if (plot == 1 && photoPathForFirstPlot != null) 'photo_local_path': photoPathForFirstPlot,
        'sync_status': 'pending',
      });
    }
    return outingId;
  }

  Future<Map<String, Object?>> outing(int id) async =>
      (await (await db).query('field_outings', where: 'id = ?', whereArgs: [id])).single;

  Future<List<Map<String, Object?>>> vegetation(int outingId) async =>
      (await db).query('vegetation_records', where: 'outing_id = ?', whereArgs: [outingId], orderBy: 'plot_number');

  Future<int> outingCount() async => Sqflite.firstIntValue(await (await db).rawQuery('SELECT COUNT(*) FROM field_outings'))!;
}

Future<String> writeTempPhoto() async {
  final dir = await Directory.systemTemp.createTemp('sync_test_photo');
  addTearDown(() => dir.delete(recursive: true));
  final file = File('${dir.path}/plot.jpg');
  await file.writeAsBytes(List.filled(64, 7));
  return file.path;
}

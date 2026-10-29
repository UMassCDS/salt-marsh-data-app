import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:mass_marsh_app/database/app_database.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import '../support/known_gap.dart';
import '../support/sync_harness.dart' show useInMemorySqlite;

const currentVersion = 10;
const oldVersions = [1, 2, 3, 4, 5, 6, 7, 8, 9];

// Only v7 and later ever shipped in a tagged release; v1 and v2 fixtures are reconstructed from the migrations
const knownGaps = <String, Map<int, String>>{
  'same schema as a fresh install': {
    1: 'v1 and v2 rows are lost: INSERT ... SELECT * misaligns columns after ADD COLUMN',
    2: 'v1 and v2 rows are lost: INSERT ... SELECT * misaligns columns after ADD COLUMN',
    3: 'vegetation_records keeps NOT NULL constraints that a fresh install dropped',
    4: 'vegetation_records keeps NOT NULL constraints that a fresh install dropped',
    5: 'vegetation_records keeps NOT NULL constraints that a fresh install dropped',
    6: 'vegetation_records keeps NOT NULL constraints that a fresh install dropped',
  },
  'keeps the existing rows': {
    1: 'v1 and v2 rows are lost: INSERT ... SELECT * misaligns columns after ADD COLUMN',
    2: 'v1 and v2 rows are lost: INSERT ... SELECT * misaligns columns after ADD COLUMN',
  },
  'accepts new rows afterwards': {
    1: 'upgrade itself fails for v1 and v2',
    2: 'upgrade itself fails for v1 and v2',
    3: 'table rebuild leaves child foreign keys pointing at the dropped _field_outings_old',
    4: 'table rebuild leaves child foreign keys pointing at the dropped _field_outings_old',
    5: 'table rebuild leaves child foreign keys pointing at the dropped _field_outings_old',
    6: 'vegetation_records keeps NOT NULL constraints that a fresh install dropped',
  },
};

// Arrange runs outside the gap check so a broken fixture fails loudly instead of passing as the gap
void versionTest(
  String name,
  int version,
  Future<String> Function() arrange,
  Future<void> Function(String path) verify,
) {
  final gap = knownGaps[name]?[version];
  test(gap == null ? name : '$name [known gap]', () async {
    final path = await arrange();
    if (gap == null) return verify(path);
    await expectKnownGap(gap, () => verify(path), isExpected: (e) => e is TestFailure || e is DatabaseException);
  });
}

void main() {
  setUpAll(useInMemorySqlite);

  late Directory dir;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('db_upgrade_test');
  });

  tearDown(() => dir.delete(recursive: true));

  String newPath(String name) => '${dir.path}/$name.db';

  Future<Database> createOldDatabase(String path, int version) async {
    final sql = await File('test/fixtures/db_schemas/v$version.sql').readAsString();
    final statements = sql
        .split(';')
        .map((s) => s.split('\n').where((l) => !l.trimLeft().startsWith('-- ')).join('\n').trim())
        .where((s) => s.isNotEmpty);
    return databaseFactory.openDatabase(
      path,
      options: OpenDatabaseOptions(
        version: version,
        onCreate: (db, _) async {
          for (final statement in statements) {
            await db.execute(statement);
          }
        },
      ),
    );
  }

  Future<void> insertRow(Database db, String table, Map<String, Object?> values) async {
    final columns = await db.rawQuery('PRAGMA table_info($table)');
    final row = <String, Object?>{};
    for (final column in columns) {
      final name = column['name'] as String;
      if (values.containsKey(name)) {
        row[name] = values[name];
      } else if (column['notnull'] == 1 && column['dflt_value'] == null && column['pk'] == 0) {
        final type = (column['type'] as String).toUpperCase();
        row[name] = type.contains('INT') ? 1 : (type.contains('REAL') ? 1.0 : 'filler');
      }
    }
    await db.insert(table, row);
  }

  Future<void> seedField(Database db) async {
    await insertRow(db, 'field_outings', {
      'id': 1,
      'local_id': 'outing-1',
      'server_id': 77,
      'org_id': 1,
      'site_name': 'Plum Island',
      'monitoring_type': 'vegetation',
      'start_time': '2026-07-01T09:00:00',
      'sync_status': 'synced',
      'is_draft': 0,
    });
    await insertRow(db, 'vegetation_records', {
      'id': 1,
      'local_id': 'veg-1',
      'server_id': 501,
      'outing_id': 1,
      'transect_id': 'T1',
      'plot_number': 3,
      'plot_id': 'PLT-3',
      'latitude': 42.1,
      'longitude': -71.2,
      'species_observations': '[{"species_code":"SPAL","percentage_cover":60}]',
      'sync_status': 'synced',
    });
    await insertRow(db, 'hydrology_records', {
      'id': 1,
      'local_id': 'hyd-1',
      'outing_id': 1,
      'serial_number': 'WLR-9',
    });
    await insertRow(db, 'elevation_records', {
      'id': 1,
      'local_id': 'elev-1',
      'outing_id': 1,
      'transect_id': 'T1',
      'point_number': 2,
      'elevation_navd88_m': 1.5,
    });
  }

  Future<Map<String, List<String>>> describeSchema(Database db) async {
    final tables = await db.rawQuery(
      "SELECT name FROM sqlite_master WHERE type = 'table' AND name NOT LIKE 'sqlite_%' ORDER BY name",
    );
    final schema = <String, List<String>>{};
    for (final table in tables) {
      final name = table['name'] as String;
      final columns = await db.rawQuery('PRAGMA table_info($name)');
      final foreignKeys = await db.rawQuery('PRAGMA foreign_key_list($name)');
      schema[name] = [
        for (final c in columns)
          '${c['name']} ${(c['type'] as String).toUpperCase()} notnull=${c['notnull']} pk=${c['pk']} default=${c['dflt_value']}',
        for (final fk in foreignKeys) 'fk ${fk['from']} -> ${fk['table']}.${fk['to']} on_delete=${fk['on_delete']}',
      ]..sort();
    }
    return schema;
  }

  Future<Set<String>> indexNames(Database db) async {
    final rows = await db.rawQuery(
      "SELECT name FROM sqlite_master WHERE type = 'index' AND name NOT LIKE 'sqlite_%'",
    );
    return {for (final r in rows) r['name'] as String};
  }

  Future<String> oldDatabase(int version, {bool seeded = true}) async {
    final path = newPath('old');
    final old = await createOldDatabase(path, version);
    if (seeded) await seedField(old);
    await old.close();
    return path;
  }

  Future<AppDatabase> upgrade(String path) async {
    final appDb = AppDatabase.forTesting(path: path);
    await appDb.database;
    return appDb;
  }

  group('upgrading an old database', () {
    for (final version in oldVersions) {
      group('from v$version', () {
        versionTest('same schema as a fresh install', version, () => oldDatabase(version), (oldPath) async {
          final upgraded = await upgrade(oldPath);
          final fresh = await upgrade(newPath('fresh'));
          addTearDown(upgraded.close);
          addTearDown(fresh.close);

          final upgradedDb = await upgraded.database;
          final freshDb = await fresh.database;
          expect(await upgradedDb.getVersion(), currentVersion);
          expect(await describeSchema(upgradedDb), await describeSchema(freshDb));
          expect(await indexNames(upgradedDb), await indexNames(freshDb));
        });

        versionTest('keeps the existing rows', version, () => oldDatabase(version), (oldPath) async {
          final upgraded = await upgrade(oldPath);
          addTearDown(upgraded.close);
          final db = await upgraded.database;

          final outing = (await db.query('field_outings')).single;
          expect(outing['local_id'], 'outing-1');
          expect(outing['site_name'], 'Plum Island');
          expect(outing['org_id'], 1);
          expect(outing['start_time'], '2026-07-01T09:00:00');
          if (version >= 2) expect(outing['server_id'], 77);

          final veg = (await db.query('vegetation_records')).single;
          expect(veg['local_id'], 'veg-1');
          expect(veg['outing_id'], 1);
          expect(veg['plot_number'], 3);
          expect(veg['species_observations'], '[{"species_code":"SPAL","percentage_cover":60}]');
          if (version >= 3) expect(veg['plot_id'], 'PLT-3');

          expect((await db.query('hydrology_records')).single['serial_number'], 'WLR-9');
          expect((await db.query('elevation_records')).single['elevation_navd88_m'], 1.5);
        });

        versionTest('accepts new rows afterwards', version, () => oldDatabase(version, seeded: false), (oldPath) async {
          final upgraded = await upgrade(oldPath);
          addTearDown(upgraded.close);
          final db = await upgraded.database;

          await db.insert('field_outings', {
            'local_id': 'new-outing',
            'org_id': 1,
            'site_name': 'Rumney',
            'monitoring_type': 'vegetation',
            'accuracy_m': 3.2,
            'location_quality': 'good',
          });
          await db.insert('vegetation_records', {
            'local_id': 'new-veg',
            'outing_id': (await db.query('field_outings', where: "local_id = 'new-outing'")).single['id'],
            'plot_number': 1,
            'latitude': 42.0,
            'longitude': -71.0,
            'species_observations': '[]',
            'photo_upload_error': 'timeout',
            'photo_upload_attempts': 2,
            'location_quality': 'good',
          });

          expect((await db.query('vegetation_records', where: "local_id = 'new-veg'")).single['photo_upload_attempts'], 2);
        });
      });
    }

    test('opening an already-current database changes nothing', () async {
      final path = newPath('current');
      final first = await upgrade(path);
      final db = await first.database;
      await db.insert('field_outings', {
        'local_id': 'keep-me',
        'org_id': 1,
        'site_name': 'Plum Island',
        'monitoring_type': 'vegetation',
      });
      final schemaBefore = await describeSchema(db);
      await first.close();

      final second = await upgrade(path);
      addTearDown(second.close);
      final reopened = await second.database;
      expect(await reopened.getVersion(), currentVersion);
      expect(await describeSchema(reopened), schemaBefore);
      expect((await reopened.query('field_outings')).single['local_id'], 'keep-me');
    });
  });

  group('an upgrade that was interrupted', () {
    test('after adding GPS columns but before bumping the version still completes', () async {
      final path = newPath('interrupted');
      final old = await createOldDatabase(path, 9);
      await seedField(old);
      await old.execute('ALTER TABLE field_outings ADD COLUMN accuracy_m REAL');
      await old.execute('ALTER TABLE vegetation_records ADD COLUMN location_quality TEXT');
      await old.close();

      final upgraded = await upgrade(path);
      addTearDown(upgraded.close);
      final db = await upgraded.database;

      expect(await db.getVersion(), currentVersion);
      expect((await db.query('field_outings')).single['local_id'], 'outing-1');
      final columns = (await db.rawQuery('PRAGMA table_info(field_outings)')).map((c) => c['name']).toList();
      expect(columns.where((c) => c == 'accuracy_m'), hasLength(1));
      expect(columns, contains('location_quality'));
    });

    test('with every GPS column already present still completes', () async {
      final path = newPath('interrupted_all');
      final old = await createOldDatabase(path, 9);
      for (final statement in [
        'ALTER TABLE field_outings ADD COLUMN accuracy_m REAL',
        'ALTER TABLE field_outings ADD COLUMN location_quality TEXT',
        'ALTER TABLE vegetation_records ADD COLUMN location_quality TEXT',
        'ALTER TABLE elevation_records ADD COLUMN accuracy_m REAL',
        'ALTER TABLE elevation_records ADD COLUMN location_quality TEXT',
      ]) {
        await old.execute(statement);
      }
      await old.close();

      final upgraded = await upgrade(path);
      addTearDown(upgraded.close);
      expect(await (await upgraded.database).getVersion(), currentVersion);
    });
  });
}

import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:mass_marsh_app/database/app_database.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart' show inMemoryDatabasePath;
import '../support/sync_harness.dart' show useInMemorySqlite;

final sopFile = File('test/fixtures/payloads/sop_species.json');

void main() {
  setUpAll(useInMemorySqlite);

  test('a fresh install has every species in the SOP table with the SOP common name', () async {
    final sop = (jsonDecode(sopFile.readAsStringSync())['common_names'] as Map<String, dynamic>).cast<String, String>();
    final appDb = AppDatabase.forTesting(path: inMemoryDatabasePath);
    addTearDown(appDb.close);
    final rows = await (await appDb.database).query('species_lookup', columns: ['species_code', 'common_name']);
    final offered = {for (final r in rows) r['species_code'] as String: r['common_name'] as String?};

    expect(sop.keys.where((code) => !offered.containsKey(code)), isEmpty, reason: 'SOP species missing from the app');
    final wrong = {for (final e in sop.entries) if (offered[e.key] != e.value) e.key: offered[e.key]};
    expect(wrong, isEmpty, reason: 'common names that differ from the SOP table');
  });

  test('species added beyond the SOP table are kept', () async {
    final appDb = AppDatabase.forTesting(path: inMemoryDatabasePath);
    addTearDown(appDb.close);
    final rows = await (await appDb.database).query('species_lookup', columns: ['species_code']);

    expect(rows.map((r) => r['species_code']), containsAll(['BARE', 'DEAD', 'WRACK', 'WATER', 'ALGAE']));
  });
}

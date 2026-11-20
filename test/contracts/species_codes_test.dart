import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart' show inMemoryDatabasePath;
import 'package:mass_marsh_app/database/app_database.dart';
import '../support/sync_harness.dart' show useInMemorySqlite;

final speciesFile = File('test/fixtures/payloads/app_species_codes.json');
final updating = Platform.environment['UPDATE_PAYLOADS'] == '1';

String canonicalCodes(List<String> codes) => '${const JsonEncoder.withIndent('  ').convert({'species_codes': codes})}\n';

void main() {
  setUpAll(useInMemorySqlite);

  test('the species a fresh install offers match the saved list the backend checks', () async {
    final appDb = AppDatabase.forTesting(path: inMemoryDatabasePath);
    addTearDown(appDb.close);
    final rows = await (await appDb.database).query('species_lookup', columns: ['species_code']);
    final actual = canonicalCodes(rows.map((r) => r['species_code'] as String).toList()..sort());

    if (updating) {
      await speciesFile.create(recursive: true);
      await speciesFile.writeAsString(actual);
      return;
    }
    expect(speciesFile.existsSync(), isTrue, reason: 'No saved list. Run: UPDATE_PAYLOADS=1 flutter test test/contracts');
    expect(actual, await speciesFile.readAsString(), reason: 'The app offers different species. The server must have every code before this is updated: UPDATE_PAYLOADS=1 flutter test test/contracts');
  });
}

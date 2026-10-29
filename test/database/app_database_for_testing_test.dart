import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:mass_marsh_app/database/app_database.dart';
import '../support/sync_harness.dart' show useInMemorySqlite;

void main() {
  setUpAll(useInMemorySqlite);

  test('a test database reports the path it actually opened', () async {
    final dir = await Directory.systemTemp.createTemp('app_db_path');
    addTearDown(() => dir.delete(recursive: true));
    final path = '${dir.path}/custom.db';
    final appDb = AppDatabase.forTesting(path: path);
    addTearDown(appDb.close);

    await appDb.database;

    expect(await appDb.getDatabasePath(), path);
    expect(File(path).existsSync(), isTrue);
  });
}

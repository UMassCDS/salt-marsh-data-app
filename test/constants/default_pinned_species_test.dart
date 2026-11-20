import 'package:flutter_test/flutter_test.dart';
import 'package:mass_marsh_app/constants/species_constants.dart';
import 'package:mass_marsh_app/database/app_database.dart';
import 'package:mass_marsh_app/models/field_outing/plot_data.dart';
import 'package:mass_marsh_app/services/protocol_service.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart' show inMemoryDatabasePath;
import '../support/sync_harness.dart' show useInMemorySqlite;

const sopOrder = ['SPALT', 'SPPAT', 'DISPI', 'SADEP', 'BARE', 'DEAD'];

void main() {
  setUpAll(useInMemorySqlite);

  test('the default pinned species follow the SOP order', () {
    expect(kDefaultPinnedSpecies, sopOrder);
  });

  test('a new plot lists the pinned species in that order', () {
    final plot = PlotData(transectId: 'T1', plotNumber: 1, habitatType: '', distanceAlongTransect: 0, latitude: 0, longitude: 0);
    addTearDown(plot.dispose);

    expect(plot.pinnedControllers.keys.toList(), sopOrder);
  });

  test('the offline fallback protocol pins the same species', () {
    expect(ProtocolDefinition.massMarshVegDefault().speciesConfig.pinnedSpecies, sopOrder);
  });

  test('every pinned species is in the list a fresh install offers', () async {
    final appDb = AppDatabase.forTesting(path: inMemoryDatabasePath);
    addTearDown(appDb.close);
    final rows = await (await appDb.database).query('species_lookup', columns: ['species_code']);

    expect(rows.map((r) => r['species_code']), containsAll(kDefaultPinnedSpecies));
  });
}

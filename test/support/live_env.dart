import 'dart:convert';
import 'dart:io';
import 'sync_harness.dart';

final baseUrl = Platform.environment['E2E_API_BASE_URL'];
final backendRequired = Platform.environment['E2E_REQUIRED'] == '1';
final skipWithoutBackend = baseUrl == null ? 'set E2E_API_BASE_URL to run against a real backend' : null;

const contributor = ('contributor@umass.edu', 'demo123');
const manager = ('manager@umass.edu', 'demo123');
const viewer = ('viewer@umass.edu', 'demo123');

Map<String, Object?> _plotRow(String localId, int outingId, int plot) => {
      'local_id': '$localId-plot-$plot',
      'outing_id': outingId,
      'transect_id': 'T1',
      'plot_number': plot,
      'latitude': 42.1,
      'longitude': -71.2,
      'accuracy_m': 4.2,
      'location_quality': 'gps_good',
      'canopy_height_m': 0.45,
      'thatch_height_m': 0.07,
      'species_observations': jsonEncode([
        {'species_code': 'SPALT', 'percentage_cover': 60},
        {'species_code': 'BARE', 'percentage_cover': 40},
      ]),
      'protocol_code': 'MassMarshVeg',
      'sync_status': 'pending',
    };

Future<int> seedOuting(SyncHarness harness, {required int orgId, required String localId, int plots = 2}) async {
  final db = await harness.db;
  final outingId = await db.insert('field_outings', {
    'local_id': localId,
    'org_id': orgId,
    'site_name': localId,
    'other_members': 'Sam Rivera',
    'monitoring_type': 'vegetation',
    'start_time': '2026-07-01T09:00:00',
    'end_time': '2026-07-01T11:30:00',
    'is_draft': 0,
    'sync_status': 'pending',
  });
  for (var plot = 1; plot <= plots; plot++) {
    await db.insert('vegetation_records', _plotRow(localId, outingId, plot));
  }
  return outingId;
}

Future<void> addLatePlot(SyncHarness harness, {required int outingId, required String localId, required int plot}) async {
  final row = _plotRow(localId, outingId, plot)..remove('sync_status');
  await (await harness.db).insert('vegetation_records', row);
}

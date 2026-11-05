import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import '../support/live_backend.dart';
import '../support/sync_harness.dart';

// Runs the app's real sync code against a real backend. Skipped unless E2E_API_BASE_URL is set (the backend repo's workflow sets it).
final baseUrl = Platform.environment['E2E_API_BASE_URL'];
// Set by the backend workflow so a missing backend fails the run instead of silently skipping every test
final backendRequired = Platform.environment['E2E_REQUIRED'] == '1';

const contributor = ('contributor@umass.edu', 'demo123');
const manager = ('manager@umass.edu', 'demo123');

void main() {
  setUpAll(useInMemorySqlite);

  test('a backend address is provided when the run requires one', () {
    if (backendRequired) expect(baseUrl, isNotNull, reason: 'E2E_REQUIRED is set but E2E_API_BASE_URL is not');
  });

  group('against a real backend', skip: baseUrl == null ? 'set E2E_API_BASE_URL to run against a real backend' : null, () {
    late LiveBackend backend;
    late String contributorToken;
    late String managerToken;
    late int orgId;

    setUpAll(() async {
      backend = LiveBackend(baseUrl!);
      contributorToken = await backend.login(contributor.$1, contributor.$2);
      managerToken = await backend.login(manager.$1, manager.$2);
      orgId = await backend.firstOrganizationId(contributorToken);
    });

    Future<int> seedOuting(SyncHarness harness, String localId) async {
      final db = await harness.db;
      final outingId = await db.insert('field_outings', {
        'local_id': localId,
        'org_id': orgId,
        'site_name': 'Plum Island',
        'other_members': 'Sam Rivera',
        'monitoring_type': 'vegetation',
        'start_time': '2026-07-01T09:00:00',
        'end_time': '2026-07-01T11:30:00',
        'is_draft': 0,
        'sync_status': 'pending',
      });
      for (var plot = 1; plot <= 2; plot++) {
        await db.insert('vegetation_records', {
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
        });
      }
      return outingId;
    }

    test('an outing uploads once and both sides agree on what was stored', () async {
      final harness = await SyncHarness.createLive(baseUrl: baseUrl!, token: contributorToken);
      addTearDown(harness.dispose);
      final outingId = await seedOuting(harness, 'e2e-upload-1');

      final serverId = await harness.sync.uploadFieldOuting(outingId);

      expect(serverId, isNotNull);
      final outing = await harness.outing(outingId);
      expect(outing['sync_status'], 'synced');
      expect(outing['server_id'], serverId);
      final plots = await harness.vegetation(outingId);
      expect(plots.map((p) => p['sync_status']), everyElement('synced'));
      expect(plots.map((p) => p['server_id']), everyElement(isNotNull));

      final status = await backend.syncStatus(managerToken, ['e2e-upload-1']);
      expect(status['e2e-upload-1'], containsPair('synced', true));
      expect(status['e2e-upload-1'], containsPair('server_id', serverId));
      final stored = (await backend.sessions(managerToken, orgId)).where((s) => s['id'] == serverId).single;
      expect(stored['site_name'], 'Plum Island');
      expect(stored['monitoring_type'], 'vegetation');
      expect(stored['record_count'], 2);
    });

    test('sending the same outing again does not create a second session', () async {
      final harness = await SyncHarness.createLive(baseUrl: baseUrl!, token: contributorToken);
      addTearDown(harness.dispose);
      final outingId = await seedOuting(harness, 'e2e-resend-1');
      final first = await harness.sync.uploadFieldOuting(outingId);
      final before = (await backend.sessions(managerToken, orgId)).length;

      await (await harness.db).update('field_outings', {'sync_status': 'pending', 'server_id': null}, where: 'id = ?', whereArgs: [outingId]);
      final second = await harness.sync.uploadFieldOuting(outingId);

      expect(second, first);
      expect((await backend.sessions(managerToken, orgId)).length, before);
    });
  });
}

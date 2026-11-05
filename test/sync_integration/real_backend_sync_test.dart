import 'package:flutter_test/flutter_test.dart';
import '../support/live_backend.dart';
import '../support/live_env.dart';
import '../support/sync_harness.dart';

void main() {
  setUpAll(useInMemorySqlite);

  test('a backend address is provided when the run requires one', () {
    if (backendRequired) expect(baseUrl, isNotNull, reason: 'E2E_REQUIRED is set but E2E_API_BASE_URL is not');
  });

  group('against a real backend', skip: skipWithoutBackend, () {
    late LiveBackend backend;
    late String contributorToken;
    late String managerToken;
    late int orgId;
    final run = DateTime.now().millisecondsSinceEpoch;

    setUpAll(() async {
      backend = LiveBackend(baseUrl!);
      contributorToken = await backend.login(contributor.$1, contributor.$2);
      managerToken = await backend.login(manager.$1, manager.$2);
      orgId = await backend.firstOrganizationId(contributorToken);
    });

    test('an outing uploads once and both sides agree on what was stored', () async {
      final harness = await SyncHarness.createLive(baseUrl: baseUrl!, token: contributorToken);
      addTearDown(harness.dispose);
      final outingId = await seedOuting(harness, orgId: orgId, localId: 'e2e-upload-1-$run');

      final serverId = await harness.sync.uploadFieldOuting(outingId);

      expect(serverId, isNotNull);
      final outing = await harness.outing(outingId);
      expect(outing['sync_status'], 'synced');
      expect(outing['server_id'], serverId);
      final plots = await harness.vegetation(outingId);
      expect(plots.map((p) => p['sync_status']), everyElement('synced'));
      expect(plots.map((p) => p['server_id']), everyElement(isNotNull));

      final status = await backend.syncStatus(managerToken, ['e2e-upload-1-$run']);
      expect(status['e2e-upload-1-$run'], containsPair('synced', true));
      expect(status['e2e-upload-1-$run'], containsPair('server_id', serverId));
      final stored = (await backend.sessions(managerToken, orgId)).where((s) => s['id'] == serverId).single;
      expect(stored['site_name'], 'e2e-upload-1-$run');
      expect(stored['monitoring_type'], 'vegetation');
      expect(stored['record_count'], 2);
    });

    test('sending the same outing again does not create a second session', () async {
      final harness = await SyncHarness.createLive(baseUrl: baseUrl!, token: contributorToken);
      addTearDown(harness.dispose);
      final outingId = await seedOuting(harness, orgId: orgId, localId: 'e2e-resend-1-$run');
      final first = await harness.sync.uploadFieldOuting(outingId);
      

      await (await harness.db).update('field_outings', {'sync_status': 'pending', 'server_id': null}, where: 'id = ?', whereArgs: [outingId]);
      final second = await harness.sync.uploadFieldOuting(outingId);

      expect(second, first);
      expect((await backend.sessions(managerToken, orgId)).where((s) => s['site_name'] == 'e2e-resend-1-$run'), hasLength(1));
    });
  });
}

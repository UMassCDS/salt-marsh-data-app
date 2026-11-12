import 'package:flutter_test/flutter_test.dart';
import '../support/live_env.dart';
import '../support/sync_harness.dart';

void main() {
  setUpAll(useInMemorySqlite);

  test('a backend address is provided when the run requires one', () {
    if (backendRequired) expect(baseUrl, isNotNull, reason: 'E2E_REQUIRED is set but E2E_API_BASE_URL is not');
  });

  group('against a real backend', skip: skipWithoutBackend, () {
    late LiveRun live;

    setUpAll(() async => live = await LiveRun.start());
    tearDownAll(() => live.cleanUp());

    test('an outing uploads once and both sides agree on what was stored', () async {
      final localId = live.localId('upload');
      final harness = await SyncHarness.createLive(baseUrl: baseUrl!, token: live.contributorToken);
      addTearDown(harness.dispose);
      final outingId = await live.seedOuting(harness, localId);

      final serverId = await harness.sync.uploadFieldOuting(outingId);

      expect(serverId, isNotNull);
      final outing = await harness.outing(outingId);
      expect(outing['sync_status'], 'synced');
      expect(outing['server_id'], serverId);
      final plots = await harness.vegetation(outingId);
      expect(plots.map((p) => p['sync_status']), everyElement('synced'));
      expect(plots.map((p) => p['server_id']), everyElement(isNotNull));

      final status = await live.backend.syncStatus(live.managerToken, [localId]);
      expect(status[localId], containsPair('synced', true));
      expect(status[localId], containsPair('server_id', serverId));
      final stored = (await live.storedSession(localId))!;
      expect(stored['site_name'], localId);
      expect(stored['monitoring_type'], 'vegetation');
      expect(stored['record_count'], 2);

      final detail = await live.backend.sessionDetail(live.managerToken, live.orgId, serverId!);
      final times = {
        for (final p in (detail['vegetation_records'] as List).cast<Map<String, dynamic>>())
          p['plot_number']: (p['plot_start_time'], p['plot_end_time']),
      };
      expect(times, {1: (plotOneStart, plotOneEnd), 2: (null, null)});
    });

    test('sending the same outing again does not create a second session', () async {
      final localId = live.localId('resend');
      final harness = await SyncHarness.createLive(baseUrl: baseUrl!, token: live.contributorToken);
      addTearDown(harness.dispose);
      final outingId = await live.seedOuting(harness, localId);
      final first = await harness.sync.uploadFieldOuting(outingId);

      await (await harness.db).update('field_outings', {'sync_status': 'pending', 'server_id': null}, where: 'id = ?', whereArgs: [outingId]);
      final second = await harness.sync.uploadFieldOuting(outingId);

      expect(second, first);
      expect(await live.sessionsNamed(localId), 1);
    });
  });
}

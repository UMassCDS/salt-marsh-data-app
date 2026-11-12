import 'package:flutter_test/flutter_test.dart';
import '../support/live_env.dart';
import '../support/live_faults.dart';
import '../support/sync_harness.dart';

void main() {
  setUpAll(useInMemorySqlite);

  group('recovery against a real backend', skip: skipWithoutBackend, () {
    late LiveRun live;

    setUpAll(() async => live = await LiveRun.start());
    tearDownAll(() => live.cleanUp());

    test('a lost reply after the server saved the outing leaves one session and settles on the next sync', () async {
      final localId = live.localId('lost-reply');
      final lostReply = LostReplyAdapter(method: 'POST', pathContains: '/field-outings');
      final harness = await SyncHarness.createLive(baseUrl: baseUrl!, token: live.contributorToken, adapter: lostReply);
      addTearDown(harness.dispose);
      final outingId = await live.seedOuting(harness, localId);

      expect(await harness.sync.uploadFieldOuting(outingId), isNull);
      expect(lostReply.committed, 1);
      expect((await harness.outing(outingId))['sync_status'], 'pending');
      expect(await live.sessionsNamed(localId), 1);

      await harness.sync.uploadAllPendingOutings();

      expect(await live.sessionsNamed(localId), 1);
      final stored = (await live.storedSession(localId))!;
      final outing = await harness.outing(outingId);
      expect(outing['sync_status'], 'synced');
      expect(outing['server_id'], stored['id']);
      expect((await harness.vegetation(outingId)).map((p) => p['server_id']), everyElement(isNotNull));
    });

    test('a plot saved after the outing synced reaches the same session exactly once', () async {
      final localId = live.localId('late-plot');
      final harness = await SyncHarness.createLive(baseUrl: baseUrl!, token: live.contributorToken);
      addTearDown(harness.dispose);
      final outingId = await live.seedOuting(harness, localId);
      final serverId = await harness.sync.uploadFieldOuting(outingId);
      expect(serverId, isNotNull);

      await live.addLatePlot(harness, outingId: outingId, localId: localId, plot: 3);
      await harness.sync.uploadAllPendingOutings();
      await harness.sync.uploadAllPendingOutings();

      expect(await live.sessionsNamed(localId), 1);
      final stored = (await live.storedSession(localId))!;
      expect(stored['id'], serverId);
      expect(stored['record_count'], 3);
      expect((await harness.vegetation(outingId)).map((p) => p['server_id']), everyElement(isNotNull));
    });

    test('a viewer cannot upload, nothing is created, and the outing stays pending for later', () async {
      final localId = live.localId('viewer');
      final harness = await SyncHarness.createLive(baseUrl: baseUrl!, token: live.viewerToken);
      addTearDown(harness.dispose);
      final outingId = await live.seedOuting(harness, localId);

      expect(await harness.sync.uploadFieldOuting(outingId), isNull);

      expect(await live.sessionsNamed(localId), 0);
      expect(await live.storedSession(localId), isNull);
      final outing = await harness.outing(outingId);
      expect(outing['sync_status'], 'pending');
      expect(outing['server_id'], isNull);
      expect(await harness.sync.getPendingItemsCount(), 1);
    });

    test('the same pending outing uploads once the user has upload rights', () async {
      final localId = live.localId('rights');
      final harness = await SyncHarness.createLive(baseUrl: baseUrl!, token: live.viewerToken);
      addTearDown(harness.dispose);
      final outingId = await live.seedOuting(harness, localId);
      await harness.sync.uploadFieldOuting(outingId);
      expect(await live.storedSession(localId), isNull);

      harness.sync.setAuthToken(live.contributorToken);
      final serverId = await harness.sync.uploadFieldOuting(outingId);

      expect(serverId, isNotNull);
      expect(await live.storedSession(localId), isNotNull);
      expect((await harness.outing(outingId))['sync_status'], 'synced');
    });

    test('an outing saved while signed out stays pending and uploads after signing in', () async {
      final localId = live.localId('signed-out');
      final harness = await SyncHarness.createLive(baseUrl: baseUrl!, token: live.contributorToken);
      addTearDown(harness.dispose);
      harness.sync.clearAuthToken();
      final outingId = await live.seedOuting(harness, localId);

      expect(await harness.sync.uploadAllPendingOutings(), 0);
      expect(await live.storedSession(localId), isNull);
      expect((await harness.outing(outingId))['sync_status'], 'pending');

      harness.sync.setAuthToken(live.contributorToken);
      expect(await harness.sync.uploadAllPendingOutings(), 1);

      expect(await live.storedSession(localId), isNotNull);
      expect((await harness.outing(outingId))['sync_status'], 'synced');
    });
  });
}

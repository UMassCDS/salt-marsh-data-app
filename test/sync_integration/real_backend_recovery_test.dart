import 'package:flutter_test/flutter_test.dart';
import '../support/live_backend.dart';
import '../support/live_env.dart';
import '../support/live_faults.dart';
import '../support/sync_harness.dart';

void main() {
  setUpAll(useInMemorySqlite);

  group('recovery against a real backend', skip: skipWithoutBackend, () {
    late LiveBackend backend;
    late String contributorToken;
    late String managerToken;
    late String viewerToken;
    late int orgId;
    final run = DateTime.now().millisecondsSinceEpoch;

    setUpAll(() async {
      backend = LiveBackend(baseUrl!);
      contributorToken = await backend.login(contributor.$1, contributor.$2);
      managerToken = await backend.login(manager.$1, manager.$2);
      viewerToken = await backend.login(viewer.$1, viewer.$2);
      orgId = await backend.firstOrganizationId(contributorToken);
    });

    Future<int> sessionsNamed(String localId) async =>
        (await backend.sessions(managerToken, orgId)).where((s) => s['site_name'] == localId).length;

    Future<Map<String, dynamic>?> storedSession(String localId) async {
      final serverId = (await backend.syncStatus(managerToken, [localId]))[localId]?['server_id'];
      if (serverId == null) return null;
      return (await backend.sessions(managerToken, orgId)).where((s) => s['id'] == serverId).singleOrNull;
    }

    test('a lost reply after the server saved the outing leaves one session and settles on the next sync', () async {
      final localId = 'e2e-lost-reply-$run';
      final lostReply = LostReplyAdapter(method: 'POST', pathContains: '/field-outings');
      final harness = await SyncHarness.createLive(baseUrl: baseUrl!, token: contributorToken, adapter: lostReply);
      addTearDown(harness.dispose);
      final outingId = await seedOuting(harness, orgId: orgId, localId: localId);

      expect(await harness.sync.uploadFieldOuting(outingId), isNull);
      expect(lostReply.committed, 1);
      expect((await harness.outing(outingId))['sync_status'], 'pending');
      expect(await sessionsNamed(localId), 1);

      await harness.sync.uploadAllPendingOutings();

      expect(await sessionsNamed(localId), 1);
      final stored = (await storedSession(localId))!;
      final outing = await harness.outing(outingId);
      expect(outing['sync_status'], 'synced');
      expect(outing['server_id'], stored['id']);
      expect((await harness.vegetation(outingId)).map((p) => p['server_id']), everyElement(isNotNull));
    });

    test('a plot saved after the outing synced reaches the same session exactly once', () async {
      final localId = 'e2e-late-plot-$run';
      final harness = await SyncHarness.createLive(baseUrl: baseUrl!, token: contributorToken);
      addTearDown(harness.dispose);
      final outingId = await seedOuting(harness, orgId: orgId, localId: localId);
      final serverId = await harness.sync.uploadFieldOuting(outingId);
      expect(serverId, isNotNull);

      await addLatePlot(harness, outingId: outingId, localId: localId, plot: 3);
      await harness.sync.uploadAllPendingOutings();
      await harness.sync.uploadAllPendingOutings();

      expect(await sessionsNamed(localId), 1);
      final stored = (await storedSession(localId))!;
      expect(stored['id'], serverId);
      expect(stored['record_count'], 3);
      expect((await harness.vegetation(outingId)).map((p) => p['server_id']), everyElement(isNotNull));
    });

    test('a viewer cannot upload, nothing is created, and the outing stays pending for later', () async {
      final localId = 'e2e-viewer-$run';
      final harness = await SyncHarness.createLive(baseUrl: baseUrl!, token: viewerToken);
      addTearDown(harness.dispose);
      final outingId = await seedOuting(harness, orgId: orgId, localId: localId);

      expect(await harness.sync.uploadFieldOuting(outingId), isNull);

      expect(await sessionsNamed(localId), 0);
      expect(await storedSession(localId), isNull);
      final outing = await harness.outing(outingId);
      expect(outing['sync_status'], 'pending');
      expect(outing['server_id'], isNull);
      expect(await harness.sync.getPendingItemsCount(), 1);
    });

    test('the same pending outing uploads once the user has upload rights', () async {
      final localId = 'e2e-rights-$run';
      final asViewer = await SyncHarness.createLive(baseUrl: baseUrl!, token: viewerToken);
      addTearDown(asViewer.dispose);
      final outingId = await seedOuting(asViewer, orgId: orgId, localId: localId);
      await asViewer.sync.uploadFieldOuting(outingId);
      expect(await storedSession(localId), isNull);

      asViewer.sync.setAuthToken(contributorToken);
      final serverId = await asViewer.sync.uploadFieldOuting(outingId);

      expect(serverId, isNotNull);
      expect(await storedSession(localId), isNotNull);
      expect((await asViewer.outing(outingId))['sync_status'], 'synced');
    });
  });
}

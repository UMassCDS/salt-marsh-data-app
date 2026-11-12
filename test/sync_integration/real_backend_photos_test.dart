import 'package:flutter_test/flutter_test.dart';
import '../support/live_env.dart';
import '../support/sync_harness.dart';

void main() {
  setUpAll(useInMemorySqlite);

  group('photos against a real backend', skip: skipWithoutBackend, () {
    late LiveRun live;

    setUpAll(() async => live = await LiveRun.start());
    tearDownAll(() => live.cleanUp());

    Future<Map<String, String?>> serverPhotosByPlot(int serverId) async {
      final detail = await live.backend.sessionDetail(live.managerToken, live.orgId, serverId);
      return {
        for (final plot in (detail['vegetation_records'] as List).cast<Map<String, dynamic>>())
          '${plot['plot_number']}': plot['photo_filename'] as String?,
      };
    }

    test(
      'a plot photo is stored and attached to the right plot on the server',
      skip: backendHasPhotoStorage ? null : 'set E2E_PHOTO_STORAGE=1 when the backend has photo storage',
      () async {
        final localId = live.localId('photo');
        final harness = await SyncHarness.createLive(baseUrl: baseUrl!, token: live.contributorToken);
        addTearDown(harness.dispose);
        final outingId = await live.seedOuting(harness, localId, photoForFirstPlot: await writeTempPhoto());

        final serverId = await harness.sync.uploadFieldOuting(outingId);

        expect(serverId, isNotNull);
        final photos = await serverPhotosByPlot(serverId!);
        expect(photos['1'], isNotNull);
        expect(photos['2'], isNull);
        final plots = await harness.vegetation(outingId);
        expect(plots.first['photo_filename'], photos['1']);
        expect(await harness.sync.getPendingPhotoUploadsCount(), 0);
      },
    );

    test(
      'when photo storage is down the outing still syncs and the photo waits to be retried',
      skip: backendHasPhotoStorage ? 'the backend has photo storage, so it cannot be down' : null,
      () async {
        final localId = live.localId('photo-down');
        final harness = await SyncHarness.createLive(baseUrl: baseUrl!, token: live.contributorToken);
        addTearDown(harness.dispose);
        final outingId = await live.seedOuting(harness, localId, photoForFirstPlot: await writeTempPhoto());

        final serverId = await harness.sync.uploadFieldOuting(outingId);

        expect(serverId, isNotNull);
        expect((await harness.outing(outingId))['sync_status'], 'synced');
        expect((await serverPhotosByPlot(serverId!)).values, everyElement(isNull));
        final firstPlot = (await harness.vegetation(outingId)).first;
        expect(firstPlot['photo_local_path'], isNotNull);
        expect(firstPlot['photo_upload_error'], isNotNull);
        expect(await harness.sync.getPendingPhotoUploadsCount(), 1);

        await harness.sync.uploadAllPendingOutings();

        expect(await live.sessionsNamed(localId), 1);
        expect(await harness.sync.getPendingPhotoUploadsCount(), 1);
      },
    );
  });
}

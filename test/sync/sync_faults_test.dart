import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mass_marsh_app/services/sync_service.dart';
import '../support/fake_backend.dart';
import '../support/known_gap.dart';
import '../support/sync_harness.dart';

const outingsPath = '/api/mobile/field-outings';
const syncStatusPath = '/api/mobile/sync-status';
const photosPath = '/api/mobile/photos';

void main() {
  setUpAll(useInMemorySqlite);

  late SyncHarness harness;

  Future<SyncHarness> withFaults(List<Fault> faults) async {
    harness = await SyncHarness.create(faults: faults);
    addTearDown(harness.dispose);
    return harness;
  }

  Future<void> expectEverythingSynced(int outingId, String localId) async {
    final outing = await harness.outing(outingId);
    expect(outing['sync_status'], 'synced');
    expect(outing['server_id'], harness.backend.sessionsByLocalId[localId]!.id);
    for (final plot in await harness.vegetation(outingId)) {
      expect(plot['sync_status'], 'synced', reason: 'plot ${plot['local_id']}');
      expect(plot['server_id'], harness.backend.serverPlotId(localId, plot['local_id'] as String),
          reason: 'plot ${plot['local_id']}');
    }
  }

  group('request never reaches the server', () {
    for (final type in [DioExceptionType.connectionError, DioExceptionType.connectionTimeout]) {
      test('$type leaves the outing pending and the next sync uploads it exactly once', () async {
        await withFaults([Fault(method: 'POST', path: outingsPath, kind: FaultKind.dropBeforeServer, dioType: type)]);
        final outingId = await harness.insertOuting(localId: 'o-1');

        expect(await harness.sync.uploadFieldOuting(outingId), isNull);
        expect((await harness.outing(outingId))['sync_status'], 'pending');
        expect(harness.backend.sessionCount, 0);
        expect(await harness.sync.getPendingItemsCount(), 1);

        expect(await harness.sync.uploadAllPendingOutings(), 1);
        expect(harness.backend.sessionCount, 1);
        await expectEverythingSynced(outingId, 'o-1');
        expect(await harness.sync.getPendingItemsCount(), 0);
      });
    }

    test('a server error leaves the outing pending and is retried', () async {
      await withFaults([const Fault(method: 'POST', path: outingsPath, kind: FaultKind.serverError)]);
      final outingId = await harness.insertOuting(localId: 'o-1');

      expect(await harness.sync.uploadFieldOuting(outingId), isNull);
      expect((await harness.outing(outingId))['sync_status'], 'pending');

      expect(await harness.sync.uploadAllPendingOutings(), 1);
      expect(harness.backend.sessionCount, 1);
      await expectEverythingSynced(outingId, 'o-1');
    });

    test('connectivity says online but every request fails: nothing is sent twice and the outing stays pending', () async {
      await withFaults([
        for (var i = 1; i <= 3; i++) Fault(method: 'POST', path: syncStatusPath, occurrence: i, kind: FaultKind.dropBeforeServer),
      ]);
      final outingId = await harness.insertOuting(localId: 'o-1');

      for (var i = 0; i < 3; i++) {
        expect(await harness.sync.uploadAllPendingOutings(), 0);
      }

      expect(harness.backend.callsTo('POST', outingsPath), 0);
      expect((await harness.outing(outingId))['sync_status'], 'pending');
    });
  });

  group('server saved the outing but the response was lost', () {
    for (final type in [DioExceptionType.receiveTimeout, DioExceptionType.connectionError]) {
      test('$type: the next sync does not upload a second copy', () async {
        await withFaults([Fault(method: 'POST', path: outingsPath, kind: FaultKind.loseResponseAfterCommit, dioType: type)]);
        final outingId = await harness.insertOuting(localId: 'o-1');

        expect(await harness.sync.uploadFieldOuting(outingId), isNull);
        expect(harness.backend.sessionCount, 1);

        await harness.sync.uploadAllPendingOutings();
        await harness.sync.uploadAllPendingOutings();

        expect(harness.backend.sessionCount, 1);
        expect(harness.backend.serverCommitsTo('POST', outingsPath), 1);
        final outing = await harness.outing(outingId);
        expect(outing['sync_status'], 'synced');
        expect(outing['server_id'], harness.backend.sessionsByLocalId['o-1']!.id);
      });
    }

    test('while the duplicate check keeps failing it stays pending rather than resending, then settles', () async {
      await withFaults([
        const Fault(method: 'POST', path: outingsPath, kind: FaultKind.loseResponseAfterCommit),
        for (var i = 2; i <= 4; i++)
          Fault(method: 'POST', path: syncStatusPath, occurrence: i, kind: FaultKind.loseResponseAfterCommit),
      ]);
      final outingId = await harness.insertOuting(localId: 'o-1');

      for (var i = 0; i < 4; i++) {
        await harness.sync.uploadAllPendingOutings();
      }
      expect((await harness.outing(outingId))['sync_status'], 'pending');
      expect(harness.backend.callsTo('POST', outingsPath), 1);

      await harness.sync.uploadAllPendingOutings();

      expect(harness.backend.sessionCount, 1);
      expect(harness.backend.callsTo('POST', outingsPath), 1);
      expect((await harness.outing(outingId))['sync_status'], 'synced');
    });

    knownGapTest(
      'auto-sync also records the server ids of the plots',
      'pre-check marks only the outing synced; plots stay pending with no server_id until a manual Resync',
      () async {
        await withFaults([const Fault(method: 'POST', path: outingsPath, kind: FaultKind.loseResponseAfterCommit)]);
        final outingId = await harness.insertOuting(localId: 'o-1');

        await harness.sync.uploadFieldOuting(outingId);
        await harness.sync.uploadAllPendingOutings();

        await expectEverythingSynced(outingId, 'o-1');
      },
    );

    test('manual resync recovers the plot ids without adding plots on the server', () async {
      await withFaults([const Fault(method: 'POST', path: outingsPath, kind: FaultKind.loseResponseAfterCommit)]);
      final outingId = await harness.insertOuting(localId: 'o-1');
      await harness.sync.uploadFieldOuting(outingId);

      final result = await harness.sync.resyncOuting(outingId);

      expect(result.alreadyOnServer, isTrue);
      expect(result.uploadFailed, isFalse);
      expect(harness.backend.sessionsByLocalId['o-1']!.vegetation, hasLength(2));
      expect(harness.backend.serverCommitsTo('POST', outingsPath), 1);
      await expectEverythingSynced(outingId, 'o-1');
    });

    knownGapTest(
      'a photo that failed on the same attempt still reaches the server',
      'plot has no server_id so photo retry skips it; resync re-uploads it but add-records ignores photos on existing plots',
      () async {
        final photo = await writeTempPhoto();
        await withFaults([
          const Fault(method: 'POST', path: photosPath, kind: FaultKind.dropBeforeServer),
          const Fault(method: 'POST', path: outingsPath, kind: FaultKind.loseResponseAfterCommit),
        ]);
        final outingId = await harness.insertOuting(localId: 'o-1', photoPathForFirstPlot: photo);

        await harness.sync.uploadFieldOuting(outingId);
        await harness.sync.uploadAllPendingOutings();
        await harness.sync.resyncOuting(outingId);
        await harness.sync.uploadAllPendingOutings();

        final plotId = harness.backend.serverPlotId('o-1', 'o-1-veg-1')!;
        expect(harness.backend.photoUrlByVegetationId[plotId], isNotNull);
      },
    );
  });

  group('the duplicate check itself fails', () {
    test('an unreachable sync-status never falls through to an upload', () async {
      await withFaults([const Fault(method: 'POST', path: syncStatusPath, kind: FaultKind.dropBeforeServer)]);
      final outingId = await harness.insertOuting(localId: 'o-1');

      expect(await harness.sync.uploadFieldOuting(outingId), isNull);

      expect(harness.backend.callsTo('POST', outingsPath), 0);
      expect((await harness.outing(outingId))['sync_status'], 'pending');
      expect(await harness.sync.uploadFieldOuting(outingId), isNotNull);
      expect(harness.backend.sessionCount, 1);
    });

    test('resync reports a failure instead of uploading when sync-status errors', () async {
      await withFaults([const Fault(method: 'POST', path: syncStatusPath, kind: FaultKind.serverError)]);
      final outingId = await harness.insertOuting(localId: 'o-1');

      final result = await harness.sync.resyncOuting(outingId);

      expect(result.uploadFailed, isTrue);
      expect(harness.backend.callsTo('POST', outingsPath), 0);
    });
  });

  group('overlapping uploads', () {
    test('two triggers at once in one process send one upload', () async {
      await withFaults([]);
      final outingId = await harness.insertOuting(localId: 'o-1');

      final results = await Future.wait([
        harness.sync.uploadFieldOuting(outingId),
        harness.sync.uploadFieldOuting(outingId),
        harness.sync.uploadAllPendingOutings(),
      ]);

      expect(harness.backend.serverCommitsTo('POST', outingsPath), 1);
      expect(harness.backend.sessionCount, 1);
      expect([results[0], results[1]].whereType<int>(), hasLength(1));
    });

    test('a second sync service on the same database (background isolate) still yields one server session', () async {
      await withFaults([]);
      final outingId = await harness.insertOuting(localId: 'o-1');
      final background = SyncService.forTesting(
        dio: Dio()..httpClientAdapter = harness.backend,
        db: harness.appDb,
        connectivity: harness.connectivity,
      );

      await Future.wait([
        harness.sync.uploadFieldOuting(outingId),
        background.uploadFieldOuting(outingId),
      ]);

      expect(harness.backend.sessionCount, 1);
      await expectEverythingSynced(outingId, 'o-1');
    });
  });

  group('photos', () {
    Future<int> outingWithFailedPhoto() async {
      final photo = await writeTempPhoto();
      await withFaults([const Fault(method: 'POST', path: photosPath, kind: FaultKind.dropBeforeServer)]);
      final outingId = await harness.insertOuting(localId: 'o-1', photoPathForFirstPlot: photo);
      expect(await harness.sync.uploadFieldOuting(outingId), isNotNull);
      return outingId;
    }

    test('a failed photo upload is recorded on the plot and counted as pending', () async {
      final outingId = await outingWithFailedPhoto();

      final plot = (await harness.vegetation(outingId)).first;
      expect(plot['sync_status'], 'synced');
      expect(plot['photo_upload_error'], 'No connection to the server');
      expect(plot['photo_upload_attempts'], 1);
      expect(await harness.sync.getPendingPhotoUploadsCount(), 1);
    });

    test('manual resync uploads a failed photo and attaches it to the right plot', () async {
      final outingId = await outingWithFailedPhoto();

      final result = await harness.sync.resyncOuting(outingId);

      expect(result.photosUploaded, 1);
      expect(result.photosStillPending, 0);
      final plotId = harness.backend.serverPlotId('o-1', 'o-1-veg-1')!;
      expect(harness.backend.photoUrlByVegetationId[plotId], isNotNull);
      final retried = (await harness.vegetation(outingId)).first;
      expect(retried['photo_filename'], harness.backend.photoUrlByVegetationId[plotId]);
      expect(retried['photo_upload_error'], isNull);
    });

    knownGapTest(
      'auto-sync retries a failed photo once nothing else is pending',
      'uploadAllPendingOutings returns early when no outing is pending, before retryPendingPhotoUploads',
      () async {
        final outingId = await outingWithFailedPhoto();

        await harness.sync.uploadAllPendingOutings();

        final plotId = harness.backend.serverPlotId('o-1', 'o-1-veg-1')!;
        expect(harness.backend.photoUrlByVegetationId[plotId], isNotNull);
        expect((await harness.vegetation(outingId)).first['photo_upload_error'], isNull);
        expect(await harness.sync.getPendingPhotoUploadsCount(), 0);
      },
    );

    test('a photo that uploads with the outing is attached to the right plot', () async {
      final photo = await writeTempPhoto();
      await withFaults([]);
      final outingId = await harness.insertOuting(localId: 'o-1', photoPathForFirstPlot: photo);

      await harness.sync.uploadFieldOuting(outingId);

      final plotId = harness.backend.serverPlotId('o-1', 'o-1-veg-1')!;
      expect(harness.backend.photoUrlByVegetationId, {plotId: harness.backend.uploadedPhotos.single});
    });
  });

  test('a plot saved locally after the outing synced is added by resync, once', () async {
    await withFaults([]);
    final outingId = await harness.insertOuting(localId: 'o-1');
    await harness.sync.uploadFieldOuting(outingId);
    final db = await harness.db;
    await db.insert('vegetation_records', {
      'local_id': 'o-1-veg-late',
      'outing_id': outingId,
      'transect_id': 'T1',
      'plot_number': 9,
      'latitude': 42.0,
      'longitude': -71.0,
      'species_observations': '[]',
      'protocol_code': 'MassMarshVeg',
    });

    final first = await harness.sync.resyncOuting(outingId);
    final second = await harness.sync.resyncOuting(outingId);

    expect(first.plotsRecovered, 1);
    expect(second.plotsRecovered, 0);
    expect(harness.backend.sessionsByLocalId['o-1']!.vegetation, hasLength(3));
    await expectEverythingSynced(outingId, 'o-1');
  });
}

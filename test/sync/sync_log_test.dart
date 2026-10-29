import 'dart:convert';
import 'dart:io';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mass_marsh_app/services/sync_log.dart';
import '../support/fake_backend.dart';
import '../support/sync_harness.dart';

void main() {
  setUpAll(useInMemorySqlite);

  late Directory dir;
  late File logFile;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('sync_log_test');
    logFile = File('${dir.path}/sync_log.jsonl');
  });

  tearDown(() => dir.delete(recursive: true));

  SyncLog newLog({DateTime Function()? clock, Duration retention = const Duration(days: 14)}) =>
      SyncLog(fileProvider: () async => logFile, retention: retention, clock: clock);

  SyncLogEntry entry(DateTime time, {String path = '/api/mobile/field-outings', String outcome = 'ok'}) => SyncLogEntry(
        time: time,
        method: 'POST',
        path: path,
        network: 'wifi',
        durationMs: 120,
        outcome: outcome,
        status: 200,
      );

  group('SyncLog', () {
    test('keeps entries across a new instance, as after an app restart', () async {
      await newLog().record(entry(DateTime.now()));

      final entries = await newLog().entries();

      expect(entries, hasLength(1));
      expect(entries.single.path, '/api/mobile/field-outings');
      expect(entries.single.status, 200);
    });

    test('drops entries older than the retention window when a session starts logging', () async {
      final now = DateTime(2026, 10, 29, 12);
      await newLog().record(entry(now.subtract(const Duration(days: 20)), path: '/old'));
      await newLog(clock: () => now).record(entry(now.subtract(const Duration(days: 3)), path: '/recent'));
      await newLog(clock: () => now).record(entry(now, path: '/new'));

      final paths = (await newLog().entries()).map((e) => e.path);

      expect(paths, ['/recent', '/new']);
    });

    test('ignores corrupt lines instead of failing', () async {
      await logFile.writeAsString('not json\n');
      await newLog().record(entry(DateTime.now()));

      expect(await newLog().entries(), hasLength(1));
    });

    test('stores only request metadata', () async {
      await newLog().record(entry(DateTime.now()));

      final line = (await logFile.readAsLines()).single;

      expect((jsonDecode(line) as Map).keys, unorderedEquals(['t', 'm', 'p', 'n', 'ms', 'o', 's']));
    });

    test('a log file that cannot be written never throws', () async {
      final log = SyncLog(fileProvider: () async => File('${dir.path}/missing_dir/sync_log.jsonl'));

      await log.record(entry(DateTime.now()));

      expect(await log.entries(), isEmpty);
    });

    test('dump is readable and says so when empty', () async {
      expect(await newLog().dump(), 'No sync attempts recorded.');
      await newLog().record(entry(DateTime.now()));
      expect(await newLog().dump(), contains('POST /api/mobile/field-outings network=wifi 120ms ok (200)'));
    });
  });

  group('SyncService request logging', () {
    Future<SyncHarness> harnessWithLog({List<Fault> faults = const []}) async {
      final harness = await SyncHarness.create(faults: faults, syncLog: newLog());
      addTearDown(harness.dispose);
      return harness;
    }

    test('records a successful upload and its duplicate check', () async {
      final harness = await harnessWithLog();
      final outingId = await harness.insertOuting(localId: 'o-1');

      await harness.sync.uploadFieldOuting(outingId);

      final entries = await newLog().entries();
      expect(entries.map((e) => '${e.method} ${e.path}'), ['POST /api/mobile/sync-status', 'POST /api/mobile/field-outings']);
      expect(entries.map((e) => e.outcome), everyElement('ok'));
      expect(entries.map((e) => e.network), everyElement('wifi'));
    });

    test('records dropped connections and server errors with their cause', () async {
      final harness = await harnessWithLog(faults: [
        const Fault(method: 'POST', path: '/api/mobile/sync-status', kind: FaultKind.dropBeforeServer),
        const Fault(method: 'POST', path: '/api/mobile/sync-status', occurrence: 2, kind: FaultKind.serverError),
        const Fault(
          method: 'POST',
          path: '/api/mobile/sync-status',
          occurrence: 3,
          kind: FaultKind.loseResponseAfterCommit,
          dioType: DioExceptionType.receiveTimeout,
        ),
      ]);
      final outingId = await harness.insertOuting(localId: 'o-1');

      for (var i = 0; i < 3; i++) {
        await harness.sync.uploadFieldOuting(outingId);
      }

      final outcomes = (await newLog().entries()).map((e) => e.outcome).toList();
      expect(outcomes, ['connectionError', 'http_error', 'receiveTimeout']);
      expect((await newLog().entries())[1].status, 500);
    });

    test('records which network was in use', () async {
      final harness = await harnessWithLog();
      harness.connectivity.set([ConnectivityResult.mobile]);
      final outingId = await harness.insertOuting(localId: 'o-1');

      await harness.sync.uploadFieldOuting(outingId);

      expect((await newLog().entries()).map((e) => e.network), everyElement('mobile'));
    });

    test('nothing is logged while offline because nothing is sent', () async {
      final harness = await harnessWithLog();
      harness.connectivity.set([]);
      final outingId = await harness.insertOuting(localId: 'o-1');

      await harness.sync.uploadFieldOuting(outingId);

      expect(await newLog().entries(), isEmpty);
    });

    test('a connectivity check that throws while logging never leaves a request hanging', () async {
      final harness = await harnessWithLog();
      final outingId = await harness.insertOuting(localId: 'o-1');
      harness.connectivity
        ..checkError = Exception('platform channel unavailable')
        ..checksBeforeError = 1;

      final serverId = await harness.sync.uploadFieldOuting(outingId).timeout(const Duration(seconds: 5));

      expect(serverId, isNotNull);
      expect(harness.backend.sessionCount, 1);
      expect((await newLog().entries()).map((e) => e.network), everyElement('unknown'));
    });

    test('syncing still works when the log cannot be written', () async {
      final broken = SyncLog(fileProvider: () async => File('${dir.path}/missing_dir/sync_log.jsonl'));
      final harness = await SyncHarness.create(syncLog: broken);
      addTearDown(harness.dispose);
      final outingId = await harness.insertOuting(localId: 'o-1');

      expect(await harness.sync.uploadFieldOuting(outingId), isNotNull);
    });
  });
}

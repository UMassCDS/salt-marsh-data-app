import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mass_marsh_app/services/app_version_interceptor.dart';
import '../support/fake_backend.dart';
import '../support/sync_harness.dart';

void main() {
  setUpAll(useInMemorySqlite);

  Dio dioWith(FakeBackend backend, Future<String> Function() loadVersion) =>
      Dio()
        ..httpClientAdapter = backend
        ..interceptors.add(AppVersionInterceptor(loadVersion: loadVersion));

  test('every request carries the app version', () async {
    final backend = FakeBackend();
    final dio = dioWith(backend, () async => '0.8.0+12');

    await dio.post('/api/mobile/sync-status', data: {'local_ids': <String>[]});
    await dio.post('/api/mobile/sync-status', data: {'local_ids': <String>[]});

    expect(backend.requests.map((r) => r.headers[appVersionHeader]), ['0.8.0+12', '0.8.0+12']);
  });

  test('the version is read once, not on every request', () async {
    var loads = 0;
    final dio = dioWith(FakeBackend(), () async {
      loads++;
      return '0.8.0+12';
    });

    for (var i = 0; i < 3; i++) {
      await dio.post('/api/mobile/sync-status', data: {'local_ids': <String>[]});
    }

    expect(loads, 1);
  });

  test('a version that cannot be read never blocks the request', () async {
    final backend = FakeBackend();
    final dio = dioWith(backend, () async => throw Exception('platform channel unavailable'));

    final response = await dio.post('/api/mobile/sync-status', data: {'local_ids': <String>[]});

    expect(response.statusCode, 200);
    expect(backend.requests.single.headers.containsKey(appVersionHeader), isFalse);
  });

  test('sync requests carry the version', () async {
    final harness = await SyncHarness.create();
    addTearDown(harness.dispose);
    final outingId = await harness.insertOuting(localId: 'o-1');

    await harness.sync.uploadFieldOuting(outingId);

    expect(harness.backend.requests, isNotEmpty);
    expect(harness.backend.requests.map((r) => r.headers[appVersionHeader]), everyElement('test'));
  });
}

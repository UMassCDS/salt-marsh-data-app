import 'package:flutter_test/flutter_test.dart';
import '../support/sync_harness.dart';

void main() {
  setUpAll(useInMemorySqlite);

  late SyncHarness harness;

  setUp(() async => harness = await SyncHarness.create());
  tearDown(() => harness.dispose());

  test('uploads an outing and records server ids on the outing and every plot', () async {
    final outingId = await harness.insertOuting(localId: 'outing-1');

    final serverId = await harness.sync.uploadFieldOuting(outingId);

    expect(serverId, isNotNull);
    final outing = await harness.outing(outingId);
    expect(outing['sync_status'], 'synced');
    expect(outing['server_id'], serverId);
    final plots = await harness.vegetation(outingId);
    expect(plots.map((p) => p['sync_status']), everyElement('synced'));
    expect(plots.map((p) => p['server_id']), everyElement(isNotNull));
    expect(harness.backend.sessionCount, 1);
  });

  test('does nothing while offline', () async {
    harness.connectivity.set([]);
    final outingId = await harness.insertOuting(localId: 'outing-1');

    expect(await harness.sync.uploadFieldOuting(outingId), isNull);

    expect(harness.backend.requests, isEmpty);
    expect((await harness.outing(outingId))['sync_status'], 'pending');
  });
}

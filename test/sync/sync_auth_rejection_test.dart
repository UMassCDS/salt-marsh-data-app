import 'package:flutter_test/flutter_test.dart';
import 'package:mass_marsh_app/services/auth_rejection.dart';
import '../support/fake_backend.dart';
import '../support/sync_harness.dart';

const syncStatusPath = '/api/mobile/sync-status';

void main() {
  setUpAll(useInMemorySqlite);

  late AuthRejections rejections;
  late int reported;

  setUp(() {
    rejections = AuthRejections();
    reported = 0;
    rejections.stream.listen((_) => reported++);
  });

  Future<SyncHarness> signedInWith(List<Fault> faults) async {
    final harness = await SyncHarness.create(faults: faults, authRejections: rejections);
    addTearDown(harness.dispose);
    harness.sync.setAuthToken('expired-token');
    return harness;
  }

  List<Fault> unauthorizedFor(int attempts, {FaultKind kind = FaultKind.unauthorized}) => [
        for (var i = 1; i <= attempts; i++) Fault(method: 'POST', path: syncStatusPath, occurrence: i, kind: kind),
      ];

  Future<void> pump() => Future<void>.delayed(Duration.zero);

  test('a 401 while holding a token is reported and loses no data', () async {
    final harness = await signedInWith(unauthorizedFor(1));
    final outingId = await harness.insertOuting(localId: 'o-1');

    expect(await harness.sync.uploadFieldOuting(outingId), isNull);
    await pump();

    expect(reported, 1);
    expect((await harness.outing(outingId))['sync_status'], 'pending');
    expect((await harness.vegetation(outingId)), hasLength(2));
    expect(harness.backend.sessionCount, 0);
  });

  test('repeated 401s are reported once, so the user is not signed out over and over', () async {
    final harness = await signedInWith(unauthorizedFor(3));
    final outingId = await harness.insertOuting(localId: 'o-1');

    for (var i = 0; i < 3; i++) {
      await harness.sync.uploadFieldOuting(outingId);
    }
    await pump();

    expect(reported, 1);
  });

  test('after signing in again, the next 401 is reported again', () async {
    final harness = await signedInWith(unauthorizedFor(2));
    final outingId = await harness.insertOuting(localId: 'o-1');
    await harness.sync.uploadFieldOuting(outingId);

    harness.sync.setAuthToken('fresh-token');
    await harness.sync.uploadFieldOuting(outingId);
    await pump();

    expect(reported, 2);
  });

  test('a 403 (not allowed to upload) does not sign the user out', () async {
    final harness = await signedInWith(unauthorizedFor(1, kind: FaultKind.forbidden));
    final outingId = await harness.insertOuting(localId: 'o-1');

    await harness.sync.uploadFieldOuting(outingId);
    await pump();

    expect(reported, 0);
    expect((await harness.outing(outingId))['sync_status'], 'pending');
  });

  test('a 401 with no token held is not a session to expire', () async {
    final harness = await SyncHarness.create(faults: unauthorizedFor(1), authRejections: rejections);
    addTearDown(harness.dispose);
    final outingId = await harness.insertOuting(localId: 'o-1');

    await harness.sync.uploadFieldOuting(outingId);
    await pump();

    expect(reported, 0);
  });

  test('once signed in again, the outing uploads normally', () async {
    final harness = await signedInWith(unauthorizedFor(1));
    final outingId = await harness.insertOuting(localId: 'o-1');
    await harness.sync.uploadFieldOuting(outingId);

    harness.sync.setAuthToken('fresh-token');

    expect(await harness.sync.uploadFieldOuting(outingId), isNotNull);
    expect((await harness.outing(outingId))['sync_status'], 'synced');
  });

  test('other failures never count as a rejected session', () async {
    final harness = await signedInWith([
      const Fault(method: 'POST', path: syncStatusPath, kind: FaultKind.serverError),
      const Fault(method: 'POST', path: syncStatusPath, occurrence: 2, kind: FaultKind.dropBeforeServer),
    ]);
    final outingId = await harness.insertOuting(localId: 'o-1');

    await harness.sync.uploadFieldOuting(outingId);
    await harness.sync.uploadFieldOuting(outingId);
    await pump();

    expect(reported, 0);
  });
}

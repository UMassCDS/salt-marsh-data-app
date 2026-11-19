import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:mass_marsh_app/models/field_outing/additional_photo.dart';
import '../support/fake_backend.dart';
import '../support/sync_harness.dart';

final extraPhotoPath = RegExp(r'^/api/mobile/vegetation-records/\d+/additional-photos$');

void main() {
  setUpAll(useInMemorySqlite);

  late SyncHarness harness;

  Future<int> outingWithTwoExtraPhotos({List<Fault> faults = const []}) async {
    harness = await SyncHarness.create(faults: faults);
    addTearDown(harness.dispose);
    final photos = [await writeTempPhoto(), await writeTempPhoto()];
    return harness.insertOuting(localId: 'o-1', additionalPhotosForFirstPlot: photos);
  }

  Future<List<AdditionalPhoto>> localExtras(int outingId) async =>
      decodeAdditionalPhotos((await harness.vegetation(outingId)).first['additional_photos']);

  Map<String, String> serverExtras() => harness.backend.additionalPhotosByVegetationId[harness.backend.serverPlotId('o-1', 'o-1-veg-1')] ?? {};

  test('additional photos reach the server after the outing and are marked done on the tablet', () async {
    final outingId = await outingWithTwoExtraPhotos();

    await harness.sync.uploadAllPendingOutings();

    expect(serverExtras().keys, ['o-1-extra-0', 'o-1-extra-1']);
    expect((await localExtras(outingId)).map((p) => p.url), everyElement(isNotNull));
    expect(await harness.sync.getPendingPhotoUploadsCount(), 0);
  });

  test('a failed upload stays pending, is counted, and goes on the next sync without duplicates', () async {
    final outingId = await outingWithTwoExtraPhotos(faults: [
      Fault(method: 'POST', path: extraPhotoPath, kind: FaultKind.dropBeforeServer),
    ]);

    await harness.sync.uploadAllPendingOutings();
    expect(serverExtras(), hasLength(1));
    expect((await localExtras(outingId)).where((p) => p.url == null), hasLength(1));
    expect(await harness.sync.getPendingPhotoUploadsCount(), 1);

    await harness.sync.uploadAllPendingOutings();
    expect(serverExtras(), hasLength(2));
    expect(await harness.sync.getPendingPhotoUploadsCount(), 0);
  });

  test('a reply lost after the server saved the photo does not add it twice', () async {
    await outingWithTwoExtraPhotos(faults: [
      Fault(method: 'POST', path: extraPhotoPath, kind: FaultKind.loseResponseAfterCommit),
    ]);

    await harness.sync.uploadAllPendingOutings();
    await harness.sync.uploadAllPendingOutings();

    expect(serverExtras(), hasLength(2));
  });

  test('plots without additional photos send nothing extra', () async {
    harness = await SyncHarness.create();
    addTearDown(harness.dispose);
    await harness.insertOuting(localId: 'o-1');

    await harness.sync.uploadAllPendingOutings();

    expect(harness.backend.additionalPhotosByVegetationId, isEmpty);
  });

  test('the saved list survives a round trip and a broken value is ignored', () {
    final photos = [AdditionalPhoto(localId: 'a', path: '/p/a.jpg'), AdditionalPhoto(localId: 'b', path: '/p/b.jpg', url: 'https://x/b.jpg')];
    final decoded = decodeAdditionalPhotos(encodeAdditionalPhotos(photos));
    expect([for (final p in decoded) (p.localId, p.path, p.url)], [('a', '/p/a.jpg', null), ('b', '/p/b.jpg', 'https://x/b.jpg')]);
    expect(encodeAdditionalPhotos([]), isNull);
    expect(decodeAdditionalPhotos('not json'), isEmpty);
    expect(decodeAdditionalPhotos(jsonEncode([])), isEmpty);
  });
}

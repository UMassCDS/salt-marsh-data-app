import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import '../support/payload_scenarios.dart';
import '../support/sync_harness.dart';

final currentDir = Directory('test/fixtures/payloads/current');
final updating = Platform.environment['UPDATE_PAYLOADS'] == '1';

Object? _sorted(Object? value) {
  if (value is Map) {
    return {for (final key in (value.keys.toList()..sort())) key: _sorted(value[key])};
  }
  if (value is List) return value.map(_sorted).toList();
  return value;
}

String canonicalJson(Object? payload) => '${const JsonEncoder.withIndent('  ').convert(_sorted(payload))}\n';

void main() {
  setUpAll(useInMemorySqlite);

  for (final scenario in payloadScenarios) {
    test('${scenario.name}: the outing upload body matches the saved payload', () async {
      final harness = await SyncHarness.create();
      addTearDown(harness.dispose);
      final photo = await writeTempPhoto();
      final outingId = await scenario.seed(harness, photo);

      expect(await harness.sync.uploadFieldOuting(outingId), isNotNull);

      final upload = harness.backend.requests.singleWhere(
        (r) => r.method == 'POST' && r.path == '/api/mobile/field-outings' && r.reachedServer,
      );
      final actual = canonicalJson(upload.data);
      final file = File('${currentDir.path}/${scenario.name}.json');

      if (updating) {
        await file.create(recursive: true);
        await file.writeAsString(actual);
        return;
      }
      expect(file.existsSync(), isTrue, reason: 'No saved payload. Run: UPDATE_PAYLOADS=1 flutter test test/contracts');
      expect(actual, await file.readAsString(), reason: 'The upload body changed. If intended: UPDATE_PAYLOADS=1 flutter test test/contracts');
    });
  }

  test('every saved payload has a scenario that produces it', () {
    final saved = currentDir.existsSync()
        ? currentDir.listSync().whereType<File>().map((f) => f.uri.pathSegments.last.replaceAll('.json', '')).toSet()
        : <String>{};

    expect(saved, payloadScenarios.map((s) => s.name).toSet());
  });
}

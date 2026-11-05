import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

final payloadsDir = Directory('test/fixtures/payloads');

Set<String> _names(Directory dir) =>
    dir.listSync().whereType<File>().where((f) => f.path.endsWith('.json')).map((f) => f.uri.pathSegments.last).toSet();

void main() {
  final frozen = payloadsDir.listSync().whereType<Directory>().where((d) => d.uri.pathSegments.reversed.skip(1).first.startsWith('v'));
  final currentNames = _names(Directory('${payloadsDir.path}/current'));

  test('at least the v0.7.0 payloads are kept', () {
    expect(frozen.map((d) => d.uri.pathSegments.reversed.skip(1).first), contains('v0.7.0'));
  });

  for (final dir in frozen) {
    final version = dir.uri.pathSegments.reversed.skip(1).first;

    test('$version covers every scenario and each file is a valid upload body', () {
      expect(_names(dir), currentNames);
      for (final file in dir.listSync().whereType<File>().where((f) => f.path.endsWith('.json'))) {
        final body = jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
        expect(body, containsPair('org_id', isA<int>()), reason: file.path);
        expect(body['local_id'], isA<String>(), reason: file.path);
        expect(body['vegetation_records'], isA<List>(), reason: file.path);
      }
    });
  }

  test('v0.7.0 vegetation records have no GPS accuracy fields, as that release did not send them', () {
    for (final file in Directory('${payloadsDir.path}/v0.7.0').listSync().whereType<File>().where((f) => f.path.endsWith('.json'))) {
      final body = jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
      for (final plot in (body['vegetation_records'] as List).cast<Map<String, dynamic>>()) {
        expect(plot.containsKey('accuracy_m'), isFalse, reason: file.path);
        expect(plot.containsKey('location_quality'), isFalse, reason: file.path);
      }
    }
  });
}

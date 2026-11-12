import 'dart:convert';
import 'dart:typed_data';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mass_marsh_app/services/update_check.dart';

class _FakeGitHub implements HttpClientAdapter {
  _FakeGitHub(this.reply);
  final Object reply;
  int calls = 0;

  @override
  Future<ResponseBody> fetch(RequestOptions options, Stream<Uint8List>? requestStream, Future<void>? cancelFuture) async {
    calls++;
    if (reply is DioExceptionType) throw DioException(requestOptions: options, type: reply as DioExceptionType);
    return ResponseBody.fromString(jsonEncode(reply), 200, headers: {
      Headers.contentTypeHeader: ['application/json'],
    });
  }

  @override
  void close({bool force = false}) {}
}

const release = {'tag_name': 'v0.8.0', 'html_url': 'https://github.com/UMassCDS/salt-marsh-data-app/releases/tag/v0.8.0'};

void main() {
  group('compareVersions', () {
    for (final (a, b, expected) in [
      ('v0.8.0', '0.7.0+11', 1),
      ('v0.7.0', '0.7.0+11', 0),
      ('0.7.1', 'v0.7.0', 1),
      ('v0.10.0', '0.9.9', 1),
      ('v1.0.0', '0.12.3+40', 1),
      ('v0.7.0', '0.8.0+12', -1),
    ]) {
      test('$a vs $b', () => expect(compareVersions(a, b).sign, expected));
    }
  });

  late Map<String, String> stored;

  UpdateChecker checker(Object reply, {String installed = '0.7.0+11', bool enabled = true}) {
    final dio = Dio()..httpClientAdapter = _FakeGitHub(reply);
    return UpdateChecker(
      dio: dio,
      installedVersion: () async => installed,
      readDismissed: () async => stored['dismissed'],
      writeDismissed: (v) async => stored['dismissed'] = v,
      enabled: enabled,
    );
  }

  setUp(() => stored = {});

  test('a newer release is offered with its page', () async {
    final update = await checker(release).check();
    expect(update?.version, '0.8.0');
    expect(update?.url, release['html_url']);
  });

  test('nothing is offered when the installed version is current or newer', () async {
    expect(await checker(release, installed: '0.8.0+12').check(), isNull);
    expect(await checker(release, installed: '0.9.0+13').check(), isNull);
  });

  test('a dismissed release is not offered again, but a newer one is', () async {
    await checker(release).dismiss('0.8.0');
    expect(await checker(release).check(), isNull);
    expect((await checker({...release, 'tag_name': 'v0.9.0'}).check())?.version, '0.9.0');
  });

  test('offline or a bad reply never shows anything and never throws', () async {
    expect(await checker(DioExceptionType.connectionError).check(), isNull);
    expect(await checker({'message': 'API rate limit exceeded'}).check(), isNull);
  });

  test('dev builds never ask', () async {
    final adapter = _FakeGitHub(release);
    final dio = Dio()..httpClientAdapter = adapter;
    final dev = UpdateChecker(dio: dio, installedVersion: () async => '0.7.0+11', enabled: false);
    expect(await dev.check(), isNull);
    expect(adapter.calls, 0);
  });
}

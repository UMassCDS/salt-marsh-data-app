import 'dart:convert';
import 'dart:typed_data';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mass_marsh_app/services/update_check.dart';

class _FakeGitHub implements HttpClientAdapter {
  Object reply = release;
  int calls = 0;

  @override
  Future<ResponseBody> fetch(RequestOptions options, Stream<Uint8List>? requestStream, Future<void>? cancelFuture) async {
    calls++;
    final current = reply;
    if (current is DioExceptionType) throw DioException(requestOptions: options, type: current);
    return ResponseBody.fromString(jsonEncode(current), 200, headers: {
      Headers.contentTypeHeader: ['application/json'],
    });
  }

  @override
  void close({bool force = false}) {}
}

const release = {'tag_name': 'v0.8.0', 'html_url': 'https://github.com/UMassCDS/salt-marsh-data-app/releases/tag/v0.8.0'};
const offline = DioExceptionType.connectionError;

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

  late _FakeGitHub github;
  late String? saved;
  late DateTime clock;

  UpdateChecker checker({String installed = '0.7.0+11', bool enabled = true}) => UpdateChecker(
        dio: Dio()..httpClientAdapter = github,
        installedVersion: () async => installed,
        loadState: () async => saved == null ? UpdateCheckState() : UpdateCheckState.fromJson(jsonDecode(saved!) as Map<String, dynamic>),
        saveState: (s) async => saved = jsonEncode(s.toJson()),
        now: () => clock,
        enabled: enabled,
      );

  setUp(() {
    github = _FakeGitHub();
    saved = null;
    clock = DateTime(2026, 11, 12, 9);
  });

  test('a newer release is offered with its page', () async {
    final update = await checker().check();
    expect(update?.version, '0.8.0');
    expect(update?.url, release['html_url']);
  });

  test('nothing is offered when the installed version is current or newer', () async {
    expect(await checker(installed: '0.8.0+12').check(), isNull);
    expect(await checker(installed: '0.9.0+13').check(), isNull);
  });

  test('asks GitHub at most once a day and uses the saved answer in between', () async {
    await checker().check();
    clock = clock.add(const Duration(hours: 23));
    github.reply = {...release, 'tag_name': 'v0.9.0'};

    expect((await checker().check())?.version, '0.8.0');
    expect(github.calls, 1);

    clock = clock.add(const Duration(hours: 2));
    expect((await checker().check())?.version, '0.9.0');
    expect(github.calls, 2);
  });

  test('fully offline: a known update is still shown from the saved answer', () async {
    await checker().check();
    clock = clock.add(const Duration(days: 3));
    github.reply = offline;

    expect((await checker().check())?.version, '0.8.0');
  });

  test('fully offline with nothing saved: no banner and no error', () async {
    github.reply = offline;
    expect(await checker().check(), isNull);
    github.reply = {'message': 'API rate limit exceeded'};
    expect(await checker().check(), isNull);
  });

  test('a failed check is retried on the next launch instead of waiting a day', () async {
    github.reply = offline;
    await checker().check();
    github.reply = release;
    expect((await checker().check())?.version, '0.8.0');
    expect(github.calls, 2);
  });

  test('a dismissed release is not offered again, but a newer one is', () async {
    await checker().dismiss('0.8.0');
    expect(await checker().check(), isNull);

    clock = clock.add(const Duration(days: 1));
    github.reply = {...release, 'tag_name': 'v0.9.0'};
    expect((await checker().check())?.version, '0.9.0');
  });

  test('dev builds never ask', () async {
    expect(await checker(enabled: false).check(), isNull);
    expect(github.calls, 0);
  });
}

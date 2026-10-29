import 'dart:convert';
import 'dart:typed_data';
import 'package:dio/dio.dart';

enum FaultKind {
  dropBeforeServer,
  loseResponseAfterCommit,
  serverError,
}

class Fault {
  final String method;
  final Pattern path;
  final int occurrence;
  final FaultKind kind;
  final DioExceptionType dioType;

  const Fault({
    required this.method,
    required this.path,
    this.occurrence = 1,
    required this.kind,
    this.dioType = DioExceptionType.connectionError,
  });

  bool matches(String requestMethod, String requestPath, int count) =>
      method == requestMethod && path.allMatches(requestPath).isNotEmpty && occurrence == count;
}

class ServerSession {
  final int id;
  final String localId;
  final Map<String, dynamic> payload;
  final Map<String, int> vegetation;
  final Map<String, int> hydrology;
  final Map<String, int> elevation;

  ServerSession(this.id, this.localId, this.payload, this.vegetation, this.hydrology, this.elevation);
}

class RecordedRequest {
  final String method;
  final String path;
  final dynamic data;
  final bool reachedServer;

  RecordedRequest(this.method, this.path, this.data, this.reachedServer);
}

// Mirrors the real backend: field-outings is idempotent per local_id and sync-status matches exactly
class FakeBackend implements HttpClientAdapter {
  final List<Fault> faults;
  final Map<String, ServerSession> sessionsByLocalId = {};
  final Map<int, String> photoUrlByVegetationId = {};
  final List<RecordedRequest> requests = [];
  final List<String> uploadedPhotos = [];
  final Map<String, int> _callCounts = {};
  int _nextId = 100;

  FakeBackend({this.faults = const []});

  int get sessionCount => sessionsByLocalId.length;

  int callsTo(String method, Pattern path) =>
      requests.where((r) => r.method == method && path.allMatches(r.path).isNotEmpty).length;

  int serverCommitsTo(String method, Pattern path) => requests
      .where((r) => r.reachedServer && r.method == method && path.allMatches(r.path).isNotEmpty)
      .length;

  @override
  void close({bool force = false}) {}

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    final method = options.method;
    final path = options.path;
    final key = '$method $path';
    final count = _callCounts.update(key, (c) => c + 1, ifAbsent: () => 1);
    final fault = faults.where((f) => f.matches(method, path, count)).firstOrNull;

    if (fault?.kind == FaultKind.dropBeforeServer) {
      requests.add(RecordedRequest(method, path, options.data, false));
      throw DioException(requestOptions: options, type: fault!.dioType, message: 'injected: dropped before server');
    }
    if (fault?.kind == FaultKind.serverError) {
      requests.add(RecordedRequest(method, path, options.data, false));
      return _json({'detail': 'injected server error'}, 500);
    }

    requests.add(RecordedRequest(method, path, options.data, true));
    final response = await _handle(method, path, options);

    if (fault?.kind == FaultKind.loseResponseAfterCommit) {
      throw DioException(requestOptions: options, type: fault!.dioType, message: 'injected: response lost after commit');
    }
    return response;
  }

  Future<ResponseBody> _handle(String method, String path, RequestOptions options) async {
    if (method == 'POST' && path == '/api/mobile/sync-status') {
      final ids = (options.data['local_ids'] as List).cast<String>();
      return _json({
        'success': true,
        'records': {
          for (final id in ids)
            id: sessionsByLocalId.containsKey(id)
                ? {'synced': true, 'server_id': sessionsByLocalId[id]!.id, 'approval_status': 'pending'}
                : {'synced': false},
        },
      });
    }

    if (method == 'POST' && path == '/api/mobile/field-outings') {
      final body = Map<String, dynamic>.from(options.data as Map);
      final localId = body['local_id'] as String;
      final existing = sessionsByLocalId[localId];
      if (existing != null) return _json(_uploadResponse(existing, 'Field session already uploaded.'));

      Map<String, int> assign(String key) => {
            for (final record in (body[key] as List? ?? []))
              (record as Map)['local_id'] as String: _nextId++,
          };
      final session = ServerSession(
        _nextId++, localId, body, assign('vegetation_records'), assign('hydrology_records'), assign('elevation_records'),
      );
      sessionsByLocalId[localId] = session;
      return _json(_uploadResponse(session, 'Field session uploaded successfully.'));
    }

    if (method == 'POST' && path == '/api/mobile/photos') {
      final url = 'https://fake.blob.local/photos/${uploadedPhotos.length + 1}.jpg';
      uploadedPhotos.add(url);
      return _json({'success': true, 'url': url});
    }

    final photoUpdate = RegExp(r'^/api/mobile/vegetation-records/(\d+)/photo$').firstMatch(path);
    if (method == 'PUT' && photoUpdate != null) {
      photoUrlByVegetationId[int.parse(photoUpdate.group(1)!)] = options.data['photo_url'] as String;
      return _json({'success': true});
    }

    return _json({'detail': 'FakeBackend has no route for $method $path'}, 404);
  }

  Map<String, dynamic> _uploadResponse(ServerSession s, String message) => {
        'success': true,
        'server_id': s.id,
        'source_id': 'mobile-${s.localId}',
        'child_records': {'vegetation': s.vegetation, 'hydrology': s.hydrology, 'elevation': s.elevation},
        'approval_status': 'pending',
        'message': message,
      };

  ResponseBody _json(Map<String, dynamic> body, [int status = 200]) => ResponseBody.fromString(
        jsonEncode(body),
        status,
        headers: {
          Headers.contentTypeHeader: ['application/json'],
        },
      );
}

import 'dart:typed_data';
import 'package:dio/dio.dart';
import 'package:dio/io.dart';

// Forwards the request to the real server, then drops the reply for chosen calls, as a weak connection does
class LostReplyAdapter implements HttpClientAdapter {
  LostReplyAdapter({required this.method, required this.pathContains, this.occurrence = 1});

  final String method;
  final String pathContains;
  final int occurrence;
  final IOHttpClientAdapter _real = IOHttpClientAdapter();
  int _seen = 0;
  int committed = 0;

  @override
  Future<ResponseBody> fetch(RequestOptions options, Stream<Uint8List>? requestStream, Future<void>? cancelFuture) async {
    final response = await _real.fetch(options, requestStream, cancelFuture);
    final matches = options.method == method && options.path.contains(pathContains);
    if (matches && ++_seen == occurrence) {
      committed++;
      throw DioException(requestOptions: options, type: DioExceptionType.connectionError, message: 'reply lost after the server saved the data');
    }
    return response;
  }

  @override
  void close({bool force = false}) => _real.close(force: force);
}

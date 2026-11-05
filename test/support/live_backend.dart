import 'package:dio/dio.dart';

// Plain HTTP client for checking what a real backend stored, independent of the app's own sync code
class LiveBackend {
  LiveBackend(String baseUrl) : _dio = Dio(BaseOptions(baseUrl: baseUrl, validateStatus: (_) => true));

  final Dio _dio;

  Future<String> login(String email, String password) async {
    final response = await _dio.post('/api/v1/auth/login', data: {'email': email, 'password': password});
    if (response.statusCode != 200) throw StateError('Login failed for $email: ${response.statusCode} ${response.data}');
    return response.data['access_token'] as String;
  }

  Options _as(String token) => Options(headers: {'Authorization': 'Bearer $token'});

  Future<int> firstOrganizationId(String token) async {
    final response = await _dio.get('/api/mobile/organizations', options: _as(token));
    return (response.data['organizations'] as List).first['id'] as int;
  }

  Future<List<Map<String, dynamic>>> sessions(String token, int orgId) async {
    final response = await _dio.get('/api/v1/orgs/$orgId/sessions', options: _as(token));
    if (response.statusCode != 200) throw StateError('Listing sessions failed: ${response.statusCode} ${response.data}');
    return (response.data['sessions'] as List).cast<Map<String, dynamic>>();
  }

  Future<void> deleteSession(String token, int orgId, int sessionId) async {
    final response = await _dio.delete('/api/v1/orgs/$orgId/sessions/$sessionId', options: _as(token));
    if (response.statusCode != 200) throw StateError('Deleting session $sessionId failed: ${response.statusCode} ${response.data}');
  }

  Future<Map<String, dynamic>> syncStatus(String token, List<String> localIds) async {
    final response = await _dio.post('/api/mobile/sync-status', data: {'local_ids': localIds}, options: _as(token));
    return (response.data['records'] as Map).cast<String, dynamic>();
  }
}

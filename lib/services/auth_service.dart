import 'package:dio/dio.dart';
import '../models/user/user.dart';

const kApiBaseUrl = String.fromEnvironment('API_BASE_URL', defaultValue: 'https://saltmarshdata.org');

class AuthService {
  final Dio _dio;

  AuthService()
      : _dio = Dio(
          BaseOptions(
            baseUrl: kApiBaseUrl,
            connectTimeout: const Duration(seconds: 30),
            receiveTimeout: const Duration(seconds: 30),
            headers: {'Content-Type': 'application/json'},
          ),
        );

  /// POST /api/v1/auth/login
  /// Returns the JWT token and authenticated User.
  Future<({String token, User user})> login(
      String email, String password) async {
    final response = await _dio.post('/api/v1/auth/login', data: {
      'email': email,
      'password': password,
    });

    // A brand new login response never carries X-Refreshed-Token, since the
    // token it just issued is already at full freshness
    final token = response.data['access_token'] as String;
    final user = _userFromApiJson(response.data['user'] as Map<String, dynamic>);
    return (token: token, user: user);
  }

  /// GET /api/v1/auth/me - validates a stored token and returns the current user.
  /// refreshedToken is set when the server renewed the token on this request.
  Future<({User user, String? refreshedToken})> getMe(String token) async {
    final response = await _dio.get(
      '/api/v1/auth/me',
      options: Options(headers: {'Authorization': 'Bearer $token'}),
    );
    final user = _userFromApiJson(response.data as Map<String, dynamic>);
    return (user: user, refreshedToken: response.headers.value('x-refreshed-token'));
  }

  /// Maps the API's snake_case user JSON to the app's User model (camelCase).
  User _userFromApiJson(Map<String, dynamic> json) {
    return User(
      id: (json['id'] as num).toInt(),
      email: json['email'] as String,
      fullName: json['full_name'] as String,
      isActive: _parseBool(json['is_active']),
      isSuperadmin: _parseBool(json['is_superadmin']),
      createdAt: json['created_at'] != null
          ? DateTime.tryParse(json['created_at'] as String)
          : null,
      lastLogin: json['last_login'] != null
          ? DateTime.tryParse(json['last_login'] as String)
          : null,
    );
  }

  /// API may return booleans as int (0/1) or actual bool.
  bool _parseBool(dynamic value) {
    if (value is bool) return value;
    if (value is int) return value == 1;
    return false;
  }
}

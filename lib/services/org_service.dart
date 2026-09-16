import 'package:dio/dio.dart';
import '../models/organization/organization.dart';
import 'auth_service.dart';

class OrgService {
  final Dio _dio;

  OrgService()
      : _dio = Dio(
          BaseOptions(
            baseUrl: kApiBaseUrl,
            connectTimeout: const Duration(seconds: 30),
            receiveTimeout: const Duration(seconds: 30),
            headers: {'Content-Type': 'application/json'},
          ),
        );

  /// GET /api/v1/auth/me/orgs - returns all organizations the current user belongs to.
  Future<List<Organization>> getMyOrgs(String token) async {
    final response = await _dio.get(
      '/api/v1/auth/me/orgs',
      options: Options(headers: {'Authorization': 'Bearer $token'}),
    );

    final List<dynamic> data = response.data as List<dynamic>;
    return data
        .map((json) => _orgFromApiJson(json as Map<String, dynamic>))
        .toList();
  }

  /// Maps snake_case API response to the Organization model.
  Organization _orgFromApiJson(Map<String, dynamic> json) {
    return Organization(
      id: (json['id'] as num).toInt(),
      name: json['name'] as String,
      slug: json['slug'] as String,
      description: json['description'] as String?,
      contactEmail: json['contact_email'] as String?,
      isActive: json['is_active'] as bool? ?? true,
      userRole: (json['user_role'] ?? json['role'] ?? 'viewer') as String,
      defaultVisibility: (json['default_visibility'] ?? 'public') as String,
      memberCount: (json['member_count'] as num?)?.toInt(),
      createdAt: json['created_at'] != null
          ? DateTime.tryParse(json['created_at'] as String)
          : null,
    );
  }
}

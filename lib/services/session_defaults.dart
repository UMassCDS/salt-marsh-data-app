import 'dart:convert';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class SessionDefaults {
  const SessionDefaults({this.siteName, this.otherMembers});
  final String? siteName;
  final String? otherMembers;
}

// Remembers the last submitted site and team per org so the next session starts pre-filled
class SessionDefaultsStore {
  SessionDefaultsStore({Future<String?> Function(String key)? read, Future<void> Function(String key, String value)? write})
      : _read = read ?? ((key) => const FlutterSecureStorage().read(key: key)),
        _write = write ?? ((key, value) => const FlutterSecureStorage().write(key: key, value: value));

  final Future<String?> Function(String key) _read;
  final Future<void> Function(String key, String value) _write;

  static String _key(int? orgId) => 'session_defaults_${orgId ?? 'none'}';

  Future<SessionDefaults> load(int? orgId) async {
    try {
      final raw = await _read(_key(orgId));
      if (raw == null) return const SessionDefaults();
      final json = jsonDecode(raw) as Map<String, dynamic>;
      return SessionDefaults(siteName: json['site_name'] as String?, otherMembers: json['other_members'] as String?);
    } catch (_) {
      return const SessionDefaults();
    }
  }

  Future<void> save(int? orgId, {required String siteName, String? otherMembers}) async {
    try {
      await _write(_key(orgId), jsonEncode({'site_name': siteName.trim(), 'other_members': otherMembers?.trim()}));
    } catch (_) {}
  }
}

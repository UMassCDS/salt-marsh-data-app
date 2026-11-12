import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import '../config/env.dart';
import 'app_version_interceptor.dart';

const latestReleaseUrl = 'https://api.github.com/repos/UMassCDS/salt-marsh-data-app/releases/latest';
const _dismissedKey = 'dismissed_update_version';

List<int> _versionParts(String version) {
  final core = version.replaceFirst(RegExp(r'^v'), '').split('+').first;
  return core.split('.').map((p) => int.tryParse(p) ?? 0).toList();
}

// Compares release versions like "v0.8.0" and "0.7.0+11"; the build number is ignored
int compareVersions(String a, String b) {
  final left = _versionParts(a);
  final right = _versionParts(b);
  for (var i = 0; i < 3; i++) {
    final diff = (i < left.length ? left[i] : 0) - (i < right.length ? right[i] : 0);
    if (diff != 0) return diff;
  }
  return 0;
}

class AvailableUpdate {
  const AvailableUpdate(this.version, this.url);
  final String version;
  final String url;
}

class UpdateChecker {
  UpdateChecker({
    Dio? dio,
    Future<String> Function()? installedVersion,
    Future<String?> Function()? readDismissed,
    Future<void> Function(String)? writeDismissed,
    this.enabled = !kIsDevFlavor,
  })  : _dio = dio ?? Dio(BaseOptions(connectTimeout: const Duration(seconds: 10), receiveTimeout: const Duration(seconds: 10))),
        _installedVersion = installedVersion ?? platformAppVersion,
        _readDismissed = readDismissed ?? (() => const FlutterSecureStorage().read(key: _dismissedKey)),
        _writeDismissed = writeDismissed ?? ((v) => const FlutterSecureStorage().write(key: _dismissedKey, value: v));

  final Dio _dio;
  final Future<String> Function() _installedVersion;
  final Future<String?> Function() _readDismissed;
  final Future<void> Function(String) _writeDismissed;
  final bool enabled;

  // Any failure means "no banner": an update hint must never get in the way of field work
  Future<AvailableUpdate?> check() async {
    if (!enabled) return null;
    try {
      final reply = await _dio.get<Map<String, dynamic>>(latestReleaseUrl);
      final tag = reply.data?['tag_name'] as String?;
      final url = reply.data?['html_url'] as String?;
      if (tag == null || url == null) return null;
      final latest = tag.replaceFirst(RegExp(r'^v'), '');
      if (compareVersions(latest, await _installedVersion()) <= 0) return null;
      if (await _readDismissed() == latest) return null;
      return AvailableUpdate(latest, url);
    } catch (_) {
      return null;
    }
  }

  Future<void> dismiss(String version) => _writeDismissed(version);
}

final updateCheckerProvider = Provider<UpdateChecker>((ref) => UpdateChecker());

final availableUpdateProvider = FutureProvider<AvailableUpdate?>((ref) => ref.watch(updateCheckerProvider).check());

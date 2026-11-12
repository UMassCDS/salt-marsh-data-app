import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import '../config/env.dart';
import 'app_version_interceptor.dart';

const latestReleaseUrl = 'https://api.github.com/repos/UMassCDS/salt-marsh-data-app/releases/latest';
const _stateKey = 'update_check_state';

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

// What the last successful check found, kept on the device so most launches need no network at all
class UpdateCheckState {
  UpdateCheckState({this.checkedAt, this.latestVersion, this.url, this.dismissed});

  DateTime? checkedAt;
  String? latestVersion;
  String? url;
  String? dismissed;

  factory UpdateCheckState.fromJson(Map<String, dynamic> json) => UpdateCheckState(
        checkedAt: DateTime.tryParse(json['checked_at'] as String? ?? ''),
        latestVersion: json['latest_version'] as String?,
        url: json['url'] as String?,
        dismissed: json['dismissed'] as String?,
      );

  Map<String, dynamic> toJson() => {
        'checked_at': checkedAt?.toIso8601String(),
        'latest_version': latestVersion,
        'url': url,
        'dismissed': dismissed,
      };
}

Future<UpdateCheckState> _loadFromSecureStorage() async {
  final raw = await const FlutterSecureStorage().read(key: _stateKey);
  return raw == null ? UpdateCheckState() : UpdateCheckState.fromJson(jsonDecode(raw) as Map<String, dynamic>);
}

Future<void> _saveToSecureStorage(UpdateCheckState state) =>
    const FlutterSecureStorage().write(key: _stateKey, value: jsonEncode(state.toJson()));

class UpdateChecker {
  UpdateChecker({
    Dio? dio,
    Future<String> Function()? installedVersion,
    Future<UpdateCheckState> Function()? loadState,
    Future<void> Function(UpdateCheckState)? saveState,
    DateTime Function()? now,
    this.interval = const Duration(days: 1),
    this.enabled = !kIsDevFlavor,
  })  : _dio = dio ?? Dio(BaseOptions(connectTimeout: const Duration(seconds: 10), receiveTimeout: const Duration(seconds: 10))),
        _installedVersion = installedVersion ?? platformAppVersion,
        _loadState = loadState ?? _loadFromSecureStorage,
        _saveState = saveState ?? _saveToSecureStorage,
        _now = now ?? DateTime.now;

  final Dio _dio;
  final Future<String> Function() _installedVersion;
  final Future<UpdateCheckState> Function() _loadState;
  final Future<void> Function(UpdateCheckState) _saveState;
  final DateTime Function() _now;
  final Duration interval;
  final bool enabled;

  Future<UpdateCheckState> _state() async {
    try {
      return await _loadState();
    } catch (_) {
      return UpdateCheckState();
    }
  }

  // Any failure means "use what we already know": an update hint must never get in the way of field work
  Future<AvailableUpdate?> check() async {
    if (!enabled) return null;
    final state = await _state();
    final last = state.checkedAt;
    if (last == null || _now().difference(last) >= interval) {
      try {
        final reply = await _dio.get<Map<String, dynamic>>(latestReleaseUrl);
        final tag = reply.data?['tag_name'] as String?;
        final url = reply.data?['html_url'] as String?;
        if (tag != null && url != null) {
          state
            ..latestVersion = tag.replaceFirst(RegExp(r'^v'), '')
            ..url = url
            ..checkedAt = _now();
          await _saveState(state);
        }
      } catch (_) {
        // Offline or GitHub unavailable: keep the saved result and try again next launch
      }
    }
    final latest = state.latestVersion;
    final url = state.url;
    if (latest == null || url == null || latest == state.dismissed) return null;
    try {
      if (compareVersions(latest, await _installedVersion()) <= 0) return null;
    } catch (_) {
      return null;
    }
    return AvailableUpdate(latest, url);
  }

  Future<void> dismiss(String version) async {
    final state = await _state();
    state.dismissed = version;
    try {
      await _saveState(state);
    } catch (_) {}
  }
}

final updateCheckerProvider = Provider<UpdateChecker>((ref) => UpdateChecker());

final availableUpdateProvider = FutureProvider<AvailableUpdate?>((ref) => ref.watch(updateCheckerProvider).check());

import 'package:dio/dio.dart';
import 'package:package_info_plus/package_info_plus.dart';

const appVersionHeader = 'X-App-Version';

Future<String> platformAppVersion() async {
  final info = await PackageInfo.fromPlatform();
  return '${info.version}+${info.buildNumber}';
}

// Lets the backend see which app versions are still in use; a failure to read the version must never block a request
class AppVersionInterceptor extends Interceptor {
  AppVersionInterceptor({Future<String> Function()? loadVersion}) : _loadVersion = loadVersion ?? platformAppVersion;

  final Future<String> Function() _loadVersion;
  String? _version;

  @override
  Future<void> onRequest(RequestOptions options, RequestInterceptorHandler handler) async {
    try {
      _version ??= await _loadVersion();
      options.headers[appVersionHeader] = _version;
    } catch (_) {
      // Request goes out without the header; the backend logs it as "none"
    } finally {
      handler.next(options);
    }
  }
}

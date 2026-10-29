import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mass_marsh_app/models/user/user.dart';
import 'package:mass_marsh_app/providers/auth_provider.dart';
import 'package:mass_marsh_app/services/auth_cache.dart';
import 'package:mass_marsh_app/services/auth_rejection.dart';
import 'package:mass_marsh_app/services/auth_service.dart';

class _UnreachableServer implements AuthService {
  @override
  Future<({User user, String? refreshedToken})> getMe(String token) =>
      throw DioException(requestOptions: RequestOptions(path: '/me'), type: DioExceptionType.connectionError);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const user = User(id: 7, email: 'tech@example.test', fullName: 'Field Tech');

  setUp(() {
    final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(const MethodChannel('dev.fluttercommunity.plus/connectivity'), (_) async => ['none']);
    messenger.setMockMethodCallHandler(const MethodChannel('dev.fluttercommunity.plus/connectivity_status'), (_) async => null);
    FlutterSecureStorage.setMockInitialValues({
      AuthCache.tokenKey: 'expired-token',
      'cached_user': jsonEncode(user.toJson()),
      'cached_orgs': '[]',
    });
    AuthRejections.instance.rearm();
  });

  Future<ProviderContainer> signedInOffline() async {
    final container = ProviderContainer(overrides: [authServiceProvider.overrideWithValue(_UnreachableServer())]);
    addTearDown(container.dispose);
    container.listen(authProvider, (_, _) {});
    await container.read(authProvider.notifier).ready;
    await Future<void>.delayed(const Duration(milliseconds: 50));
    expect(container.read(authProvider).isAuthenticated, isTrue);
    return container;
  }

  test('a rejected session signs the user out with a message and clears the stored token', () async {
    final container = await signedInOffline();

    AuthRejections.instance.report();
    await Future<void>.delayed(const Duration(milliseconds: 50));

    final state = container.read(authProvider);
    expect(state.isAuthenticated, isFalse);
    expect(state.isInitialized, isTrue);
    expect(state.error, contains('session expired'));
    expect(state.error, contains('nothing on this device was lost'));
    expect(await const FlutterSecureStorage().read(key: AuthCache.tokenKey), isNull);
    expect(await AuthCache.readUser(), isNull);
  });

  test('a rejection while already signed out changes nothing', () async {
    FlutterSecureStorage.setMockInitialValues({});
    final container = ProviderContainer(overrides: [authServiceProvider.overrideWithValue(_UnreachableServer())]);
    addTearDown(container.dispose);
    container.listen(authProvider, (_, _) {});
    await container.read(authProvider.notifier).ready;
    await Future<void>.delayed(const Duration(milliseconds: 50));

    AuthRejections.instance.report();
    await Future<void>.delayed(const Duration(milliseconds: 50));

    expect(container.read(authProvider).error, isNull);
  });

  test('logging out still signs out without an error message', () async {
    final container = await signedInOffline();

    await container.read(authProvider.notifier).logout();

    final state = container.read(authProvider);
    expect(state.isAuthenticated, isFalse);
    expect(state.error, isNull);
  });
}

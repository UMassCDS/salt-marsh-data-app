import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../models/user/user.dart';
import '../services/app_logger.dart';
import '../services/auth_cache.dart';
import '../services/auth_service.dart';
import '../services/sync_service.dart';

class AuthState {
  final User? user;
  final String? token;
  final bool isLoading;

  /// True once the initial session-restore attempt has completed.
  final bool isInitialized;
  final String? error;

  /// True when the session was restored from the local cache and the
  /// server could not be reached to confirm it, so the user is signed
  /// in on a stale, offline copy of their account.
  final bool signedInOffline;

  const AuthState({
    this.user,
    this.token,
    this.isLoading = false,
    this.isInitialized = false,
    this.error,
    this.signedInOffline = false,
  });

  bool get isAuthenticated => token != null && user != null;

  AuthState copyWith({
    User? user,
    String? token,
    bool? isLoading,
    bool? isInitialized,
    String? error,
    bool clearError = false,
    bool clearUser = false,
    bool clearToken = false,
    bool? signedInOffline,
  }) {
    return AuthState(
      user: clearUser ? null : (user ?? this.user),
      token: clearToken ? null : (token ?? this.token),
      isLoading: isLoading ?? this.isLoading,
      isInitialized: isInitialized ?? this.isInitialized,
      error: clearError ? null : (error ?? this.error),
      signedInOffline: signedInOffline ?? this.signedInOffline,
    );
  }
}

class AuthNotifier extends Notifier<AuthState> {
  static const _tokenKey = AuthCache.tokenKey;
  static const _storage = FlutterSecureStorage();

  final _readyCompleter = Completer<void>();

  // Resolves once the token is known - not once the network confirms it, so
  // a dependent provider (org restore) never waits out a full Dio timeout
  // offline just to learn what it could already tell from the cache
  Future<void> get ready => _readyCompleter.future;

  void _markReady() {
    if (!_readyCompleter.isCompleted) _readyCompleter.complete();
  }

  @override
  AuthState build() {
    _tryRestoreSession();
    return const AuthState();
  }

  AuthService get _authService => ref.read(authServiceProvider);

  Future<void> _tryRestoreSession() async {
    final token = await _storage.read(key: _tokenKey);
    if (token == null) {
      appLogger.i('[auth] restore: no stored token, staying signed out');
      state = const AuthState(isInitialized: true);
      _markReady();
      return;
    }

    SyncService.instance.setAuthToken(token);

    // Hydrate from the last known user immediately, so a device with no
    // signal opens straight into the app instead of blocking on a request
    // that cannot complete. Confirmed against the server below, in the
    // background, once state has already let the user in.
    final cachedUser = await AuthCache.readUser();
    if (cachedUser != null) {
      appLogger.i('[auth] restore: hydrated from cache, user=${cachedUser.id}');
      state = AuthState(token: token, user: cachedUser, isInitialized: true);
      SyncService.instance.startAutoSync();
      _markReady();
    } else {
      appLogger.i('[auth] restore: token present but no cached user, waiting on network');
    }

    try {
      final result = await _authService.getMe(token);
      await AuthCache.saveUser(result.user);

      var currentToken = token;
      if (result.refreshedToken != null) {
        currentToken = result.refreshedToken!;
        await _storage.write(key: _tokenKey, value: currentToken);
        SyncService.instance.setAuthToken(currentToken);
      }

      appLogger.i('[auth] restore: network confirmed user=${result.user.id}');
      state = AuthState(
          token: currentToken, user: result.user, isInitialized: true);
      if (cachedUser == null) SyncService.instance.startAutoSync();
    } on DioException catch (e) {
      if (_isAuthRejection(e)) {
        appLogger.w('[auth] restore: server rejected token (${e.response?.statusCode}), signing out');
        await _storage.delete(key: _tokenKey);
        await AuthCache.clear();
        SyncService.instance.clearAuthToken();
        state = const AuthState(isInitialized: true);
        return;
      }
      // Any other failure - timeout, no connection, 5xx - is not proof the
      // token is invalid, so the session (cached or not) is left standing
      appLogger.w('[auth] restore: network error (${e.type}), keeping cached session');
      if (cachedUser == null) {
        state = const AuthState(isInitialized: true);
      } else {
        state = state.copyWith(signedInOffline: true);
      }
    } catch (e) {
      appLogger.w('[auth] restore: unexpected error, keeping cached session: $e');
      if (cachedUser == null) {
        state = const AuthState(isInitialized: true);
      } else {
        state = state.copyWith(signedInOffline: true);
      }
    } finally {
      // No-op if the cache-hit branch already marked it. Only the no-cache
      // path reaches here first, since it has no earlier answer to give
      _markReady();
    }
  }

  bool _isAuthRejection(DioException e) {
    final status = e.response?.statusCode;
    return status == 401 || status == 403;
  }

  Future<void> login(String email, String password) async {
    state = state.copyWith(isLoading: true, clearError: true);

    try {
      final result = await _authService.login(email, password);
      await _storage.write(key: _tokenKey, value: result.token);
      await AuthCache.saveUser(result.user);
      SyncService.instance.setAuthToken(result.token);
      state = AuthState(
        token: result.token,
        user: result.user,
        isInitialized: true,
      );
      SyncService.instance.startAutoSync();
    } on DioException catch (e) {
      final message = e.response?.statusCode == 401
          ? 'Invalid email or password.'
          : e.type == DioExceptionType.connectionTimeout || e.type == DioExceptionType.receiveTimeout
              ? 'Server is taking too long to respond. Please try again.'
              : 'Could not connect to server. Please try again.';
      state = state.copyWith(isLoading: false, error: message);
    } catch (_) {
      state = state.copyWith(
          isLoading: false, error: 'An unexpected error occurred.');
    }
  }

  Future<void> logout() async {
    await _storage.delete(key: _tokenKey);
    await AuthCache.clear();
    SyncService.instance.clearAuthToken();
    state = const AuthState(isInitialized: true);
  }
}

final authServiceProvider = Provider<AuthService>((ref) => AuthService());

final authProvider = NotifierProvider<AuthNotifier, AuthState>(AuthNotifier.new);

import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import '../models/organization/organization.dart';
import '../services/app_logger.dart';
import '../services/auth_cache.dart';
import '../services/org_service.dart';
import 'auth_provider.dart';

// OrgService provider

final orgServiceProvider = Provider<OrgService>((ref) => OrgService());

// List of orgs the current user belongs to

// Falls back to the cached list when the network call fails, so org
// selection works with no signal instead of hanging on a request that
// cannot complete
final myOrgsProvider = FutureProvider<List<Organization>>((ref) async {
  final auth = ref.watch(authProvider);
  final token = auth.token;
  if (token == null) return [];

  try {
    final orgs = await ref.read(orgServiceProvider).getMyOrgs(token);
    await AuthCache.saveOrgs(orgs);
    return orgs;
  } catch (_) {
    return AuthCache.readOrgs();
  }
});

// Local snapshot of the org list, read straight from storage - lets the org
// picker paint the list a swap-eligible user already has instantly, instead
// of blocking on myOrgsProvider's live request every time the screen opens
final cachedOrgsProvider =
    FutureProvider<List<Organization>>((ref) => AuthCache.readOrgs());

// Selected org state

class SelectedOrgNotifier extends Notifier<Organization?> {
  static const _orgIdKey = 'selected_org_id';
  static const _storage = FlutterSecureStorage();

  @override
  Organization? build() {
    _restore();
    return null;
  }

  // Restores the last selected org so it doesn't silently reset on cold start
  Future<void> _restore() async {
    try {
      final savedId = await _storage.read(key: _orgIdKey);
      if (savedId == null) {
        appLogger.i('[org] restore: no saved org id, will show org picker');
        return;
      }

      // Waits for AuthNotifier to know the token first, so this never reads
      // myOrgsProvider before it's set and silently fails to match every boot
      await ref.read(authProvider.notifier).ready;

      // Matched against the cache first, not a live request - the whole
      // point of caching org/user data locally is that nothing needed to
      // resume a session should block on signal. A slow/unreachable
      // request here used to just mean the wrong screen flashed briefly;
      // now that app.dart waits on this to finish, it meant a blank
      // loading screen for up to the request's full timeout in the field
      final cached = await AuthCache.readOrgs();
      final cachedMatch = _findById(cached, savedId);
      if (cachedMatch != null) {
        appLogger.i('[org] restore: matched from cache, resuming org ${cachedMatch.id}');
        state = cachedMatch;
        // Refreshes the cache for next time - not on this path's critical path
        unawaited(ref.read(myOrgsProvider.future));
        return;
      }

      final orgs = await ref.read(myOrgsProvider.future);
      appLogger.i('[org] restore: saved=$savedId, candidates=${orgs.map((o) => o.id).toList()}');
      if (state != null) {
        appLogger.i('[org] restore: state already set to ${state?.id} by the time orgs loaded, not overwriting');
        return;
      }
      final match = _findById(orgs, savedId);
      if (match != null) {
        appLogger.i('[org] restore: matched, resuming org ${match.id}');
        state = match;
        return;
      }
      appLogger.w('[org] restore: saved id $savedId not found among ${orgs.length} candidate(s), will show org picker');
    } finally {
      // Flipped exactly once, on every exit path - lets app.dart tell
      // "still restoring" apart from "genuinely no org", which otherwise
      // look identical (both null) and briefly bounce to the org picker
      // on every cold start, including the process restart Android does
      // behind the camera intent
      ref.read(orgRestoredProvider.notifier).state = true;
    }
  }

  Organization? _findById(List<Organization> orgs, String id) {
    for (final org in orgs) {
      if (org.id.toString() == id) return org;
    }
    return null;
  }

  void select(Organization org) {
    state = org;
    _storage.write(key: _orgIdKey, value: org.id.toString());
  }

  void clear() {
    state = null;
    _storage.delete(key: _orgIdKey);
  }
}

final selectedOrgProvider =
    NotifierProvider<SelectedOrgNotifier, Organization?>(
        SelectedOrgNotifier.new);

// True once _restore() has finished (found a match, found none, or had
// nothing saved) - distinct from selectedOrgProvider itself because both
// "still restoring" and "no org selected" read as null there
final orgRestoredProvider = NotifierProvider<_OrgRestoredNotifier, bool>(
    _OrgRestoredNotifier.new);

class _OrgRestoredNotifier extends Notifier<bool> {
  @override
  bool build() => false;
}

/// Convenience: the currently selected org's id (throws if none selected).
final selectedOrgIdProvider = Provider<int>((ref) {
  final org = ref.watch(selectedOrgProvider);
  if (org == null) throw StateError('No org selected');
  return org.id;
});

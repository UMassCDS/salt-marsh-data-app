import 'dart:convert';
import 'dart:io';
import 'live_backend.dart';
import 'sync_harness.dart';

const productionHosts = {
  'saltmarshdata.org',
  'www.saltmarshdata.org',
  'massmarsh.azurewebsites.net',
  'massmarsh-backend.azurewebsites.net',
};

// These tests create and delete sessions, so they must never point at production
String? refuseProduction(String? url) {
  if (url == null) return null;
  final host = Uri.parse(url).host.toLowerCase();
  if (productionHosts.contains(host)) {
    throw StateError('Refusing to run real-backend tests against production ($host)');
  }
  return url;
}

final _env = Platform.environment;
final baseUrl = refuseProduction(_env['E2E_API_BASE_URL']);
final backendRequired = _env['E2E_REQUIRED'] == '1';
final skipWithoutBackend = baseUrl == null ? 'set E2E_API_BASE_URL to run against a real backend' : null;

// Defaults are the demo users that backend/scripts/init_db.py creates; a shared server passes its own test accounts
(String, String) credentialsFor(String role, {Map<String, String>? env}) {
  final source = env ?? _env;
  final upper = role.toUpperCase();
  return (source['E2E_${upper}_EMAIL'] ?? '$role@umass.edu', source['E2E_${upper}_PASSWORD'] ?? 'demo123');
}

class LiveRun {
  LiveRun._(this.backend, this.contributorToken, this.managerToken, this.viewerToken, this.orgId);

  final LiveBackend backend;
  final String contributorToken;
  final String managerToken;
  final String viewerToken;
  final int orgId;
  final String id = '${DateTime.now().millisecondsSinceEpoch}';
  final List<String> _seeded = [];

  static Future<LiveRun> start() async {
    final backend = LiveBackend(baseUrl!);
    Future<String> login(String role) {
      final (email, password) = credentialsFor(role);
      return backend.login(email, password);
    }

    final contributorToken = await login('contributor');
    final configuredOrg = int.tryParse(_env['E2E_ORG_ID'] ?? '');
    final orgId = configuredOrg ?? await backend.firstOrganizationId(contributorToken);
    return LiveRun._(backend, contributorToken, await login('manager'), await login('viewer'), orgId);
  }

  String localId(String name) => 'e2e-$name-$id';

  Future<int> seedOuting(SyncHarness harness, String localId, {int plots = 2}) async {
    _seeded.add(localId);
    final db = await harness.db;
    final outingId = await db.insert('field_outings', {
      'local_id': localId,
      'org_id': orgId,
      'site_name': localId,
      'other_members': 'Sam Rivera',
      'monitoring_type': 'vegetation',
      'start_time': '2026-07-01T09:00:00',
      'end_time': '2026-07-01T11:30:00',
      'is_draft': 0,
      'sync_status': 'pending',
    });
    for (var plot = 1; plot <= plots; plot++) {
      await db.insert('vegetation_records', plotRow(localId, outingId, plot));
    }
    return outingId;
  }

  Future<void> addLatePlot(SyncHarness harness, {required int outingId, required String localId, required int plot}) async {
    final row = plotRow(localId, outingId, plot)..remove('sync_status');
    await (await harness.db).insert('vegetation_records', row);
  }

  Future<int> sessionsNamed(String siteName) async =>
      (await backend.sessions(managerToken, orgId)).where((s) => s['site_name'] == siteName).length;

  Future<Map<String, dynamic>?> storedSession(String localId) async {
    final serverId = (await backend.syncStatus(managerToken, [localId]))[localId]?['server_id'];
    if (serverId == null) return null;
    return (await backend.sessions(managerToken, orgId)).where((s) => s['id'] == serverId).singleOrNull;
  }

  // Deletes every session this run created, so a shared server is left as it was found
  Future<void> cleanUp() async {
    if (_seeded.isEmpty) return;
    final status = await backend.syncStatus(managerToken, _seeded);
    for (final record in status.values) {
      final serverId = record['server_id'];
      if (serverId is int) await backend.deleteSession(managerToken, orgId, serverId);
    }
  }
}

Map<String, Object?> plotRow(String localId, int outingId, int plot) => {
      'local_id': '$localId-plot-$plot',
      'outing_id': outingId,
      'transect_id': 'T1',
      'plot_number': plot,
      'latitude': 42.1,
      'longitude': -71.2,
      'accuracy_m': 4.2,
      'location_quality': 'gps_good',
      'canopy_height_m': 0.45,
      'thatch_height_m': 0.07,
      'species_observations': jsonEncode([
        {'species_code': 'SPALT', 'percentage_cover': 60},
        {'species_code': 'BARE', 'percentage_cover': 40},
      ]),
      'protocol_code': 'MassMarshVeg',
      'sync_status': 'pending',
    };

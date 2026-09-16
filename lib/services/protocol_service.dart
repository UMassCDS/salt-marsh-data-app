import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:sqflite/sqflite.dart' show ConflictAlgorithm;
import '../database/app_database.dart';
import 'app_logger.dart';
import 'sync_service.dart';

// ---------------------------------------------------------------------------
// Protocol definition data classes
// ---------------------------------------------------------------------------

class ProtocolSpeciesConfig {
  final List<String> pinnedSpecies;
  final bool require100Percent;
  final int coverIncrement; // 1 = arbitrary integer, 10 = multiples of 10
  final int minSpecies;
  final int? maxSpecies;

  const ProtocolSpeciesConfig({
    required this.pinnedSpecies,
    required this.require100Percent,
    required this.coverIncrement,
    required this.minSpecies,
    this.maxSpecies,
  });

  factory ProtocolSpeciesConfig.fromJson(Map<String, dynamic> json) {
    return ProtocolSpeciesConfig(
      pinnedSpecies: (json['pinned_species'] as List<dynamic>?)
              ?.map((e) => e as String)
              .toList() ??
          [],
      require100Percent: (json['require_100_percent'] as bool?) ?? false,
      coverIncrement: (json['cover_increment'] as int?) ?? 1,
      minSpecies: (json['min_species'] as int?) ?? 0,
      maxSpecies: json['max_species'] as int?,
    );
  }
}

class ProtocolDefinition {
  final String protocolCode;
  final String protocolName;
  final String version;
  final List<String> hiddenFields;
  final List<String> plotExtraFields;
  final ProtocolSpeciesConfig speciesConfig;
  final List<String>? subclassOptions;

  const ProtocolDefinition({
    required this.protocolCode,
    required this.protocolName,
    required this.version,
    required this.hiddenFields,
    required this.plotExtraFields,
    required this.speciesConfig,
    this.subclassOptions,
  });

  /// Whether a named field should be hidden for this protocol.
  bool isFieldHidden(String fieldName) => hiddenFields.contains(fieldName);

  /// Whether a named extra field should be shown for this protocol.
  bool hasExtraField(String fieldName) => plotExtraFields.contains(fieldName);

  factory ProtocolDefinition.fromApiResponse(Map<String, dynamic> json) {
    final def = json['definition'] as Map<String, dynamic>;
    return ProtocolDefinition(
      protocolCode: json['protocol_code'] as String,
      protocolName: json['protocol_name'] as String,
      version: (def['version'] as String?) ?? '1.0',
      hiddenFields: (def['hidden_fields'] as List<dynamic>?)
              ?.map((e) => e as String)
              .toList() ??
          [],
      plotExtraFields: (def['plot_extra_fields'] as List<dynamic>?)
              ?.map((e) => e as String)
              .toList() ??
          [],
      speciesConfig: ProtocolSpeciesConfig.fromJson(
        def['species_config'] as Map<String, dynamic>? ?? {},
      ),
      subclassOptions: (def['subclass_options'] as List<dynamic>?)
          ?.map((e) => e as String)
          .toList(),
    );
  }

  /// Fallback used when offline and no cache exists.
  factory ProtocolDefinition.massMarshVegDefault() {
    return const ProtocolDefinition(
      protocolCode: 'MassMarshVeg',
      protocolName: 'MassMarsh Vegetation SOP',
      version: '1.0',
      hiddenFields: [],
      plotExtraFields: [],
      speciesConfig: ProtocolSpeciesConfig(
        pinnedSpecies: ['SPALT', 'SPPAT', 'BARE', 'DEAD'],
        require100Percent: false,
        coverIncrement: 1,
        minSpecies: 0,
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Protocol service (mirrors SpeciesService pattern exactly)
// ---------------------------------------------------------------------------

class ProtocolService {
  static final ProtocolService instance = ProtocolService._();
  ProtocolService._();

  final _logger = appLogger;
  static const String _apiBase = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'https://massmarsh.azurewebsites.net',
  );

  /// Fetch the active protocol for [orgId] from the API and cache it locally.
  /// Falls back to the local cache when offline or on error.
  /// Falls back to a hard-coded MassMarshVeg default if the cache is also empty.
  Future<ProtocolDefinition> fetchAndCache(int orgId) async {
    if (await SyncService.instance.hasConnectivity()) {
      try {
        final response = await Dio().get(
          '$_apiBase/api/mobile/orgs/$orgId/protocol',
          options: Options(receiveTimeout: const Duration(seconds: 30)),
        );
        if (response.statusCode == 200 && response.data['success'] == true) {
          final data = response.data as Map<String, dynamic>;
          await _cacheProtocol(orgId, data);
          _logger.i('Fetched protocol for org $orgId: ${data['protocol_code']}');
          return ProtocolDefinition.fromApiResponse(data);
        }
      } catch (e) {
        _logger.w('Protocol API fetch failed for org $orgId, using cache: $e');
      }
    }

    return _loadFromCache(orgId);
  }

  Future<void> _cacheProtocol(int orgId, Map<String, dynamic> responseData) async {
    final db = await AppDatabase.instance.database;
    await db.insert(
      'protocol_cache',
      {
        'org_id': orgId,
        'protocol_code': responseData['protocol_code'] as String,
        'protocol_name': responseData['protocol_name'] as String,
        'definition_json': jsonEncode(responseData),
        'cached_at': DateTime.now().toIso8601String(),
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<ProtocolDefinition> _loadFromCache(int orgId) async {
    final db = await AppDatabase.instance.database;
    final rows = await db.query(
      'protocol_cache',
      where: 'org_id = ?',
      whereArgs: [orgId],
      limit: 1,
    );
    if (rows.isEmpty) return ProtocolDefinition.massMarshVegDefault();
    final raw = jsonDecode(rows.first['definition_json'] as String) as Map<String, dynamic>;
    return ProtocolDefinition.fromApiResponse(raw);
  }
}

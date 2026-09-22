import 'package:dio/dio.dart';
import 'package:sqflite/sqflite.dart' show ConflictAlgorithm;
import '../config/env.dart';
import '../database/app_database.dart';
import 'app_logger.dart';
import 'sync_service.dart';

class SpeciesItem {
  final String code;
  final String scientificName;
  final String? commonName;

  const SpeciesItem({
    required this.code,
    required this.scientificName,
    this.commonName,
  });

  /// Display label shown in search results (primary line)
  String get label => commonName != null ? '$code – $commonName' : code;
}

class SpeciesService {
  static final SpeciesService instance = SpeciesService._();
  SpeciesService._();

  final _logger = appLogger;

  static const _ttl = Duration(hours: 1);
  List<SpeciesItem>? _memCache;
  DateTime? _lastFetched;

  /// Fetch species from API and cache in SQLite species_lookup table.
  /// Returns in-memory cache if fetched within the last 24 hours.
  /// Falls back to SQLite cache on failure / offline.
  Future<List<SpeciesItem>> fetchAndCache() async {
    // Return in-memory cache if still fresh
    if (_memCache != null &&
        _lastFetched != null &&
        DateTime.now().difference(_lastFetched!) < _ttl) {
      return _memCache!;
    }

    // Try network first
    if (await SyncService.instance.hasConnectivity()) {
      try {
        final response = await Dio().get(
          '$kApiBaseUrl/api/mobile/species',
          options: Options(receiveTimeout: const Duration(seconds: 30)),
        );
        if (response.statusCode == 200 && response.data['success'] == true) {
          final List<dynamic> raw = response.data['species'] as List<dynamic>;
          await _cacheSpecies(raw);
          _logger.i('Fetched ${raw.length} species from API');
        }
      } catch (e) {
        _logger.w('Species API fetch failed, using cache: $e');
      }
    }

    final species = await _loadFromCache();
    _memCache = species;
    _lastFetched = DateTime.now();
    return species;
  }

  Future<void> _cacheSpecies(List<dynamic> raw) async {
    final db = await AppDatabase.instance.database;
    final batch = db.batch();
    for (final item in raw) {
      batch.insert(
        'species_lookup',
        {
          'species_code': item['species_code'] as String,
          'scientific_name': item['scientific_name'] as String,
          'common_name': item['common_name'] as String?,
          'active': 1,
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }
    await batch.commit(noResult: true);
  }

  Future<List<SpeciesItem>> _loadFromCache() async {
    final db = await AppDatabase.instance.database;
    final rows = await db.query(
      'species_lookup',
      columns: ['species_code', 'scientific_name', 'common_name'],
      where: 'active = ?',
      whereArgs: [1],
      orderBy: 'species_code ASC',
    );
    return rows
        .map((r) => SpeciesItem(
              code: r['species_code'] as String,
              scientificName: r['scientific_name'] as String,
              commonName: r['common_name'] as String?,
            ))
        .toList();
  }
}

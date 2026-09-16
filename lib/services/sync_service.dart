import 'dart:async';
import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:logger/logger.dart';
import '../database/app_database.dart';
import 'app_logger.dart';
import 'auth_cache.dart';

class ResyncResult {
  final bool alreadyOnServer;
  final bool uploadedNow;
  final bool uploadFailed;
  final int photosStillPending;
  final int uploadedCount;
  final int plotsRecovered;
  final int photosUploaded;

  const ResyncResult({
    required this.alreadyOnServer,
    required this.uploadedNow,
    required this.uploadFailed,
    required this.photosStillPending,
    this.uploadedCount = 1,
    this.plotsRecovered = 0,
    this.photosUploaded = 0,
  });
}

/// Service for synchronizing local database with cloud backend.
///
/// Implements an offline-first architecture where:
/// 1. All data is stored locally in SQLite
/// 2. Changes are queued when offline
/// 3. Automatic sync when connectivity is restored
/// 4. Conflict resolution for bidirectional sync
class SyncService {
  final Dio _dio;
  final AppDatabase _db;
  final Logger _logger;
  final Connectivity _connectivity;

  /// Base URL for the API (should be configured per environment)
  late final String _baseUrl;

  /// Auth token for API requests
  String? _authToken;

  StreamSubscription<List<ConnectivityResult>>? _connectivitySub;

  // Prevents overlapping uploads of the same outing (Resync, Sync All,
  // connectivity restore, and the background task can all trigger at once),
  // since /field-outings has no upsert and duplicate POSTs crash on a unique
  // constraint instead of just being redundant
  final Set<int> _outingsUploading = {};

  static SyncService? _instance;

  /// Private constructor for singleton pattern
  SyncService._({
    required Dio dio,
    required AppDatabase db,
    required Logger logger,
    required Connectivity connectivity,
    required String baseUrl,
  })  : _dio = dio,
        _db = db,
        _logger = logger,
        _connectivity = connectivity,
        _baseUrl = baseUrl {
    _configureClient();
  }

  /// Get or create singleton instance
  static SyncService get instance {
    _instance ??= SyncService._(
      dio: Dio(),
      db: AppDatabase.instance,
      logger: appLogger,
      connectivity: Connectivity(),
      baseUrl: const String.fromEnvironment(
        'API_BASE_URL',
        // defaultValue: 'http://10.0.2.2:8000',
        defaultValue: 'https://massmarsh.azurewebsites.net',
      ),
    );
    return _instance!;
  }

  /// Configure the HTTP client
  void _configureClient() {
    _dio.options.baseUrl = _baseUrl;
    _dio.options.connectTimeout = const Duration(seconds: 60);
    _dio.options.receiveTimeout = const Duration(seconds: 60);

    // Add interceptors for auth and logging
    _dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) {
          if (_authToken != null) {
            options.headers['Authorization'] = 'Bearer $_authToken';
          }
          options.headers['Content-Type'] = 'application/json';
          _logger.d('Request: ${options.method} ${options.path}');
          return handler.next(options);
        },
        onResponse: (response, handler) {
          _logger.d('Response: ${response.statusCode} ${response.requestOptions.path}');
          final refreshed = response.headers.value('x-refreshed-token');
          if (refreshed != null && refreshed != _authToken) {
            _authToken = refreshed;
            AuthCache.updateToken(refreshed);
          }
          return handler.next(response);
        },
        onError: (error, handler) {
          _logger.e('Error: ${error.message}');
          return handler.next(error);
        },
      ),
    );
  }

  Map<String, dynamic> _vegRecordPayload(Map<String, dynamic> veg, String? photoUrl) {
    return {
      'local_id': veg['local_id'] as String? ?? '',
      'transect_id': veg['transect_id'],
      'plot_number': veg['plot_number'],
      'plot_id': veg['plot_id'],
      'habitat_type': veg['habitat_type'],
      'distance_along_transect_m': veg['distance_along_transect_m'],
      'latitude': veg['latitude'],
      'longitude': veg['longitude'],
      'elevation_m': veg['elevation_m'],
      'canopy_height_m': veg['canopy_height_m'],
      'thatch_height_m': veg['thatch_height_m'],
      'species_observations': jsonDecode(veg['species_observations'] as String),
      'photo_url': photoUrl,
      'notes': veg['notes'],
      'protocol_code': veg['protocol_code'],
      'subclass': veg['subclass'],
      'rtk_point_number': veg['rtk_point_number'],
    };
  }

  /// Upload a field outing with all child records to the server
  ///
  /// This method bundles a field outing and all its child records
  /// (vegetation, hydrology, elevation) into a single API call.
  ///
  /// Returns server-assigned ID on success, null on failure.
  Future<int?> uploadFieldOuting(int localOutingId) async {
    if (_outingsUploading.contains(localOutingId)) {
      _logger.w('Upload already in progress for outing $localOutingId, skipping');
      return null;
    }
    _outingsUploading.add(localOutingId);
    try {
      return await _doUploadFieldOuting(localOutingId);
    } finally {
      _outingsUploading.remove(localOutingId);
    }
  }

  Future<int?> _doUploadFieldOuting(int localOutingId) async {
    try {
      if (!await hasConnectivity()) {
        _logger.w('No connectivity available for field outing upload');
        return null;
      }

      final db = await _db.database;

      // Fetch field outing
      final outingRows = await db.query(
        'field_outings',
        where: 'id = ?',
        whereArgs: [localOutingId],
      );

      if (outingRows.isEmpty) {
        _logger.e('Field outing not found: $localOutingId');
        return null;
      }

      final outing = outingRows.first;

      // A prior attempt may have already succeeded server-side without this
      // row ever being marked synced (e.g. the app lost the response) -
      // resending would duplicate the session, so check first
      final localId = outing['local_id'] as String?;
      if (localId != null) {
        final check = await _lookupServerId(localId);
        if (!check.verified) {
          _logger.w('Could not verify outing $localOutingId against the server, skipping upload to avoid a duplicate');
          return null;
        }
        if (check.serverId != null) {
          await db.update(
            'field_outings',
            {'sync_status': 'synced', 'server_id': check.serverId},
            where: 'id = ?',
            whereArgs: [localOutingId],
          );
          _logger.i('Outing $localOutingId already existed server-side, marked synced without resending');
          return check.serverId;
        }
      }

      // Build the request payload
      final payload = <String, dynamic>{
        'org_id': outing['org_id'],
        'local_id': outing['local_id'],
        'site_name': outing['site_name'],
        'other_members': outing['other_members'],
        'monitoring_type': outing['monitoring_type'],
        'start_time': outing['start_time'],
        'end_time': outing['end_time'],
        'submission_time': outing['submission_time'],
        'latitude': outing['latitude'],
        'longitude': outing['longitude'],
        if (outing['visibility'] != null) 'visibility': outing['visibility'],
        if (outing['embargo_until'] != null) 'embargo_until': outing['embargo_until'],
      };

      // Fetch and add vegetation records
      final vegRecords = await db.query(
        'vegetation_records',
        where: 'outing_id = ?',
        whereArgs: [localOutingId],
      );

      // Upload photos first, collect blob URLs (or errors) keyed by local_id
      final photoUrls = <String, String>{};
      final photoErrors = <String, String>{};
      for (final veg in vegRecords) {
        final localPath = veg['photo_local_path'] as String?;
        final localId = veg['local_id'] as String? ?? '';
        if (localPath != null && localPath.isNotEmpty) {
          final (url, error) = await _uploadPhoto(localPath);
          if (url != null) {
            photoUrls[localId] = url;
          } else {
            photoErrors[localId] = error ?? 'Photo upload failed';
          }
        }
      }

      // Derive session-level protocol_code from first veg record (all plots share one protocol)
      final sessionProtocolCode = vegRecords.isNotEmpty
          ? (vegRecords.first['protocol_code'] as String? ?? 'MassMarshVeg')
          : 'MassMarshVeg';
      payload['protocol_code'] = sessionProtocolCode;

      payload['vegetation_records'] = vegRecords
          .map((veg) => _vegRecordPayload(veg, photoUrls[veg['local_id'] as String? ?? '']))
          .toList();

      // Fetch and add hydrology records
      final hydroRecords = await db.query(
        'hydrology_records',
        where: 'outing_id = ?',
        whereArgs: [localOutingId],
      );

      payload['hydrology_records'] = hydroRecords.map((hydro) {
        return {
          'local_id': hydro['local_id'],
          'area_treatment': hydro['area_treatment'],
          'wlr_type': hydro['wlr_type'],
          'serial_number': hydro['serial_number'],
          'elevation_waypoint_type': hydro['elevation_waypoint_type'],
          'waypoint_number': hydro['waypoint_number'],
          'rtk_elevation_navd88_m': hydro['rtk_elevation_navd88_m'],
          'time_water_elevation_taken': hydro['time_water_elevation_taken'],
          'water_above_below_nut_m': hydro['water_above_below_nut_m'],
          'well_rim_to_water_m': hydro['well_rim_to_water_m'],
          'well_rim_to_marsh_m': hydro['well_rim_to_marsh_m'],
          'well_rim_to_sensor_m': hydro['well_rim_to_sensor_m'],
          'well_length_m': hydro['well_length_m'],
          'notes': hydro['notes'],
        };
      }).toList();

      // Fetch and add elevation records
      final elevRecords = await db.query(
        'elevation_records',
        where: 'outing_id = ?',
        whereArgs: [localOutingId],
      );

      payload['elevation_records'] = elevRecords.map((elev) {
        return {
          'local_id': elev['local_id'],
          'transect_id': elev['transect_id'],
          'point_number': elev['point_number'],
          'latitude': elev['latitude'],
          'longitude': elev['longitude'],
          'elevation_navd88_m': elev['elevation_navd88_m'],
          'feature_type': elev['feature_type'],
          'notes': elev['notes'],
        };
      }).toList();

      // Upload to server
      _logger.i('Uploading field outing: ${outing['local_id']}');
      _logger.d('Base URL: $_baseUrl');
      _logger.d('Endpoint: /api/mobile/field-outings');
      _logger.d('Full URL: $_baseUrl/api/mobile/field-outings');
      _logger.d('Payload: ${payload.toString().substring(0, 200)}...');

      final response = await _dio.post(
        '/api/mobile/field-outings',
        data: payload,
      );

      _logger.d('Response status: ${response.statusCode}');

      if (response.statusCode == 200 && response.data['success'] == true) {
        // Validated explicitly (rather than letting a bad cast throw into the
        // generic catch below) so a backend schema change is diagnosable from
        // field logs as "unexpected response shape", not a cryptic TypeError
        // indistinguishable from a network hiccup
        final rawServerId = response.data['server_id'];
        final rawChildRecords = response.data['child_records'];
        if (rawServerId is! int || rawChildRecords is! Map) {
          _logger.e('Unexpected response shape from server for field outing '
              'upload: server_id=$rawServerId child_records=$rawChildRecords');
          return null;
        }
        final serverId = rawServerId;
        final childRecordIds = rawChildRecords.cast<String, dynamic>();

        // Update local record with server ID and sync status
        await db.update(
          'field_outings',
          {
            'sync_status': 'synced',
            'server_id': serverId,
          },
          where: 'id = ?',
          whereArgs: [localOutingId],
        );

        // Update child records with server IDs
        if (childRecordIds['vegetation'] != null) {
          final vegMap = childRecordIds['vegetation'] as Map<String, dynamic>;
          for (final entry in vegMap.entries) {
            final photoFailed = photoErrors.containsKey(entry.key);
            await db.update(
              'vegetation_records',
              {
                'sync_status': 'synced',
                'server_id': entry.value,
                if (photoUrls.containsKey(entry.key))
                  'photo_filename': photoUrls[entry.key],
                'photo_upload_error': photoFailed ? photoErrors[entry.key] : null,
                if (photoFailed)
                  'photo_upload_attempts': 1,
              },
              where: 'local_id = ?',
              whereArgs: [entry.key],
            );
          }
        }

        if (childRecordIds['hydrology'] != null) {
          final hydroMap = childRecordIds['hydrology'] as Map<String, dynamic>;
          for (final entry in hydroMap.entries) {
            await db.update(
              'hydrology_records',
              {
                'sync_status': 'synced',
                'server_id': entry.value,
              },
              where: 'local_id = ?',
              whereArgs: [entry.key],
            );
          }
        }

        if (childRecordIds['elevation'] != null) {
          final elevMap = childRecordIds['elevation'] as Map<String, dynamic>;
          for (final entry in elevMap.entries) {
            await db.update(
              'elevation_records',
              {
                'sync_status': 'synced',
                'server_id': entry.value,
              },
              where: 'local_id = ?',
              whereArgs: [entry.key],
            );
          }
        }

        _logger.i('Field outing uploaded successfully. Server ID: $serverId');
        return serverId;
      } else {
        _logger.e('Upload failed: ${response.statusCode} - ${response.data}');
        return null;
      }
    } on DioException catch (e) {
      _logger.e('Network error uploading field outing: ${e.message}');
      return null;
    } catch (e) {
      _logger.e('Error uploading field outing: $e');
      return null;
    }
  }

  /// Upload all pending field outings
  ///
  /// Processes all field outings with sync_status='pending'
  /// and uploads them to the server.
  ///
  /// Returns number of successfully uploaded outings.
  Future<int> uploadAllPendingOutings() async {
    try {
      if (!await hasConnectivity()) {
        _logger.w('No connectivity for uploading pending outings');
        return 0;
      }

      final db = await _db.database;
      final pendingOutings = await db.query(
        'field_outings',
        where: 'sync_status = ? AND is_draft = ?',
        whereArgs: ['pending', 0],
        orderBy: 'created_at ASC',
      );

      if (pendingOutings.isEmpty) {
        _logger.i('No pending outings to upload');
        return 0;
      }

      int successCount = 0;

      for (final outing in pendingOutings) {
        final serverId = await uploadFieldOuting(outing['id'] as int);
        if (serverId != null) {
          successCount++;
        }
      }

      _logger.i('Uploaded $successCount/${pendingOutings.length} pending outings');

      // Synced outings can still have a failed photo, so they need a separate pass
      await retryPendingPhotoUploads();

      return successCount;
    } catch (e) {
      _logger.e('Error uploading pending outings: $e');
      return 0;
    }
  }

  /// Retries photos for records with a server_id but no photo_filename yet
  Future<int> retryPendingPhotoUploads({int? outingId}) async {
    if (!await hasConnectivity()) return 0;

    final db = await _db.database;
    final rows = await db.query(
      'vegetation_records',
      where: "server_id IS NOT NULL AND photo_local_path IS NOT NULL AND "
          "photo_local_path != '' AND (photo_filename IS NULL OR photo_filename = '')"
          "${outingId != null ? ' AND outing_id = ?' : ''}",
      whereArgs: outingId != null ? [outingId] : null,
    );

    int successCount = 0;

    for (final row in rows) {
      final localPath = row['photo_local_path'] as String;
      final serverId = row['server_id'] as int;
      final attempts = (row['photo_upload_attempts'] as int?) ?? 0;

      final (url, error) = await _uploadPhoto(localPath);
      if (url == null) {
        await db.update(
          'vegetation_records',
          {
            'photo_upload_error': error,
            'photo_upload_attempts': attempts + 1,
          },
          where: 'id = ?',
          whereArgs: [row['id']],
        );
        continue;
      }

      try {
        await _dio.put(
          '/api/mobile/vegetation-records/$serverId/photo',
          data: {'photo_url': url},
        );
        await db.update(
          'vegetation_records',
          {
            'photo_filename': url,
            'photo_upload_error': null,
          },
          where: 'id = ?',
          whereArgs: [row['id']],
        );
        successCount++;
      } catch (e) {
        _logger.w('Failed to attach uploaded photo to record $serverId: $e');
        await db.update(
          'vegetation_records',
          {
            'photo_upload_error': e.toString(),
            'photo_upload_attempts': attempts + 1,
          },
          where: 'id = ?',
          whereArgs: [row['id']],
        );
      }
    }

    if (rows.isNotEmpty) {
      _logger.i('Retried ${rows.length} pending photo upload(s), $successCount succeeded');
    }

    return successCount;
  }

  /// Get count of vegetation records whose photo still needs to be (re)uploaded
  Future<int> getPendingPhotoUploadsCount({int? outingId}) async {
    final db = await _db.database;
    final result = await db.rawQuery(
      "SELECT COUNT(*) as count FROM vegetation_records WHERE server_id IS NOT NULL "
      "AND photo_local_path IS NOT NULL AND photo_local_path != '' "
      "AND (photo_filename IS NULL OR photo_filename = '')"
      "${outingId != null ? ' AND outing_id = ?' : ''}",
      outingId != null ? [outingId] : [],
    );
    return result.isNotEmpty ? (result.first['count'] as int? ?? 0) : 0;
  }

  // Confirms with the server (not just the local flag) before ever resending,
  // since /field-outings has no upsert and would duplicate an existing session
  Future<ResyncResult> resyncOuting(int outingId) async {
    final db = await _db.database;
    final rows = await db.query(
      'field_outings',
      columns: ['is_draft', 'local_id', 'server_id'],
      where: 'id = ?',
      whereArgs: [outingId],
      limit: 1,
    );
    if (rows.isEmpty || rows.first['is_draft'] == 1) {
      return const ResyncResult(alreadyOnServer: false, uploadedNow: false, uploadFailed: false, photosStillPending: 0);
    }

    final localId = rows.first['local_id'] as String?;
    final check = localId != null
        ? await _lookupServerId(localId)
        : (verified: true, serverId: null);
    if (!check.verified) {
      return const ResyncResult(
          alreadyOnServer: false, uploadedNow: false, uploadFailed: true, photosStillPending: 0);
    }
    final existingServerId = check.serverId;
    final alreadyOnServer = existingServerId != null;
    var uploadedNow = false;
    var uploadFailed = false;
    var plotsRecovered = 0;

    if (alreadyOnServer) {
      await db.update(
        'field_outings',
        {'sync_status': 'synced', 'server_id': existingServerId},
        where: 'id = ?',
        whereArgs: [outingId],
      );
      plotsRecovered = await _addMissingVegetationRecords(outingId, existingServerId);
    } else {
      final serverId = await uploadFieldOuting(outingId);
      uploadedNow = serverId != null;
      uploadFailed = serverId == null;
    }

    final photosUploaded = await retryPendingPhotoUploads(outingId: outingId);
    final photosStillPending = await getPendingPhotoUploadsCount(outingId: outingId);

    return ResyncResult(
      alreadyOnServer: alreadyOnServer,
      uploadedNow: uploadedNow,
      uploadFailed: uploadFailed,
      photosStillPending: photosStillPending,
      plotsRecovered: plotsRecovered,
      photosUploaded: photosUploaded,
    );
  }

  // Plots that never made it into a session that already exists server-side
  // (e.g. the outing uploaded before local inserts finished) have a local_id
  // but no server_id, even though the outing itself does. Attaches them now.
  Future<int> _addMissingVegetationRecords(int outingId, int serverId) async {
    final db = await _db.database;
    final orphaned = await db.query(
      'vegetation_records',
      where: 'outing_id = ? AND server_id IS NULL',
      whereArgs: [outingId],
    );
    if (orphaned.isEmpty) return 0;

    final photoUrls = <String, String>{};
    for (final veg in orphaned) {
      final localPath = veg['photo_local_path'] as String?;
      final localId = veg['local_id'] as String? ?? '';
      if (localPath != null && localPath.isNotEmpty) {
        final (url, _) = await _uploadPhoto(localPath);
        if (url != null) photoUrls[localId] = url;
      }
    }

    try {
      final response = await _dio.post(
        '/api/mobile/field-outings/$serverId/vegetation-records',
        data: {
          'protocol_code': orphaned.first['protocol_code'],
          'vegetation_records': orphaned
              .map((veg) => _vegRecordPayload(veg, photoUrls[veg['local_id'] as String? ?? '']))
              .toList(),
        },
      );
      if (response.statusCode != 200 || response.data['success'] != true) return 0;

      final ids = (response.data['child_records']['vegetation'] as Map<String, dynamic>);
      for (final entry in ids.entries) {
        await db.update(
          'vegetation_records',
          {
            'server_id': entry.value,
            'sync_status': 'synced',
            if (photoUrls.containsKey(entry.key)) 'photo_filename': photoUrls[entry.key],
          },
          where: 'local_id = ?',
          whereArgs: [entry.key],
        );
      }
      return ids.length;
    } catch (e) {
      _logger.w('Failed to attach missing plots for outing $outingId: $e');
      return 0;
    }
  }

  /// Runs resyncOuting across every non-draft session in an org
  ///
  /// Scoped to [userId] so it matches what My Sessions actually shows, rather
  /// than sweeping up another account's sessions on a shared device
  Future<ResyncResult> resyncAllOutings(int orgId, {int? userId}) async {
    final db = await _db.database;
    final rows = await db.query(
      'field_outings',
      columns: ['id'],
      where: userId != null
          ? 'org_id = ? AND is_draft = 0 AND created_by_user_id = ?'
          : 'org_id = ? AND is_draft = 0',
      whereArgs: userId != null ? [orgId, userId] : [orgId],
    );
    var uploadedCount = 0;
    var failedCount = 0;
    var photosStillPending = 0;
    var plotsRecovered = 0;
    var photosUploaded = 0;
    for (final row in rows) {
      final result = await resyncOuting(row['id'] as int);
      if (result.uploadedNow) uploadedCount++;
      if (result.uploadFailed) failedCount++;
      photosStillPending += result.photosStillPending;
      plotsRecovered += result.plotsRecovered;
      photosUploaded += result.photosUploaded;
    }
    return ResyncResult(
      alreadyOnServer: false,
      uploadedNow: uploadedCount > 0,
      uploadFailed: failedCount > 0,
      photosStillPending: photosStillPending,
      uploadedCount: uploadedCount,
      plotsRecovered: plotsRecovered,
      photosUploaded: photosUploaded,
    );
  }

  // Tri-state on purpose: a failed check must never look like "not on server",
  // or a flaky connection silently re-uploads and duplicates the session
  Future<({bool verified, int? serverId})> _lookupServerId(String localId) async {
    try {
      final response = await _dio.post(
        '/api/mobile/sync-status',
        data: {'local_ids': [localId]},
      );
      final records = response.data['records'] as Map<String, dynamic>?;
      final record = records?[localId] as Map<String, dynamic>?;
      if (record?['synced'] != true) return (verified: true, serverId: null);
      return (verified: true, serverId: record?['server_id'] as int?);
    } catch (e) {
      _logger.w('Could not check server sync status for $localId: $e');
      return (verified: false, serverId: null);
    }
  }

  /// Returns (null, errorMessage) on failure instead of just null
  Future<(String? url, String? error)> _uploadPhoto(String localPath) async {
    try {
      final file = await _multipartFileFromPath(localPath);
      if (file == null) return (null, 'Could not read photo file');

      final formData = FormData.fromMap({'file': file});

      // Temporarily remove Content-Type so Dio sets multipart boundary
      final originalContentType = _dio.options.headers['Content-Type'];
      _dio.options.headers.remove('Content-Type');

      // Full-res photos on a weak connection can take minutes, not 60s
      final response = await _dio.post(
        '/api/mobile/photos',
        data: formData,
        options: Options(
          sendTimeout: const Duration(minutes: 5),
          receiveTimeout: const Duration(minutes: 5),
        ),
      );

      _dio.options.headers['Content-Type'] = originalContentType;

      if (response.statusCode == 200 && response.data['success'] == true) {
        return (response.data['url'] as String?, null);
      }
      return (null, 'Server rejected the upload (${response.statusCode})');
    } on DioException catch (e) {
      final message = _friendlyDioError(e);
      _logger.w('Photo upload failed for $localPath: $message (${e.type}) ${e.message}');
      return (null, message);
    } catch (e) {
      _logger.w('Photo upload failed for $localPath: $e');
      return (null, 'Unexpected error while uploading');
    }
  }

  /// Turns a Dio failure into something a field user can act on
  String _friendlyDioError(DioException e) {
    switch (e.type) {
      case DioExceptionType.connectionError:
        return 'No connection to the server';
      case DioExceptionType.connectionTimeout:
        return 'Could not reach the server, check your connection';
      case DioExceptionType.sendTimeout:
      case DioExceptionType.receiveTimeout:
        return 'Timed out on a weak connection, will retry';
      case DioExceptionType.badCertificate:
        return 'Secure connection failed';
      case DioExceptionType.cancel:
        return 'Upload was cancelled';
      case DioExceptionType.badResponse:
        return _friendlyStatusError(e);
      case DioExceptionType.unknown:
        return 'Could not upload, will retry';
    }
  }

  String _friendlyStatusError(DioException e) {
    final status = e.response?.statusCode;
    // The backend sends a usable reason for 400/503, prefer it over a guess
    final detail = e.response?.data is Map ? e.response?.data['detail']?.toString() : null;
    if (status == 401 || status == 403) return 'Signed out, please sign in again';
    if (status == 413) return 'Photo is too large to upload';
    if (status == 400) return detail ?? 'Server rejected the photo';
    if (status == 503) return 'Photo storage is unavailable, will retry';
    if (status != null && status >= 500) return 'Server error, will retry';
    return detail ?? 'Upload failed (${status ?? 'no response'})';
  }

  Future<MultipartFile?> _multipartFileFromPath(String path) async {
    try {
      return await MultipartFile.fromFile(path);
    } catch (e) {
      _logger.w('Could not read photo file $path: $e');
      return null;
    }
  }

  // Lets an admin pull a device's data without physical access to it
  Future<({bool success, String? name, String? error})> uploadRecoveryBundle(
    String bundlePath, {
    void Function(int sent, int total)? onProgress,
  }) async {
    if (_authToken == null) {
      return (success: false, name: null, error: 'Sign in before uploading');
    }

    try {
      final file = await _multipartFileFromPath(bundlePath);
      if (file == null) {
        return (success: false, name: null, error: 'Could not read the bundle');
      }

      final formData = FormData.fromMap({'file': file});

      // Same dance as _uploadPhoto: the auth interceptor forces JSON, which
      // would clobber Dio's multipart boundary
      final originalContentType = _dio.options.headers['Content-Type'];
      _dio.options.headers.remove('Content-Type');

      try {
        final response = await _dio.post(
          '/api/v1/recovery/bundles',
          data: formData,
          onSendProgress: onProgress,
          options: Options(
            contentType: 'multipart/form-data',
            // A day of plots and photos over a field hotspot is not a 60s job
            sendTimeout: const Duration(minutes: 30),
            receiveTimeout: const Duration(minutes: 10),
          ),
        );

        if (response.statusCode == 200 && response.data['success'] == true) {
          return (
            success: true,
            name: response.data['name'] as String?,
            error: null,
          );
        }
        return (
          success: false,
          name: null,
          error: 'Server rejected the upload (${response.statusCode})',
        );
      } finally {
        _dio.options.headers['Content-Type'] = originalContentType;
      }
    } on DioException catch (e) {
      final message = _friendlyDioError(e);
      _logger.w('Recovery bundle upload failed: $message (${e.type})');
      return (success: false, name: null, error: message);
    } catch (e) {
      _logger.w('Recovery bundle upload failed: $e');
      return (success: false, name: null, error: 'Unexpected error: $e');
    }
  }

  /// Set authentication token for API requests
  void setAuthToken(String token) {
    _authToken = token;
  }

  /// Clear authentication token
  void clearAuthToken() {
    _authToken = null;
    stopAutoSync();
  }

  /// Start listening for connectivity changes and retry pending uploads
  /// when the device comes back online. Also fires immediately if online.
  void startAutoSync() {
    _connectivitySub?.cancel();

    // Attempt sync now in case there are pending items and we're already online
    uploadAllPendingOutings();

    _connectivitySub = _connectivity.onConnectivityChanged.listen((results) {
      final isOnline = results.contains(ConnectivityResult.mobile) ||
          results.contains(ConnectivityResult.wifi) ||
          results.contains(ConnectivityResult.ethernet);
      if (isOnline) {
        _logger.i('Connectivity restored — retrying pending uploads');
        uploadAllPendingOutings();
      }
    });
  }

  /// Stop the connectivity listener (call on logout).
  void stopAutoSync() {
    _connectivitySub?.cancel();
    _connectivitySub = null;
  }

  /// Check if device has internet connectivity
  Future<bool> hasConnectivity() async {
    final connectivityResult = await _connectivity.checkConnectivity();
    return connectivityResult.contains(ConnectivityResult.mobile) ||
        connectivityResult.contains(ConnectivityResult.wifi) ||
        connectivityResult.contains(ConnectivityResult.ethernet);
  }

  /// Perform full sync: upload pending field outings
  ///
  /// This is the main sync method that should be called periodically
  /// or when user manually triggers sync.
  ///
  /// Returns a map with sync results:
  /// - 'success': whether sync completed successfully
  /// - 'uploaded': number of items uploaded
  Future<Map<String, dynamic>> performFullSync(int orgId) async {
    _logger.i('Starting full sync for org: $orgId');

    final result = {
      'success': false,
      'uploaded': 0,
      'error': null,
    };

    try {
      if (!await hasConnectivity()) {
        result['error'] = 'No internet connectivity';
        return result;
      }

      // Upload pending field outings with all child records
      final uploadCount = await uploadAllPendingOutings();
      result['uploaded'] = uploadCount;

      // Update sync state
      await _updateSyncState(orgId);

      result['success'] = true;
      _logger.i('Full sync completed successfully');
    } catch (e) {
      _logger.e('Error during full sync: $e');
      result['error'] = e.toString();
    }

    return result;
  }

  /// Update sync state metadata
  Future<void> _updateSyncState(int orgId) async {
    final db = await _db.database;
    await db.rawUpdate('''
      UPDATE sync_state
      SET last_full_sync = ?,
          updated_at = ?
      WHERE id = 1
    ''', [
      DateTime.now().toIso8601String(),
      DateTime.now().toIso8601String(),
    ]);
  }

  /// Get count of pending field outings
  Future<int> getPendingItemsCount() async {
    final db = await _db.database;
    final result = await db.rawQuery(
      'SELECT COUNT(*) as count FROM field_outings WHERE sync_status = ? AND is_draft = ?',
      ['pending', 0],
    );
    return result.isNotEmpty ? (result.first['count'] as int? ?? 0) : 0;
  }

  /// Get last sync timestamp
  Future<DateTime?> getLastSyncTime() async {
    final db = await _db.database;
    final result = await db.query(
      'sync_state',
      columns: ['last_full_sync'],
      where: 'id = ?',
      whereArgs: [1],
      limit: 1,
    );

    if (result.isEmpty || result.first['last_full_sync'] == null) {
      return null;
    }

    return DateTime.parse(result.first['last_full_sync'] as String);
  }
}

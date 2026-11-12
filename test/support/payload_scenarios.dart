import 'dart:convert';
import 'package:sqflite/sqflite.dart' show Database;
import 'sync_harness.dart';

typedef ScenarioSeed = Future<int> Function(SyncHarness harness, String photoPath);

class PayloadScenario {
  const PayloadScenario(this.name, this.seed);

  final String name;
  final ScenarioSeed seed;
}

String _species(List<(String, num)> observations) =>
    jsonEncode([for (final (code, cover) in observations) {'species_code': code, 'percentage_cover': cover}]);

Future<int> _outing(Database db, String localId, Map<String, Object?> overrides) => db.insert('field_outings', {
      'local_id': localId,
      'org_id': 1,
      'site_name': 'Plum Island',
      'monitoring_type': 'vegetation',
      'start_time': '2026-07-01T09:00:00',
      'end_time': '2026-07-01T11:30:00',
      'submission_time': '2026-07-01T11:45:00',
      'is_draft': 0,
      'sync_status': 'pending',
      ...overrides,
    });

Future<void> _plot(Database db, int outingId, String localId, Map<String, Object?> overrides) => db.insert('vegetation_records', {
      'local_id': localId,
      'outing_id': outingId,
      'transect_id': 'T1',
      'plot_number': 1,
      'latitude': 42.1,
      'longitude': -71.2,
      'species_observations': _species([('SPAL', 60)]),
      'protocol_code': 'MassMarshVeg',
      'sync_status': 'pending',
      ...overrides,
    });

final payloadScenarios = <PayloadScenario>[
  PayloadScenario('vegetation_minimal', (h, photo) async {
    final db = await h.db;
    final id = await _outing(db, 'minimal-outing', {});
    await _plot(db, id, 'minimal-plot-1', {});
    return id;
  }),
  PayloadScenario('vegetation_full_massmarsh', (h, photo) async {
    final db = await h.db;
    final id = await _outing(db, 'full-outing', {
      'other_members': 'Sam Rivera, Jo Park',
      'latitude': 42.1,
      'longitude': -71.2,
      'visibility': 'public',
    });
    await _plot(db, id, 'full-plot-1', {
      'plot_id': 'PLT-01',
      'habitat_type': 'High Marsh',
      'distance_along_transect_m': 12.5,
      'accuracy_m': 4.2,
      'location_quality': 'gps_good',
      'plot_start_time': '2026-07-01T09:14:05-04:00',
      'plot_end_time': '2026-07-01T09:21:40-04:00',
      'elevation_m': 1.31,
      'canopy_height_m': 0.45,
      'thatch_height_m': 0.07,
      'species_observations': _species([('SPAL', 55), ('SPPAT', 30), ('BARE', 15)]),
      'notes': 'Dense stand, wrack at the edge',
    });
    await _plot(db, id, 'full-plot-2', {
      'plot_number': 2,
      'plot_id': 'PLT-02',
      'habitat_type': 'Low Marsh',
      'distance_along_transect_m': 25.0,
      'accuracy_m': 11.8,
      'location_quality': 'gps_fair',
      'canopy_height_m': 0.9,
      'thatch_height_m': 0.12,
      'species_observations': _species([('SPAL', 100)]),
    });
    return id;
  }),
  PayloadScenario('vegetation_uas_community', (h, photo) async {
    final db = await h.db;
    final id = await _outing(db, 'uas-outing', {'other_members': 'Pat Lee'});
    await _plot(db, id, 'uas-plot-1', {
      'transect_id': '',
      'protocol_code': 'UASCommunity',
      'subclass': 'High Marsh - Spartina patens dom.',
      'rtk_point_number': 'RTK-0042',
      'species_observations': _species([('SPPAT', 70), ('DISPI', 30)]),
    });
    return id;
  }),
  PayloadScenario('vegetation_manual_gps', (h, photo) async {
    final db = await h.db;
    final id = await _outing(db, 'manual-gps-outing', {});
    await _plot(db, id, 'manual-gps-plot-1', {'location_quality': 'manual', 'accuracy_m': null});
    return id;
  }),
  PayloadScenario('vegetation_with_photo', (h, photo) async {
    final db = await h.db;
    final id = await _outing(db, 'photo-outing', {});
    await _plot(db, id, 'photo-plot-1', {'photo_local_path': photo});
    await _plot(db, id, 'photo-plot-2', {'plot_number': 2});
    return id;
  }),
  PayloadScenario('vegetation_embargoed', (h, photo) async {
    final db = await h.db;
    final id = await _outing(db, 'embargo-outing', {'visibility': 'embargo', 'embargo_until': '2027-07-01T00:00:00'});
    await _plot(db, id, 'embargo-plot-1', {});
    return id;
  }),
  PayloadScenario('vegetation_edge_values', (h, photo) async {
    final db = await h.db;
    final id = await _outing(db, 'edge-outing', {});
    await _plot(db, id, 'edge-plot-1', {
      'distance_along_transect_m': -1.5,
      'canopy_height_m': 0.0,
      'thatch_height_m': 0.0,
      'species_observations': _species([('SPAL', 0), ('WATER', 100)]),
    });
    return id;
  }),
  PayloadScenario('hydrology_only', (h, photo) async {
    final db = await h.db;
    final id = await _outing(db, 'hydro-outing', {'monitoring_type': 'hydrology'});
    await db.insert('hydrology_records', {
      'local_id': 'hydro-1',
      'outing_id': id,
      'area_treatment': 'Treatment',
      'wlr_type': 'HOBO U20L',
      'serial_number': 'WLR-2201',
      'elevation_waypoint_type': 'Well top',
      'waypoint_number': 'WP-7',
      'rtk_elevation_navd88_m': 1.874,
      'time_water_elevation_taken': '2026-07-01T10:15:00',
      'water_above_below_nut_m': -0.12,
      'well_rim_to_water_m': 0.64,
      'well_rim_to_marsh_m': 0.31,
      'well_rim_to_sensor_m': 0.9,
      'well_length_m': 1.2,
      'notes': 'Sensor swapped',
      'sync_status': 'pending',
    });
    return id;
  }),
  PayloadScenario('elevation_only', (h, photo) async {
    final db = await h.db;
    final id = await _outing(db, 'elev-outing', {'monitoring_type': 'elevation'});
    for (var point = 1; point <= 2; point++) {
      await db.insert('elevation_records', {
        'local_id': 'elev-$point',
        'outing_id': id,
        'transect_id': 'T1',
        'point_number': point,
        'latitude': 42.1 + point / 10000,
        'longitude': -71.2,
        'accuracy_m': 0.02,
        'location_quality': 'gps_good',
        'elevation_navd88_m': 1.2 + point / 10,
        'feature_type': point == 1 ? 'Platform' : null,
        'sync_status': 'pending',
      });
    }
    return id;
  }),
];

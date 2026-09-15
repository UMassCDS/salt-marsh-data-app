import 'dart:convert';

import 'plot_data.dart';

String generatePlotId(String transectId, int plotNumber) {
  final padded = plotNumber.toString().padLeft(2, '0');
  return [transectId, padded].where((p) => p.isNotEmpty).join('_');
}

class HydrologyFields {
  final String? areaTreatment;
  final String? wlrType;
  final String serialNumber;
  final String waypointNumber;
  final double? rtkElevationNavd88M;
  final double? waterAboveBelowNutM;
  final double? wellRimToWaterM;
  final double? wellRimToMarshM;

  const HydrologyFields({
    this.areaTreatment,
    this.wlrType,
    required this.serialNumber,
    required this.waypointNumber,
    this.rtkElevationNavd88M,
    this.waterAboveBelowNutM,
    this.wellRimToWaterM,
    this.wellRimToMarshM,
  });
}

class ElevationFields {
  final String transectId;
  final int pointNumber;
  final double latitude;
  final double longitude;
  final double elevationNavd88M;
  final String? featureType;

  const ElevationFields({
    required this.transectId,
    required this.pointNumber,
    required this.latitude,
    required this.longitude,
    required this.elevationNavd88M,
    this.featureType,
  });
}

// Draft saves, final submission and autosave all build rows through here,
// so they can never drift apart
class DraftSnapshot {
  final String monitoringType;
  final String protocolCode;
  final List<PlotData> plots;
  final HydrologyFields? hydrology;
  final ElevationFields? elevation;

  // Held for the life of the form so repeated autosaves update one row
  final String singleRecordLocalId;

  const DraftSnapshot({
    required this.monitoringType,
    required this.singleRecordLocalId,
    this.protocolCode = 'MassMarshVeg',
    this.plots = const [],
    this.hydrology,
    this.elevation,
  });

  String? get childTable {
    switch (monitoringType) {
      case 'vegetation':
        return 'vegetation_records';
      case 'hydrology':
        return 'hydrology_records';
      case 'elevation':
        return 'elevation_records';
      default:
        return null;
    }
  }

  List<Map<String, dynamic>> toChildRows() {
    final now = DateTime.now().toIso8601String();

    switch (monitoringType) {
      case 'vegetation':
        return plots.map((plot) => _vegetationRow(plot, now)).toList();
      case 'hydrology':
        return hydrology == null ? [] : [_hydrologyRow(hydrology!, now)];
      case 'elevation':
        return elevation == null ? [] : [_elevationRow(elevation!, now)];
      default:
        return [];
    }
  }

  Map<String, dynamic> _vegetationRow(PlotData plot, String now) {
    final effectivePlotId = plot.plotId.isNotEmpty
        ? plot.plotId
        : generatePlotId(plot.transectId, plot.plotNumber);

    return {
      'local_id': plot.localId,
      'transect_id': plot.transectId,
      'plot_number': plot.plotNumber,
      'plot_id': effectivePlotId.isNotEmpty ? effectivePlotId : null,
      'habitat_type': plot.habitatType,
      'distance_along_transect_m': plot.distanceAlongTransect,
      'latitude': plot.latitude,
      'longitude': plot.longitude,
      'elevation_m': plot.elevation,
      'canopy_height_m': plot.canopyHeight,
      'thatch_height_m': plot.thatchHeight,
      'species_observations': jsonEncode(plot.species
          .map((s) => {
                'species_code': s.speciesCode,
                'percentage_cover': s.percentageCover,
              })
          .toList()),
      'photo_local_path': plot.photoPath,
      'notes': plot.notes,
      'protocol_code': protocolCode,
      'subclass': plot.subclass,
      'rtk_point_number': plot.rtkPointNumber,
      'sync_status': 'pending',
      'created_at': now,
      'updated_at': now,
    };
  }

  Map<String, dynamic> _hydrologyRow(HydrologyFields fields, String now) {
    return {
      'local_id': singleRecordLocalId,
      'area_treatment': fields.areaTreatment,
      'wlr_type': fields.wlrType,
      'serial_number': fields.serialNumber,
      'waypoint_number': fields.waypointNumber,
      'rtk_elevation_navd88_m': fields.rtkElevationNavd88M,
      'water_above_below_nut_m': fields.waterAboveBelowNutM,
      'well_rim_to_water_m': fields.wellRimToWaterM,
      'well_rim_to_marsh_m': fields.wellRimToMarshM,
      'sync_status': 'pending',
      'created_at': now,
      'updated_at': now,
    };
  }

  Map<String, dynamic> _elevationRow(ElevationFields fields, String now) {
    return {
      'local_id': singleRecordLocalId,
      'transect_id': fields.transectId,
      'point_number': fields.pointNumber,
      'latitude': fields.latitude,
      'longitude': fields.longitude,
      'elevation_navd88_m': fields.elevationNavd88M,
      'feature_type': fields.featureType,
      'sync_status': 'pending',
      'created_at': now,
      'updated_at': now,
    };
  }
}

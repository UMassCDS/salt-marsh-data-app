import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';

// Mutable, unlike the persisted SpeciesObservation in vegetation_record.dart
class PlotSpeciesEntry {
  String speciesCode;
  int percentageCover;

  PlotSpeciesEntry({
    required this.speciesCode,
    required this.percentageCover,
  });
}

class PlotData {
  // Assigned once, never regenerated - the server dedupes on this
  final String localId;
  String transectId;
  int plotNumber;
  String plotId;
  bool plotIdManuallySet;
  String habitatType;
  double distanceAlongTransect;
  double latitude;
  double longitude;
  double canopyHeight;
  double thatchHeight;
  double? elevation;
  String? notes;
  File? photoFile;
  String? photoPath;
  List<PlotSpeciesEntry> species;
  String? subclass;
  String? rtkPointNumber;
  final TextEditingController latController;
  final TextEditingController lngController;
  final TextEditingController plotIdController;
  final TextEditingController rtkPointNumberController;
  final Map<String, TextEditingController> pinnedControllers;
  final Map<String, TextEditingController> extraControllers;

  PlotData({
    String? localId,
    required this.transectId,
    required this.plotNumber,
    this.plotId = '',
    this.plotIdManuallySet = false,
    required this.habitatType,
    required this.distanceAlongTransect,
    required this.latitude,
    required this.longitude,
    required this.canopyHeight,
    required this.thatchHeight,
    this.elevation,
    this.notes,
    this.photoFile,
    this.photoPath,
    this.species = const [],
    this.subclass,
    this.rtkPointNumber,
    List<String> pinnedCodes = const ['SPALT', 'SPPAT', 'BARE', 'DEAD'],
  })  : localId = localId ?? 'veg_${const Uuid().v4()}',
        latController = TextEditingController(text: latitude == 0 ? '' : latitude.toString()),
        lngController = TextEditingController(text: longitude == 0 ? '' : longitude.toString()),
        plotIdController = TextEditingController(text: plotId),
        rtkPointNumberController = TextEditingController(text: rtkPointNumber ?? ''),
        pinnedControllers = Map.fromEntries(
          pinnedCodes.map((code) {
            final existing = species.where((s) => s.speciesCode == code);
            final text = existing.isNotEmpty ? existing.first.percentageCover.toString() : '';
            return MapEntry(code, TextEditingController(text: text));
          }),
        ),
        extraControllers = Map.fromEntries(
          species
              .where((s) => !Set.from(pinnedCodes).contains(s.speciesCode))
              .map((s) => MapEntry(
                    s.speciesCode,
                    TextEditingController(text: s.percentageCover.toString()),
                  )),
        );

  // Maps a vegetation_records DB row (as loaded when resuming a draft) into
  // a PlotData. photoPath alone isn't enough for the thumbnail to render -
  // that reads photoFile, which a freshly loaded draft never had a chance to
  // set, so this resolves it from disk here.
  factory PlotData.fromDraftRow(
    Map<String, dynamic> record, {
    List<String> pinnedCodes = const ['SPALT', 'SPPAT', 'BARE', 'DEAD'],
  }) {
    List<PlotSpeciesEntry> species = [];
    if (record['species_observations'] != null) {
      final speciesJson = jsonDecode(record['species_observations'] as String) as List;
      species = speciesJson
          .map((s) => PlotSpeciesEntry(
                speciesCode: s['species_code'] as String,
                percentageCover: s['percentage_cover'] as int,
              ))
          .toList();
    }

    final photoPath = record['photo_local_path'] as String?;
    final photoFile = photoPath != null && File(photoPath).existsSync()
        ? File(photoPath)
        : null;

    return PlotData(
      localId: record['local_id'] as String?,
      transectId: record['transect_id'] as String? ?? '',
      plotNumber: record['plot_number'] as int? ?? 1,
      plotId: record['plot_id'] as String? ?? '',
      plotIdManuallySet: (record['plot_id'] as String?)?.isNotEmpty ?? false,
      habitatType: record['habitat_type'] as String? ?? '',
      distanceAlongTransect: (record['distance_along_transect_m'] as num?)?.toDouble() ?? 0.0,
      latitude: (record['latitude'] as num?)?.toDouble() ?? 0.0,
      longitude: (record['longitude'] as num?)?.toDouble() ?? 0.0,
      canopyHeight: (record['canopy_height_m'] as num?)?.toDouble() ?? 0.0,
      thatchHeight: (record['thatch_height_m'] as num?)?.toDouble() ?? 0.0,
      elevation: (record['elevation_m'] as num?)?.toDouble(),
      notes: record['notes'] as String?,
      photoPath: photoPath,
      photoFile: photoFile,
      species: species,
      subclass: record['subclass'] as String?,
      rtkPointNumber: record['rtk_point_number'] as String?,
      pinnedCodes: pinnedCodes,
    );
  }

  void dispose() {
    latController.dispose();
    lngController.dispose();
    plotIdController.dispose();
    rtkPointNumberController.dispose();
    for (final c in pinnedControllers.values) {
      c.dispose();
    }
    for (final c in extraControllers.values) {
      c.dispose();
    }
  }
}

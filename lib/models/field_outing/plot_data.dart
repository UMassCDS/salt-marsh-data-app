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
  double? accuracyM;
  String? locationProvider;
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
    this.accuracyM,
    this.locationProvider,
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

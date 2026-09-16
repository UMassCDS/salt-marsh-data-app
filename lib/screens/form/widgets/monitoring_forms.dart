import 'package:flutter/material.dart';
import 'common_fields.dart';

class HydrologyForm extends StatelessWidget {
  final TextEditingController areaTreatmentController;
  final TextEditingController wlrTypeController;
  final TextEditingController serialNumberController;
  final TextEditingController waypointNumberController;
  final TextEditingController rtkElevationController;
  final TextEditingController waterAboveBelowController;
  final TextEditingController wellRimToWaterController;
  final TextEditingController wellRimToMarshController;

  const HydrologyForm({
    super.key,
    required this.areaTreatmentController,
    required this.wlrTypeController,
    required this.serialNumberController,
    required this.waypointNumberController,
    required this.rtkElevationController,
    required this.waterAboveBelowController,
    required this.wellRimToWaterController,
    required this.wellRimToMarshController,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SectionHeader('Hydrology Measurement Information'),
        AppTextField(areaTreatmentController, 'Area Treatment', Icons.eco, isOptional: true),
        AppTextField(wlrTypeController, 'WLR Type', Icons.water, isOptional: true),
        AppTextField(serialNumberController, 'Serial Number', Icons.fingerprint, isOptional: true),
        AppTextField(waypointNumberController, 'Waypoint Number', Icons.location_on, inputType: TextInputType.number),
        AppTextField(rtkElevationController, 'RTK Elevation (NAVD88 m)', Icons.height, inputType: TextInputType.number),
        AppTextField(waterAboveBelowController, 'Water Above/Below NUT (m)', Icons.water, inputType: TextInputType.number, isOptional: true),
        AppTextField(wellRimToWaterController, 'Well Rim to Water (m)', Icons.water, inputType: TextInputType.number, isOptional: true),
        AppTextField(wellRimToMarshController, 'Well Rim to Marsh (m)', Icons.water, inputType: TextInputType.number, isOptional: true),
      ],
    );
  }
}

class ElevationForm extends StatelessWidget {
  final TextEditingController transectIdController;
  final TextEditingController pointNumberController;
  final TextEditingController latitudeController;
  final TextEditingController longitudeController;
  final TextEditingController elevationNavd88Controller;
  final TextEditingController featureTypeController;

  const ElevationForm({
    super.key,
    required this.transectIdController,
    required this.pointNumberController,
    required this.latitudeController,
    required this.longitudeController,
    required this.elevationNavd88Controller,
    required this.featureTypeController,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SectionHeader('Elevation Point Information'),
        AppTextField(transectIdController, 'Transect ID', Icons.timeline),
        AppTextField(pointNumberController, 'Point Number', Icons.numbers, inputType: TextInputType.number),
        AppTextField(latitudeController, 'Latitude', Icons.location_on, inputType: TextInputType.number),
        AppTextField(longitudeController, 'Longitude', Icons.location_on, inputType: TextInputType.number),
        AppTextField(elevationNavd88Controller, 'Elevation (NAVD88 m)', Icons.landscape, inputType: TextInputType.number),
        AppTextField(featureTypeController, 'Feature Type', Icons.landscape, isOptional: true),
      ],
    );
  }
}

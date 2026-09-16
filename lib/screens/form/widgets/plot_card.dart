import 'package:flutter/material.dart';
import '../../../models/field_outing/plot_data.dart';
import '../../../services/protocol_service.dart';
import '../../../services/species_service.dart';
import '../../../utils/gps_quality.dart';
import '../../../utils/photo_viewer.dart';
import 'plot_text_field.dart';
import 'species_cover_input.dart';

class CollapsedPlotSummary extends StatelessWidget {
  final PlotData plot;
  final VoidCallback onTap;

  const CollapsedPlotSummary({super.key, required this.plot, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final label = plot.plotId.isNotEmpty
        ? plot.plotId
        : 'Plot ${plot.plotNumber}';

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(
            children: [
              if (plot.photoFile != null)
                Padding(
                  padding: const EdgeInsets.only(right: 12),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(6),
                    child: Image.file(
                      plot.photoFile!,
                      width: 40,
                      height: 40,
                      fit: BoxFit.cover,
                      cacheWidth: 80,
                    ),
                  ),
                ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Plot ${plot.plotNumber} · $label',
                        style: Theme.of(context)
                            .textTheme
                            .titleSmall
                            ?.copyWith(fontWeight: FontWeight.w600),
                        overflow: TextOverflow.ellipsis),
                    if (plot.species.isNotEmpty)
                      Text('${plot.species.length} species recorded',
                          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                color: colorScheme.onSurface.withValues(alpha: 0.6),
                              )),
                  ],
                ),
              ),
              Icon(Icons.expand_more, color: colorScheme.onSurface.withValues(alpha: 0.5)),
            ],
          ),
        ),
      ),
    );
  }
}

// Habitat type options for vegetation
const List<String> kHabitatOptions = [
  'Low Marsh',
  'High Marsh',
  'Pool',
  'Upper Edge',
  'Transition',
  'Panne',
  'Ditch'
];

class PlotCard extends StatelessWidget {
  final int index;
  final PlotData plot;
  final bool canDelete;
  final ProtocolDefinition? activeProtocol;
  final bool gpsCapturing;
  final double? gpsLiveAccuracy;
  final List<SpeciesItem> allSpecies;
  final VoidCallback onCollapse;
  final VoidCallback onDelete;
  final void Function(String field, String value) onFieldChanged;
  final VoidCallback onGetGpsLocation;
  final ValueChanged<String> onRtkChanged;
  final ValueChanged<String?> onSubclassChanged;
  final VoidCallback onRemovePhoto;
  final VoidCallback onTakePhoto;
  final VoidCallback onChoosePhoto;
  final VoidCallback onSpeciesChanged;

  const PlotCard({
    super.key,
    required this.index,
    required this.plot,
    required this.canDelete,
    required this.activeProtocol,
    required this.gpsCapturing,
    required this.gpsLiveAccuracy,
    required this.allSpecies,
    required this.onCollapse,
    required this.onDelete,
    required this.onFieldChanged,
    required this.onGetGpsLocation,
    required this.onRtkChanged,
    required this.onSubclassChanged,
    required this.onRemovePhoto,
    required this.onTakePhoto,
    required this.onChoosePhoto,
    required this.onSpeciesChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Plot header
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Plot ${plot.plotNumber}',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      icon: const Icon(Icons.expand_less),
                      tooltip: 'Collapse',
                      onPressed: onCollapse,
                    ),
                    if (canDelete)
                      IconButton(
                        icon: const Icon(Icons.delete, color: Colors.red),
                        onPressed: onDelete,
                      ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 12),

            // Plot fields — conditional per protocol
            if (!(activeProtocol?.isFieldHidden('transect_id') ?? false))
              PlotTextField(
                field: 'transectId',
                currentValue: plot.transectId,
                label: 'Transect ID',
                icon: Icons.timeline,
                onChanged: onFieldChanged,
              ),
            PlotTextField(
              field: 'plotId',
              currentValue: '',
              label: 'Plot ID (e.g. CB_T1_P1)',
              icon: Icons.tag,
              isOptional: true,
              controller: plot.plotIdController,
              onChanged: onFieldChanged,
            ),
            if (!(activeProtocol?.isFieldHidden('habitat_type') ?? false))
              PlotTextField(
                field: 'habitatType',
                currentValue: plot.habitatType,
                label: 'Habitat Type',
                icon: Icons.terrain,
                isDropdown: true,
                dropdownOptions: kHabitatOptions,
                onChanged: onFieldChanged,
              ),
            if (!(activeProtocol?.isFieldHidden('distance_along_transect_m') ?? false))
              PlotTextField(
                field: 'distanceAlongTransect',
                currentValue: plot.distanceAlongTransect == 0 ? '' : plot.distanceAlongTransect.toString(),
                label: 'Distance Along Transect (m)',
                icon: Icons.straighten,
                isNumber: true,
                onChanged: onFieldChanged,
              ),
            PlotTextField(
              field: 'latitude',
              currentValue: '',
              label: 'Latitude',
              icon: Icons.location_on,
              isNumber: true,
              controller: plot.latController,
              onChanged: onFieldChanged,
            ),
            PlotTextField(
              field: 'longitude',
              currentValue: '',
              label: 'Longitude',
              icon: Icons.location_on,
              isNumber: true,
              controller: plot.lngController,
              onChanged: onFieldChanged,
            ),

            // GPS Button + live/result accuracy indicator
            Builder(builder: (context) {
              final hasFix = plot.latitude != 0 || plot.longitude != 0;
              final tier = plot.locationQuality;
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(
                      height: 48,
                      child: ElevatedButton.icon(
                        onPressed: gpsCapturing ? null : onGetGpsLocation,
                        icon: gpsCapturing
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                              )
                            : const Icon(Icons.my_location),
                        label: Text(gpsCapturing
                            ? (gpsLiveAccuracy != null
                                ? 'Capturing… ±${gpsLiveAccuracy!.toStringAsFixed(0)} m'
                                : 'Capturing GPS…')
                            : (hasFix ? 'Recapture GPS Location' : 'Get GPS Location')),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.blue,
                          foregroundColor: Colors.white,
                        ),
                      ),
                    ),
                    if (!gpsCapturing && hasFix && plot.accuracyM != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 6),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Chip(
                              avatar: Icon(
                                tier == 'gps_good'
                                    ? Icons.check_circle
                                    : (tier == 'gps_fair' ? Icons.info : Icons.warning),
                                size: 18,
                                color: tier == 'gps_good'
                                    ? Colors.green
                                    : (tier == 'gps_fair' ? Colors.orange : Colors.red),
                              ),
                              label: Text(
                                '±${plot.accuracyM!.toStringAsFixed(0)} m · ${qualityLabel(tier ?? '')}',
                              ),
                              visualDensity: VisualDensity.compact,
                            ),
                            if (qualityHint(tier ?? '') != null)
                              Padding(
                                padding: const EdgeInsets.only(left: 12, top: 2),
                                child: Text(
                                  qualityHint(tier ?? '')!,
                                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                        color: tier == 'coarse' ? Colors.red.shade700 : Colors.orange.shade800,
                                      ),
                                ),
                              ),
                          ],
                        ),
                      ),
                  ],
                ),
              );
            }),

            if (!(activeProtocol?.isFieldHidden('canopy_height_m') ?? false))
              PlotTextField(
                field: 'canopyHeight',
                currentValue: plot.canopyHeight == 0 ? '' : plot.canopyHeight.toString(),
                label: 'Canopy Height (m)',
                icon: Icons.height,
                isNumber: true,
                allowNegative: false,
                onChanged: onFieldChanged,
              ),
            if (!(activeProtocol?.isFieldHidden('thatch_height_m') ?? false))
              PlotTextField(
                field: 'thatchHeight',
                currentValue: plot.thatchHeight == 0 ? '' : plot.thatchHeight.toString(),
                label: 'Thatch Height (m)',
                icon: Icons.height,
                isNumber: true,
                allowNegative: false,
                onChanged: onFieldChanged,
              ),
            if (!(activeProtocol?.isFieldHidden('elevation_navd88_m') ?? false))
              PlotTextField(
                field: 'elevation',
                currentValue: plot.elevation?.toString() ?? '',
                label: 'Elevation (m)',
                icon: Icons.landscape,
                isNumber: true,
                isOptional: true,
                onChanged: onFieldChanged,
              ),

            // UASCommunity extra fields
            if (activeProtocol?.hasExtraField('rtk_point_number') ?? false)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: TextFormField(
                  controller: plot.rtkPointNumberController,
                  decoration: const InputDecoration(
                    labelText: 'RTK Point #',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.pin_drop),
                  ),
                  onChanged: onRtkChanged,
                ),
              ),
            if (activeProtocol?.hasExtraField('subclass') ?? false)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: DropdownButtonFormField<String>(
                  key: ValueKey('subclass_${plot.localId}_${plot.subclass}'),
                  initialValue: plot.subclass,
                  decoration: const InputDecoration(
                    labelText: 'Subclass',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.category),
                  ),
                  isExpanded: true,
                  items: (activeProtocol!.subclassOptions ?? [])
                      .map((opt) => DropdownMenuItem(
                            value: opt,
                            child: Text(opt, overflow: TextOverflow.ellipsis),
                          ))
                      .toList(),
                  onChanged: onSubclassChanged,
                ),
              ),

            PlotTextField(
              field: 'notes',
              currentValue: plot.notes ?? '',
              label: 'Notes',
              icon: Icons.note,
              maxLines: 2,
              isOptional: true,
              onChanged: onFieldChanged,
            ),

            const SizedBox(height: 16),

            // Photo section
            Text(
              'Plot Photo',
              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            if (plot.photoFile != null)
              Stack(
                children: [
                  GestureDetector(
                    onTap: () => showFullScreenPhoto(context, plot.photoFile!),
                    child: Image.file(
                      plot.photoFile!,
                      height: 200,
                      width: double.infinity,
                      fit: BoxFit.cover,
                      // The file on disk stays full-resolution; only the
                      // decoded-for-display copy is downsized, since a 12MP
                      // photo decoded per plot is what likely OOM'd the app
                      cacheWidth: 800,
                    ),
                  ),
                  Positioned(
                    bottom: 8,
                    left: 8,
                    child: IgnorePointer(
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: Colors.black54,
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.zoom_in, color: Colors.white, size: 14),
                            SizedBox(width: 4),
                            Text('Tap to enlarge',
                                style: TextStyle(color: Colors.white, fontSize: 11)),
                          ],
                        ),
                      ),
                    ),
                  ),
                  Positioned(
                    top: 8,
                    right: 8,
                    child: IconButton(
                      icon: Icon(Icons.close, color: Colors.red[400]),
                      style: IconButton.styleFrom(
                        backgroundColor: Colors.white70,
                      ),
                      onPressed: onRemovePhoto,
                    ),
                  ),
                ],
              )
            else
              Container(
                height: 100,
                decoration: BoxDecoration(
                  border: Border.all(color: Colors.grey),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Center(
                  child: Text('No photo selected'),
                ),
              ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: onTakePhoto,
                    icon: const Icon(Icons.camera_alt),
                    label: const Text('Take Photo'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: onChoosePhoto,
                    icon: const Icon(Icons.image),
                    label: const Text('Choose Photo'),
                  ),
                ),
              ],
            ),

            const SizedBox(height: 16),
            Divider(),
            const SizedBox(height: 16),

            // Species observations
            SpeciesCoverInput(
              plot: plot,
              allSpecies: allSpecies,
              onChanged: onSpeciesChanged,
              coverIncrement: activeProtocol?.speciesConfig.coverIncrement ?? 1,
              pinnedCodes: activeProtocol?.speciesConfig.pinnedSpecies ?? const ['SPALT', 'SPPAT', 'BARE', 'DEAD'],
              require100Percent: activeProtocol?.speciesConfig.require100Percent ?? true,
            ),
          ],
        ),
      ),
    );
  }
}

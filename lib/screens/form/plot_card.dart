import 'package:flutter/material.dart';
import '../../models/field_outing/plot_data.dart';
import '../../services/protocol_service.dart';
import '../../services/species_service.dart';
import '../../utils/photo_viewer.dart';
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
  'Transition'
];

class PlotCard extends StatelessWidget {
  final int index;
  final PlotData plot;
  final bool canDelete;
  final ProtocolDefinition? activeProtocol;
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

  Widget _plotTextField(
    BuildContext context,
    String field,
    String currentValue,
    String label,
    IconData icon, {
    bool isNumber = false,
    bool isDropdown = false,
    bool isOptional = false,
    int maxLines = 1,
    List<String>? dropdownOptions,
    TextEditingController? controller,
  }) {
    if (isDropdown && dropdownOptions != null) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: DropdownButtonFormField<String>(
          initialValue: currentValue.isEmpty ? null : currentValue,
          items: dropdownOptions.map((option) {
            return DropdownMenuItem(
              value: option,
              child: Text(option),
            );
          }).toList(),
          onChanged: (value) {
            if (value != null) onFieldChanged(field, value);
          },
          decoration: InputDecoration(
            labelText: label,
            border: const OutlineInputBorder(),
            prefixIcon: Icon(icon),
          ),
          validator: (value) {
            if (!isOptional && (value == null || value.isEmpty)) {
              return 'This field is required';
            }
            return null;
          },
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: TextFormField(
        controller: controller,
        initialValue: controller != null ? null : currentValue,
        decoration: InputDecoration(
          labelText: label,
          border: const OutlineInputBorder(),
          prefixIcon: Icon(icon),
        ),
        keyboardType: isNumber ? TextInputType.number : TextInputType.text,
        maxLines: maxLines,
        onChanged: (value) => onFieldChanged(field, value),
        validator: (value) {
          if (!isOptional && (value == null || value.isEmpty)) {
            return 'This field is required';
          }
          return null;
        },
      ),
    );
  }

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
              _plotTextField(
                context,
                'transectId',
                plot.transectId,
                'Transect ID',
                Icons.timeline,
              ),
            _plotTextField(
              context,
              'plotId',
              '',
              'Plot ID (e.g. CB_T1_P1)',
              Icons.tag,
              isOptional: true,
              controller: plot.plotIdController,
            ),
            if (!(activeProtocol?.isFieldHidden('habitat_type') ?? false))
              _plotTextField(
                context,
                'habitatType',
                plot.habitatType,
                'Habitat Type',
                Icons.terrain,
                isDropdown: true,
                dropdownOptions: kHabitatOptions,
              ),
            if (!(activeProtocol?.isFieldHidden('distance_along_transect_m') ?? false))
              _plotTextField(
                context,
                'distanceAlongTransect',
                plot.distanceAlongTransect == 0 ? '' : plot.distanceAlongTransect.toString(),
                'Distance Along Transect (m)',
                Icons.straighten,
                isNumber: true,
              ),
            _plotTextField(
              context,
              'latitude',
              '',
              'Latitude',
              Icons.location_on,
              isNumber: true,
              controller: plot.latController,
            ),
            _plotTextField(
              context,
              'longitude',
              '',
              'Longitude',
              Icons.location_on,
              isNumber: true,
              controller: plot.lngController,
            ),

            // GPS Button
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: ElevatedButton.icon(
                onPressed: onGetGpsLocation,
                icon: const Icon(Icons.my_location),
                label: const Text('Get GPS Location'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.blue,
                  foregroundColor: Colors.white,
                ),
              ),
            ),

            if (!(activeProtocol?.isFieldHidden('canopy_height_m') ?? false))
              _plotTextField(
                context,
                'canopyHeight',
                plot.canopyHeight == 0 ? '' : plot.canopyHeight.toString(),
                'Canopy Height (m)',
                Icons.height,
                isNumber: true,
              ),
            if (!(activeProtocol?.isFieldHidden('thatch_height_m') ?? false))
              _plotTextField(
                context,
                'thatchHeight',
                plot.thatchHeight == 0 ? '' : plot.thatchHeight.toString(),
                'Thatch Height (m)',
                Icons.height,
                isNumber: true,
              ),
            if (!(activeProtocol?.isFieldHidden('elevation_navd88_m') ?? false))
              _plotTextField(
                context,
                'elevation',
                plot.elevation?.toString() ?? '',
                'Elevation (m)',
                Icons.landscape,
                isNumber: true,
                isOptional: true,
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

            _plotTextField(
              context,
              'notes',
              plot.notes ?? '',
              'Notes',
              Icons.note,
              maxLines: 2,
              isOptional: true,
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
            ),
          ],
        ),
      ),
    );
  }
}

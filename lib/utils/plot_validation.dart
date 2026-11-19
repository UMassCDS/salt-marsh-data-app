import '../constants/species_constants.dart';
import '../models/field_outing/plot_data.dart';
import '../services/protocol_service.dart';

const plotEnded = 'ended';
const plotEndedIncomplete = 'ended_incomplete';

int plotCoverTotal(PlotData plot) => plot.species
    .where((s) => !kCoverExcludedSpeciesCodes.contains(s.speciesCode))
    .fold<int>(0, (sum, s) => sum + s.percentageCover);

// Mirrors what the form requires at submit; distance 0 counts as blank there too until N/A exists
List<String> missingPlotFields(PlotData plot, ProtocolDefinition? protocol) {
  bool shown(String id) => !(protocol?.isFieldHidden(id) ?? false);
  final require100 = protocol?.speciesConfig.require100Percent ?? true;
  final total = plotCoverTotal(plot);
  return [
    if (shown('transect_id') && plot.transectId.trim().isEmpty) 'Transect ID',
    if (shown('habitat_type') && plot.habitatType.isEmpty) 'Habitat type',
    if (shown('distance_along_transect_m') && plot.distanceAlongTransect == 0) 'Distance along transect',
    if (plot.latitude == 0 && plot.longitude == 0) 'GPS location',
    if (shown('canopy_height_m') && plot.canopyHeightCm == null) 'Canopy height',
    if (shown('thatch_height_m') && plot.thatchHeightCm == null) 'Thatch height',
    if (plot.species.isEmpty) 'Species cover',
    if (plot.species.isNotEmpty && require100 && total != 100) 'Cover adds up to $total%, not 100%',
  ];
}

// Every press moves the end time to now; later edits never do
void endPlot(PlotData plot, DateTime now, {required bool complete}) {
  plot.plotStartTime ??= now;
  plot.plotEndTime = now;
  plot.endState = complete ? plotEnded : plotEndedIncomplete;
}

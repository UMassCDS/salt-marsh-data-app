import '../models/field_outing/plot_data.dart';

// Pre-filled values (transect, plot id, RTK number) are left out: they are set before anyone stands at the plot
bool plotHasEnteredData(PlotData plot) =>
    plot.species.isNotEmpty ||
    plot.canopyHeight != 0 ||
    plot.thatchHeight != 0 ||
    plot.latitude != 0 ||
    plot.longitude != 0 ||
    plot.distanceAlongTransect != 0 ||
    plot.habitatType.isNotEmpty ||
    (plot.notes?.isNotEmpty ?? false) ||
    plot.photoPath != null ||
    plot.photoFile != null ||
    plot.elevation != null ||
    (plot.subclass?.isNotEmpty ?? false);

// Times are only ever filled in, never replaced, so a time set by hand survives every later call
bool updatePlotTimes(List<PlotData> plots, DateTime now) {
  var changed = false;
  for (final plot in plots) {
    if (plot.plotStartTime != null || !plotHasEnteredData(plot)) continue;
    for (final other in plots) {
      if (!identical(other, plot) && other.plotStartTime != null && other.plotEndTime == null) {
        other.plotEndTime = now;
      }
    }
    plot.plotStartTime = now;
    changed = true;
  }
  return changed;
}

void endOpenPlots(List<PlotData> plots, DateTime now) {
  for (final plot in plots) {
    if (plot.plotStartTime != null && plot.plotEndTime == null) plot.plotEndTime = now;
  }
}

DateTime? earliestPlotStart(List<PlotData> plots) {
  final starts = plots.map((p) => p.plotStartTime).whereType<DateTime>().toList()..sort();
  return starts.isEmpty ? null : starts.first;
}

String isoWithOffset(DateTime time) {
  final local = time.toLocal();
  final offset = local.timeZoneOffset;
  String two(int n) => n.toString().padLeft(2, '0');
  final sign = offset.isNegative ? '-' : '+';
  final hours = two(offset.inHours.abs());
  final minutes = two(offset.inMinutes.abs() % 60);
  return '${local.toIso8601String().split('.').first}$sign$hours:$minutes';
}

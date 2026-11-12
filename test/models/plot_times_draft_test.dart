import 'package:flutter_test/flutter_test.dart';
import 'package:mass_marsh_app/models/field_outing/draft_snapshot.dart';
import 'package:mass_marsh_app/models/field_outing/plot_data.dart';

void main() {
  test('plot times survive saving a draft and opening it again', () {
    final start = DateTime(2026, 7, 1, 9, 14, 5);
    final end = DateTime(2026, 7, 1, 9, 21, 40);
    final plot = PlotData(
      transectId: 'T1',
      plotNumber: 1,
      habitatType: '',
      distanceAlongTransect: 0,
      latitude: 0,
      longitude: 0,
      canopyHeight: 0.4,
      thatchHeight: 0,
      species: [],
      plotStartTime: start,
      plotEndTime: end,
    );
    final unstarted = PlotData(
      transectId: 'T1', plotNumber: 2, habitatType: '', distanceAlongTransect: 0,
      latitude: 0, longitude: 0, canopyHeight: 0, thatchHeight: 0, species: [],
    );

    final rows = DraftSnapshot(monitoringType: 'vegetation', singleRecordLocalId: 'x', plots: [plot, unstarted]).toChildRows();

    expect(rows.first['plot_start_time'], matches(RegExp(r'^2026-07-01T09:14:05[+-]\d{2}:\d{2}$')));
    final reopened = PlotData.fromDraftRow(rows.first);
    expect(reopened.plotStartTime!.isAtSameMomentAs(start), isTrue);
    expect(reopened.plotEndTime!.isAtSameMomentAs(end), isTrue);
    expect((rows.last['plot_start_time'], rows.last['plot_end_time']), (null, null));
    expect(PlotData.fromDraftRow(rows.last).plotStartTime, isNull);
  });
}

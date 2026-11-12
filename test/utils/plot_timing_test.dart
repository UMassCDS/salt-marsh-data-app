import 'package:flutter_test/flutter_test.dart';
import 'package:mass_marsh_app/models/field_outing/plot_data.dart';
import 'package:mass_marsh_app/utils/plot_timing.dart';

PlotData emptyPlot(int number) => PlotData(
      transectId: 'T1',
      plotNumber: number,
      plotId: 'T1_0$number',
      habitatType: '',
      distanceAlongTransect: 0,
      latitude: 0,
      longitude: 0,
      canopyHeight: 0,
      thatchHeight: 0,
      species: [],
      rtkPointNumber: '7',
    );

void main() {
  final t1 = DateTime(2026, 7, 1, 9, 14, 5);
  final t2 = DateTime(2026, 7, 1, 9, 21, 40);
  final t3 = DateTime(2026, 7, 1, 9, 30);

  group('a plot starts', () {
    test('when the first value is entered', () {
      final plot = emptyPlot(1);
      updatePlotTimes([plot], t1);
      expect(plot.plotStartTime, isNull, reason: 'pre-filled transect, plot id and RTK number do not count');

      plot.canopyHeight = 0.4;
      expect(updatePlotTimes([plot], t2), isTrue);
      expect(plot.plotStartTime, t2);
    });

    for (final (name, fill) in <(String, void Function(PlotData))>[
      ('species', (p) => p.species = [PlotSpeciesEntry(speciesCode: 'SPALT', percentageCover: 60)]),
      ('thatch height', (p) => p.thatchHeight = 0.07),
      ('a GPS fix', (p) => p.latitude = 42.1),
      ('distance along the transect', (p) => p.distanceAlongTransect = -3),
      ('habitat', (p) => p.habitatType = 'Panne'),
      ('notes', (p) => p.notes = 'mud'),
      ('a photo', (p) => p.photoPath = '/tmp/p.jpg'),
      ('elevation', (p) => p.elevation = 1.2),
      ('subclass', (p) => p.subclass = 'Pool'),
    ]) {
      test('when $name is entered', () {
        final plot = emptyPlot(1);
        fill(plot);
        updatePlotTimes([plot], t1);
        expect(plot.plotStartTime, t1);
      });
    }

    test('only once: later edits do not move the start', () {
      final plot = emptyPlot(1)..canopyHeight = 0.4;
      updatePlotTimes([plot], t1);
      plot.thatchHeight = 0.07;
      expect(updatePlotTimes([plot], t2), isFalse);
      expect(plot.plotStartTime, t1);
    });
  });

  group('a plot ends', () {
    test('when the next plot starts', () {
      final first = emptyPlot(1)..canopyHeight = 0.4;
      final second = emptyPlot(2);
      updatePlotTimes([first, second], t1);

      second.canopyHeight = 0.3;
      updatePlotTimes([first, second], t2);

      expect(first.plotEndTime, t2);
      expect(second.plotStartTime, t2);
      expect(second.plotEndTime, isNull);
    });

    test('going back to an earlier plot changes neither plot', () {
      final first = emptyPlot(1)..canopyHeight = 0.4;
      final second = emptyPlot(2);
      updatePlotTimes([first, second], t1);
      second.canopyHeight = 0.3;
      updatePlotTimes([first, second], t2);

      first.notes = 'fixed a typo';
      updatePlotTimes([first, second], t3);

      expect((first.plotStartTime, first.plotEndTime), (t1, t2));
      expect((second.plotStartTime, second.plotEndTime), (t2, null));
    });

    test('the last plot ends when the session ends; plots never started stay empty', () {
      final first = emptyPlot(1)..canopyHeight = 0.4;
      final untouched = emptyPlot(2);
      updatePlotTimes([first, untouched], t1);

      endOpenPlots([first, untouched], t3);

      expect(first.plotEndTime, t3);
      expect((untouched.plotStartTime, untouched.plotEndTime), (null, null));
    });

    test('a time set by hand is never overwritten', () {
      final plot = emptyPlot(1)
        ..canopyHeight = 0.4
        ..plotStartTime = t1
        ..plotEndTime = t2;
      endOpenPlots([plot], t3);
      updatePlotTimes([plot], t3);
      expect((plot.plotStartTime, plot.plotEndTime), (t1, t2));
    });
  });

  test('the session starts when its first plot started', () {
    final first = emptyPlot(1)..plotStartTime = t2;
    final second = emptyPlot(2)..plotStartTime = t1;
    expect(earliestPlotStart([first, second, emptyPlot(3)]), t1);
    expect(earliestPlotStart([emptyPlot(1)]), isNull);
  });

  test('times are written with the device UTC offset so they line up with RTK logs', () {
    final local = DateTime(2026, 7, 1, 9, 14, 5, 123);
    final written = isoWithOffset(local);

    expect(written, matches(RegExp(r'^2026-07-01T09:14:05[+-]\d{2}:\d{2}$')));
    expect(DateTime.parse(written).isAtSameMomentAs(DateTime(2026, 7, 1, 9, 14, 5)), isTrue);
  });
}

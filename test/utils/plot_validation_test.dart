import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mass_marsh_app/models/field_outing/draft_snapshot.dart';
import 'package:mass_marsh_app/models/field_outing/plot_data.dart';
import 'package:mass_marsh_app/screens/form/widgets/end_plot.dart';
import 'package:mass_marsh_app/services/protocol_service.dart';
import 'package:mass_marsh_app/utils/plot_validation.dart';

PlotData completePlot() => PlotData(
      transectId: 'T1',
      plotNumber: 1,
      habitatType: 'High Marsh',
      distanceAlongTransect: 10,
      latitude: 42.1,
      longitude: -70.8,
      canopyHeightCm: 45,
      thatchHeightCm: 0,
      species: [PlotSpeciesEntry(speciesCode: 'SPPAT', percentageCover: 70), PlotSpeciesEntry(speciesCode: 'BARE', percentageCover: 30)],
    );

ProtocolDefinition protocol({List<String> hidden = const [], bool require100 = true}) => ProtocolDefinition(
      protocolCode: 'P',
      protocolName: 'P',
      version: '1',
      hiddenFields: hidden,
      plotExtraFields: const [],
      speciesConfig: ProtocolSpeciesConfig(pinnedSpecies: const [], require100Percent: require100, coverIncrement: 1, minSpecies: 0),
    );

void main() {
  group('missing values', () {
    test('a complete plot has none, and a measured 0 cm thatch counts as entered', () {
      expect(missingPlotFields(completePlot(), protocol()), isEmpty);
    });

    test('blank fields, no GPS, no species are all listed', () {
      final plot = PlotData(transectId: '', plotNumber: 1, habitatType: '', distanceAlongTransect: 0, latitude: 0, longitude: 0, species: []);
      expect(missingPlotFields(plot, protocol()), [
        'Transect ID',
        'Habitat type',
        'Distance along transect',
        'GPS location',
        'Canopy height',
        'Thatch height',
        'Species cover',
      ]);
    });

    test('fields a protocol hides are never required', () {
      final plot = completePlot()
        ..transectId = ''
        ..habitatType = ''
        ..canopyHeightCm = null
        ..thatchHeightCm = null;
      final hidden = protocol(hidden: ['transect_id', 'habitat_type', 'canopy_height_m', 'thatch_height_m']);
      expect(missingPlotFields(plot, hidden), isEmpty);
    });

    test('cover must reach 100% only when the protocol asks for it, and water does not count', () {
      final plot = completePlot()
        ..species = [PlotSpeciesEntry(speciesCode: 'SPPAT', percentageCover: 60), PlotSpeciesEntry(speciesCode: 'WATER', percentageCover: 40)];
      expect(missingPlotFields(plot, protocol()), ['Cover adds up to 60%, not 100%']);
      expect(missingPlotFields(plot, protocol(require100: false)), isEmpty);
    });
  });

  group('ending a plot', () {
    final t1 = DateTime(2026, 7, 1, 9, 20);
    final t2 = DateTime(2026, 7, 1, 9, 25);

    test('sets the end time and marks it ended, or incomplete', () {
      final plot = completePlot()..plotStartTime = DateTime(2026, 7, 1, 9);
      endPlot(plot, t1, complete: true);
      expect((plot.plotEndTime, plot.endState), (t1, plotEnded));

      endPlot(plot, t2, complete: false);
      expect((plot.plotEndTime, plot.endState), (t2, plotEndedIncomplete));
      expect(plot.plotStartTime, DateTime(2026, 7, 1, 9));
    });

    test('a plot ended before anything was typed gets a start time too', () {
      final plot = completePlot();
      endPlot(plot, t1, complete: true);
      expect(plot.plotStartTime, t1);
    });

    test('the ended state survives saving a draft and opening it again', () {
      final plot = completePlot();
      endPlot(plot, t1, complete: false);
      final row = DraftSnapshot(monitoringType: 'vegetation', singleRecordLocalId: 'x', plots: [plot]).toChildRows().single;
      expect(row['plot_end_state'], plotEndedIncomplete);
      expect(PlotData.fromDraftRow(row).endState, plotEndedIncomplete);
    });
  });

  group('screens', () {
    Future<void> pump(WidgetTester tester, Widget child) =>
        tester.pumpWidget(MaterialApp(home: Scaffold(body: Builder(builder: (_) => child))));

    testWidgets('collapsed plots show whether they were ended', (tester) async {
      await pump(tester, const PlotEndStatus(endState: null, endTime: null));
      expect(find.text('Not ended'), findsOneWidget);
      await pump(tester, PlotEndStatus(endState: plotEnded, endTime: DateTime(2026, 7, 1, 9, 21)));
      expect(find.text('Ended 9:21 AM'), findsOneWidget);
      await pump(tester, const PlotEndStatus(endState: plotEndedIncomplete, endTime: null));
      expect(find.text('Ended, values missing'), findsOneWidget);
    });

    testWidgets('the missing-values dialog lists them and can end anyway or keep editing', (tester) async {
      bool? result;
      await pump(
        tester,
        Builder(
          builder: (context) => TextButton(
            onPressed: () async => result = await showEndPlotMissingDialog(context, 3, ['Canopy height', 'GPS location']),
            child: const Text('open'),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      expect(find.text('Plot 3 is missing 2 values'), findsOneWidget);
      expect(find.text('Canopy height'), findsOneWidget);

      await tester.tap(find.text('End anyway'));
      await tester.pumpAndSettle();
      expect(result, isTrue);

      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Keep editing'));
      await tester.pumpAndSettle();
      expect(result, isFalse);
    });
  });
}

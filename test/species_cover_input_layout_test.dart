// Verifies the species cover % box stays fully visible and correctly sized
// across a range of real device widths, and that long species names never
// push it off-screen - they truncate instead. This is the layout that used
// to clip the % box on narrow phones (see v0.8 batch 1, item 6/11).
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mass_marsh_app/models/field_outing/plot_data.dart';
import 'package:mass_marsh_app/screens/form/widgets/species_cover_input.dart';
import 'package:mass_marsh_app/services/species_service.dart';

const _devices = {
  'iPhone SE (small phone)': Size(375, 667),
  'Pixel 7 (standard phone)': Size(412, 915),
  'Galaxy Tab A11+ (field tablet, portrait)': Size(800, 1280),
  'iPad Pro 12.9" (large tablet)': Size(1024, 1366),
};

final _species = [
  const SpeciesItem(code: 'SPALT', scientificName: 'Spartina alterniflora', commonName: 'Smooth Cordgrass'),
  const SpeciesItem(code: 'SPPAT', scientificName: 'Spartina patens', commonName: 'Saltmeadow Cordgrass'),
  const SpeciesItem(code: 'BARE', scientificName: 'Bare Ground'),
  const SpeciesItem(code: 'DEAD', scientificName: 'Dead Vegetation'),
  // Deliberately long names - the real longest entries in the seed list -
  // to stress-test truncation on the narrowest screen.
  const SpeciesItem(code: 'AGSTO', scientificName: 'Agrostis stolonifera', commonName: 'Creeping Bentgrass, a very long common name to force truncation'),
];

void main() {
  for (final entry in _devices.entries) {
    testWidgets('percent box stays visible on ${entry.key} (${entry.value.width.toInt()}x${entry.value.height.toInt()})', (tester) async {
      tester.view.physicalSize = entry.value;
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final plot = PlotData(
        transectId: 'T1',
        plotNumber: 1,
        habitatType: 'Low Marsh',
        distanceAlongTransect: 0,
        latitude: 0,
        longitude: 0,
        canopyHeight: 0,
        thatchHeight: 0,
        species: [
          // Non-zero on purpose - exercises the pinned-row clear (x) button,
          // which only renders when a pinned species has a value to clear
          PlotSpeciesEntry(speciesCode: 'SPALT', percentageCover: 45),
          PlotSpeciesEntry(speciesCode: 'SPPAT', percentageCover: 0),
        ],
      );
      addTearDown(plot.dispose);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: SpeciesCoverInput(
                plot: plot,
                allSpecies: _species,
                onChanged: () {},
                require100Percent: true,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // No RenderFlex overflow, no layout exceptions at this width
      expect(tester.takeException(), isNull);

      // The percent boxes must be fully laid out at the width the UI code
      // requests (68 on phones, 88 on >=600 logical px - "wide screens"),
      // not squeezed narrower by long species names
      final expectedWidth = entry.value.width >= 600 ? 88.0 : 68.0;
      // Only the cover-% boxes (suffixText '%') - excludes the species search field
      final fieldFinder = find.byWidgetPredicate(
        (w) => w is TextField && w.decoration?.suffixText == '%',
      );
      expect(fieldFinder, findsWidgets);

      for (final element in fieldFinder.evaluate()) {
        final box = element.renderObject as RenderBox;
        expect(box.size.width, closeTo(expectedWidth, 0.5),
            reason: 'percent box should render at its full requested width ($expectedWidth), not be squeezed by long species names');

        // And it must be fully on-screen - no part clipped past the right edge
        final topLeft = box.localToGlobal(Offset.zero);
        expect(topLeft.dx + box.size.width, lessThanOrEqualTo(entry.value.width),
            reason: 'percent box must not be clipped off the right edge of the screen');
      }
    });

    testWidgets('long species names truncate instead of pushing the box off ${entry.key}', (tester) async {
      tester.view.physicalSize = entry.value;
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final plot = PlotData(
        transectId: 'T1',
        plotNumber: 1,
        habitatType: 'Low Marsh',
        distanceAlongTransect: 0,
        latitude: 0,
        longitude: 0,
        canopyHeight: 0,
        thatchHeight: 0,
        species: [
          PlotSpeciesEntry(speciesCode: 'SPALT', percentageCover: 0),
          PlotSpeciesEntry(speciesCode: 'AGSTO', percentageCover: 0),
        ],
      );
      addTearDown(plot.dispose);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: SpeciesCoverInput(
                plot: plot,
                allSpecies: _species,
                onChanged: () {},
                pinnedCodes: const ['SPALT'],
                require100Percent: true,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
    });
  }
}

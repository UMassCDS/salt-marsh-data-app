import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mass_marsh_app/models/field_outing/draft_snapshot.dart';
import 'package:mass_marsh_app/models/field_outing/plot_data.dart';
import 'package:mass_marsh_app/models/quadrat.dart';
import 'package:mass_marsh_app/screens/form/widgets/quadrat_picker.dart';
import 'package:mass_marsh_app/services/protocol_service.dart';

PlotData plot({double? width, double? length}) => PlotData(
      transectId: 'T1', plotNumber: 1, habitatType: '', distanceAlongTransect: 0,
      latitude: 0, longitude: 0, species: [], quadratWidthM: width, quadratLengthM: length,
    );

Map<String, dynamic> protocolResponse(Map<String, dynamic>? quadrat) => {
      'protocol_code': 'MassMarshVeg',
      'protocol_name': 'Veg',
      'definition': {'version': '1.0', 'quadrat_config': ?quadrat},
    };

void main() {
  group('the org default from the protocol', () {
    test('uses the org setting when the server sends one', () {
      final q = ProtocolDefinition.fromApiResponse(protocolResponse({'width_m': 0.25, 'length_m': 1.0, 'allow_override': false})).quadrat;
      expect((q.widthM, q.lengthM, q.allowOverride), (0.25, 1.0, false));
    });

    test('falls back to the SOP 0.5 m² square for older servers and the offline default', () {
      final q = ProtocolDefinition.fromApiResponse(protocolResponse(null)).quadrat;
      expect((q.widthM, q.lengthM, q.allowOverride), (0.71, 0.71, true));
      expect(ProtocolDefinition.massMarshVegDefault().quadrat.widthM, 0.71);
    });
  });

  test('plots without a size get the default and a chosen size is kept', () {
    final empty = plot();
    final chosen = plot(width: 0.25, length: 1.0);
    applyQuadratDefault([empty, chosen], const QuadratConfig(widthM: 1.0, lengthM: 1.0, allowOverride: true));
    expect((empty.quadratWidthM, empty.quadratLengthM), (1.0, 1.0));
    expect((chosen.quadratWidthM, chosen.quadratLengthM), (0.25, 1.0));
  });

  test('the size survives saving a draft and opening it again', () {
    final row = DraftSnapshot(monitoringType: 'vegetation', singleRecordLocalId: 'x', plots: [plot(width: 0.25, length: 1.0)]).toChildRows().single;
    expect((row['quadrat_width_m'], row['quadrat_length_m']), (0.25, 1.0));
    final reopened = PlotData.fromDraftRow(row);
    expect((reopened.quadratWidthM, reopened.quadratLengthM), (0.25, 1.0));
  });

  test('labels show size and area', () {
    expect(quadratLabel(0.71, 0.71), '0.71 × 0.71 m (0.50 m²)');
    expect(quadratLabel(0.25, 1.0), '0.25 × 1.0 m (0.25 m²)');
    expect(quadratLabel(null, null), 'Quadrat not set');
  });

  group('picker', () {
    Future<(double, double)?> pick(WidgetTester tester, Future<void> Function() act) async {
      (double, double)? result;
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: QuadratChip(widthM: 0.71, lengthM: 0.71, onChanged: (w, l) => result = (w, l)),
        ),
      ));
      await tester.tap(find.byType(ActionChip));
      await tester.pumpAndSettle();
      await act();
      await tester.pumpAndSettle();
      return result;
    }

    testWidgets('choosing the ditch frame preset sets 0.25 × 1.0 m', (tester) async {
      final result = await pick(tester, () => tester.tap(find.text('0.25 m² ditch frame')));
      expect(result, (0.25, 1.0));
    });

    testWidgets('a custom size needs both sides and is used as typed', (tester) async {
      final result = await pick(tester, () async {
        final button = find.widgetWithText(FilledButton, 'Use custom size');
        await tester.enterText(find.widgetWithText(TextField, 'Width (m)'), '');
        await tester.pump();
        expect(tester.widget<FilledButton>(button).onPressed, isNull);
        await tester.enterText(find.widgetWithText(TextField, 'Width (m)'), '0.2');
        await tester.enterText(find.widgetWithText(TextField, 'Length (m)'), '0.25');
        await tester.pump();
        await tester.ensureVisible(button);
        await tester.tap(button);
      });
      expect(result, (0.2, 0.25));
    });
  });
}

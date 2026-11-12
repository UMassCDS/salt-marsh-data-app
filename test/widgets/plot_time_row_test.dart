import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mass_marsh_app/screens/form/widgets/plot_time_row.dart';

void main() {
  testWidgets('shows the recorded times and lets the user correct one', (tester) async {
    DateTime? picked;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: PlotTimeRow(
          start: DateTime(2026, 7, 1, 9, 14),
          end: null,
          onStartChanged: (t) => picked = t,
          onEndChanged: (_) {},
        ),
      ),
    ));

    expect(find.textContaining('9:14 AM'), findsOneWidget);
    expect(find.textContaining('not yet'), findsOneWidget);

    await tester.tap(find.textContaining('Started'));
    await tester.pumpAndSettle();
    expect(find.byType(TimePickerDialog), findsOneWidget);
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();

    expect(picked, DateTime(2026, 7, 1, 9, 14));
  });
}

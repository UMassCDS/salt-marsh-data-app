import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mass_marsh_app/screens/home/update_banner.dart';
import 'package:mass_marsh_app/services/update_check.dart';

class _FakeChecker extends UpdateChecker {
  _FakeChecker(this._update) : super(enabled: true);
  AvailableUpdate? _update;
  String? dismissed;

  @override
  Future<AvailableUpdate?> check() async => _update?.version == dismissed ? null : _update;

  @override
  Future<void> dismiss(String version) async => dismissed = version;
}

Widget _app(UpdateChecker checker) => ProviderScope(
      overrides: [updateCheckerProvider.overrideWithValue(checker)],
      child: const MaterialApp(home: Scaffold(body: UpdateBanner())),
    );

void main() {
  testWidgets('offers a newer version and hides once dismissed', (tester) async {
    final checker = _FakeChecker(const AvailableUpdate('0.8.0', 'https://example.org/releases/v0.8.0'));
    await tester.pumpWidget(_app(checker));
    await tester.pumpAndSettle();

    expect(find.textContaining('0.8.0 is available'), findsOneWidget);
    expect(find.text('Download'), findsOneWidget);

    await tester.tap(find.text('Later'));
    await tester.pumpAndSettle();

    expect(checker.dismissed, '0.8.0');
    expect(find.textContaining('is available'), findsNothing);
  });

  testWidgets('shows nothing when the app is up to date', (tester) async {
    await tester.pumpWidget(_app(_FakeChecker(null)));
    await tester.pumpAndSettle();
    expect(find.byType(FilledButton), findsNothing);
  });
}

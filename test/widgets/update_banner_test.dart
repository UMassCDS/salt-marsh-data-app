import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mass_marsh_app/screens/home/update_banner.dart';
import 'package:mass_marsh_app/services/update_check.dart';

class _FakeChecker extends UpdateChecker {
  _FakeChecker(this._update) : super(enabled: true);
  final AvailableUpdate? _update;
  String? dismissed;

  @override
  Future<AvailableUpdate?> check() async {
    final update = _update;
    if (update == null) return null;
    return AvailableUpdate(update.version, update.url, installedVersion: update.installedVersion, dismissed: update.version == dismissed);
  }

  @override
  Future<void> dismiss(String version) async => dismissed = version;
}

Widget _app(UpdateChecker checker) => ProviderScope(
      overrides: [updateCheckerProvider.overrideWithValue(checker)],
      child: const MaterialApp(home: Scaffold(body: UpdateBanner())),
    );

void main() {
  testWidgets('offers a newer version and hides once dismissed', (tester) async {
    final checker = _FakeChecker(const AvailableUpdate('0.8.0', 'https://example.org/releases/v0.8.0', installedVersion: '0.7.0'));
    await tester.pumpWidget(_app(checker));
    await tester.pumpAndSettle();

    expect(find.text('New app version available'), findsOneWidget);
    expect(find.text('v0.7.0 → v0.8.0'), findsOneWidget);
    expect(find.text('Update'), findsOneWidget);

    await tester.tap(find.text('Later'));
    await tester.pumpAndSettle();

    expect(checker.dismissed, '0.8.0');
    expect(find.text('New app version available'), findsNothing);
  });

  testWidgets('the Settings card has no Later button and stays after dismissing', (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: ProviderScope(
        child: Scaffold(body: UpdateCard(update: AvailableUpdate('0.8.0', 'https://example.org', dismissed: true), showLater: false)),
      ),
    ));
    expect(find.text('Update'), findsOneWidget);
    expect(find.text('Later'), findsNothing);
  });

  testWidgets('shows nothing when the app is up to date', (tester) async {
    await tester.pumpWidget(_app(_FakeChecker(null)));
    await tester.pumpAndSettle();
    expect(find.byType(FilledButton), findsNothing);
  });
}

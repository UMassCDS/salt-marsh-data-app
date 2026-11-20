import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mass_marsh_app/screens/outings/widgets/record_card.dart';

Future<void> pumpCard(
  WidgetTester tester, {
  String? photoUrl,
  String? error,
  bool sessionUploaded = true,
  VoidCallback? onRetry,
  bool retrying = false,
}) async {
  final dir = Directory.systemTemp.createTempSync('record_card');
  addTearDown(() => dir.deleteSync(recursive: true));
  final file = File('${dir.path}/plot.jpg')..writeAsBytesSync(const [0xFF, 0xD8, 0xFF, 0xD9]);
  await tester.pumpWidget(MaterialApp(
    home: Scaffold(
      body: SingleChildScrollView(
        child: RecordCard(
          index: 1,
          record: {
            'photo_local_path': file.path,
            'photo_filename': photoUrl,
            'photo_upload_error': error,
          },
          sessionUploaded: sessionUploaded,
          onRetry: onRetry,
          retrying: retrying,
        ),
      ),
    ),
  ));
}

void main() {
  testWidgets('a photo waiting on its session says so and can be retried', (tester) async {
    var retried = 0;
    await pumpCard(tester, sessionUploaded: false, onRetry: () => retried++);

    expect(find.text('Waiting for the session to upload'), findsOneWidget);
    await tester.tap(find.text('Retry upload'));
    expect(retried, 1);
  });

  testWidgets('a photo whose session is on the server is pending and can be retried', (tester) async {
    await pumpCard(tester, onRetry: () {});

    expect(find.text('Photo pending upload'), findsOneWidget);
    expect(find.text('Retry upload'), findsOneWidget);
  });

  testWidgets('a failed photo shows the reason and can be retried', (tester) async {
    await pumpCard(tester, error: 'Server error', onRetry: () {});

    expect(find.text('Photo not uploaded'), findsOneWidget);
    expect(find.text('Server error'), findsOneWidget);
    expect(find.text('Retry upload'), findsOneWidget);
  });

  testWidgets('a synced photo has no retry button', (tester) async {
    await pumpCard(tester, photoUrl: 'https://example.com/plot.jpg', onRetry: () {});

    expect(find.text('Photo synced'), findsOneWidget);
    expect(find.text('Retry upload'), findsNothing);
  });

  testWidgets('without a retry action there is no button', (tester) async {
    await pumpCard(tester);

    expect(find.text('Retry upload'), findsNothing);
  });

  testWidgets('the button is disabled while a retry is running', (tester) async {
    await pumpCard(tester, onRetry: () {}, retrying: true);

    final button = tester.widget<TextButton>(find.ancestor(of: find.text('Retry upload'), matching: find.byType(TextButton)));
    expect(button.onPressed, isNull);
  });
}

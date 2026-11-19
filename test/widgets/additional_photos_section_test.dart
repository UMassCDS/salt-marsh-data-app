import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mass_marsh_app/models/field_outing/additional_photo.dart';
import 'package:mass_marsh_app/screens/form/widgets/additional_photos_section.dart';

void main() {
  testWidgets('shows each additional photo with a remove button and offers take and choose', (tester) async {
    final dir = Directory.systemTemp.createTempSync('extra_photos');
    addTearDown(() => dir.deleteSync(recursive: true));
    final file = File('${dir.path}/a.jpg')..writeAsBytesSync(const [0xFF, 0xD8, 0xFF, 0xD9]);
    String? removed;
    var taken = 0;

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: AdditionalPhotosSection(
          photos: [AdditionalPhoto(localId: 'p1', path: file.path)],
          onTake: () => taken++,
          onChoose: () {},
          onRemove: (id) => removed = id,
        ),
      ),
    ));

    expect(find.textContaining('Additional photos'), findsOneWidget);
    expect(find.textContaining('optional'), findsOneWidget);
    await tester.tap(find.byTooltip('Remove photo'));
    expect(removed, 'p1');
    await tester.tap(find.text('Take'));
    expect(taken, 1);
    expect(find.text('Choose'), findsOneWidget);
  });
}

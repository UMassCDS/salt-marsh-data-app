import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mass_marsh_app/screens/form/widgets/common_fields.dart';
import 'package:mass_marsh_app/services/session_defaults.dart';

void main() {
  late Map<String, String> storage;
  SessionDefaultsStore store() => SessionDefaultsStore(read: (k) async => storage[k], write: (k, v) async => storage[k] = v);

  setUp(() => storage = {});

  test('nothing saved yet gives empty defaults', () async {
    final d = await store().load(1);
    expect(d.siteName, isNull);
    expect(d.otherMembers, isNull);
  });

  test('the last submitted site and team come back for the same org only', () async {
    await store().save(1, siteName: ' Great Marsh ', otherMembers: 'Brad, Dave');
    final same = await store().load(1);
    expect(same.siteName, 'Great Marsh');
    expect(same.otherMembers, 'Brad, Dave');
    expect((await store().load(2)).siteName, isNull);
  });

  test('a broken saved value is ignored instead of crashing the form', () async {
    storage['session_defaults_1'] = 'not json';
    expect((await store().load(1)).siteName, isNull);
  });

  testWidgets('a clearable field shows a clear button only when it has text', (tester) async {
    final controller = TextEditingController(text: 'Great Marsh');
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: AppTextField(controller, 'Site Name', Icons.place, clearable: true))));
    expect(find.byTooltip('Clear Site Name'), findsOneWidget);

    await tester.tap(find.byTooltip('Clear Site Name'));
    await tester.pump();
    expect(controller.text, isEmpty);
    expect(find.byTooltip('Clear Site Name'), findsNothing);
  });
}

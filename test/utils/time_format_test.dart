import 'package:flutter_test/flutter_test.dart';
import 'package:mass_marsh_app/utils/time_format.dart';

void main() {
  test('session times shown in the form read back as the same time', () {
    for (final (hour, minute, text) in [(0, 5, '12:05 AM'), (9, 14, '9:14 AM'), (12, 0, '12:00 PM'), (23, 59, '11:59 PM')]) {
      final time = DateTime(2026, 7, 1, hour, minute);
      expect(formatClockTime(time), text);
      final parsed = parseTimeString(text)!;
      expect((parsed.hour, parsed.minute), (hour, minute), reason: text);
    }
  });
}

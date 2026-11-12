import 'package:flutter_test/flutter_test.dart';
import 'package:mass_marsh_app/utils/gps_fix.dart';

void main() {
  final t0 = DateTime(2026, 11, 12, 9);
  DateTime at(int seconds) => t0.add(Duration(seconds: seconds));

  test('nothing collected gives no result and never settles', () {
    final c = GpsFixCollector();
    expect(c.result(), isNull);
    expect(c.isSettled(at(60)), isFalse);
  });

  test('coarse and fair readings alone never stop the capture early', () {
    final c = GpsFixCollector()
      ..add(const GpsFix(42, -70, 30), at(0))
      ..add(const GpsFix(42, -70, 12), at(1));
    expect(c.isSettled(at(10)), isFalse);
    expect(c.result()!.accuracyM, 12);
  });

  test('one good reading is not enough on its own until the settle time passes', () {
    final c = GpsFixCollector()..add(const GpsFix(42, -70, 6), at(0));
    expect(c.isSettled(at(1)), isFalse);
    expect(c.isSettled(at(4)), isTrue);
  });

  test('three good readings settle straight away', () {
    final c = GpsFixCollector()
      ..add(const GpsFix(42, -70, 6), at(0))
      ..add(const GpsFix(42, -70, 7), at(1))
      ..add(const GpsFix(42, -70, 5), at(2));
    expect(c.isSettled(at(2)), isTrue);
  });

  test('close readings are averaged, weighted toward the more accurate ones', () {
    final c = GpsFixCollector()
      ..add(const GpsFix(42.00000, -70.00000, 4), at(0))
      ..add(const GpsFix(42.00004, -70.00004, 4), at(1));
    final r = c.result()!;
    expect(r.latitude, closeTo(42.00002, 1e-9));
    expect(r.longitude, closeTo(-70.00002, 1e-9));
    expect(r.accuracyM, 4);
  });

  test('much worse readings are left out of the average', () {
    final c = GpsFixCollector()
      ..add(const GpsFix(42.0, -70.0, 25), at(0))
      ..add(const GpsFix(42.001, -70.001, 5), at(1));
    final r = c.result()!;
    expect(r.latitude, 42.001);
    expect(r.longitude, -70.001);
  });
}

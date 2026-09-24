import 'package:flutter_test/flutter_test.dart';
import 'package:mass_marsh_app/config/env.dart';

void main() {
  test('kApiBaseUrl defaults to the prod API when not overridden by --dart-define', () {
    expect(kApiBaseUrl, 'https://saltmarshdata.org');
  });

  test('kFlavor defaults to prod when not overridden by --dart-define', () {
    expect(kFlavor, 'prod');
  });
}

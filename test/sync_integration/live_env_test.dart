import 'package:flutter_test/flutter_test.dart';
import '../support/live_env.dart';

void main() {
  group('refuseProduction', () {
    for (final url in [
      'https://saltmarshdata.org',
      'https://SaltMarshData.org/',
      'https://www.saltmarshdata.org',
      'https://massmarsh-backend.azurewebsites.net',
    ]) {
      test('refuses $url', () => expect(() => refuseProduction(url), throwsStateError));
    }

    for (final url in ['https://dev.saltmarshdata.org', 'http://127.0.0.1:8000', null]) {
      test('allows $url', () => expect(refuseProduction(url), url));
    }
  });

  group('credentialsFor', () {
    test('falls back to the demo users a seeded test backend has', () {
      expect(credentialsFor('viewer', env: {}), ('viewer@umass.edu', 'demo123'));
    });

    test('uses the accounts a shared server provides', () {
      final env = {'E2E_MANAGER_EMAIL': 'e2e-manager@example.org', 'E2E_MANAGER_PASSWORD': 's3cret'};
      expect(credentialsFor('manager', env: env), ('e2e-manager@example.org', 's3cret'));
    });
  });
}

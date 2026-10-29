import 'package:flutter_test/flutter_test.dart';

// Dart has no strict xfail: the test must keep failing, and goes red once the gap is fixed
void knownGapTest(String description, String gap, Future<void> Function() body) {
  test('$description [known gap]', () async {
    try {
      await body();
    } on TestFailure {
      return;
    }
    fail('Known gap now passes, turn this back into a normal test: $gap');
  });
}

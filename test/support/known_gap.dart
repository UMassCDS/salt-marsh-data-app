import 'package:flutter_test/flutter_test.dart';

bool _isAssertionFailure(Object error) => error is TestFailure;

// Dart has no strict xfail: the body must keep failing in the expected way, and goes red once the gap is fixed
Future<void> expectKnownGap(
  String gap,
  Future<void> Function() body, {
  bool Function(Object error) isExpected = _isAssertionFailure,
}) async {
  try {
    await body();
  } catch (error) {
    if (isExpected(error)) return;
    rethrow;
  }
  fail('Known gap now passes, turn this back into a normal test: $gap');
}

void knownGapTest(String description, String gap, Future<void> Function() body) {
  test('$description [known gap]', () => expectKnownGap(gap, body));
}

import 'dart:async';

// Announces that the server stopped accepting our token. One report per token, so a retry loop cannot sign the user out repeatedly.
class AuthRejections {
  static final instance = AuthRejections();

  final _controller = StreamController<void>.broadcast();
  bool _reported = false;

  Stream<void> get stream => _controller.stream;

  void report() {
    if (_reported) return;
    _reported = true;
    _controller.add(null);
  }

  void rearm() => _reported = false;
}

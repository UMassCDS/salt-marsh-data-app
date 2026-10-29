import 'dart:async';
import 'package:connectivity_plus/connectivity_plus.dart';

class FakeConnectivity implements Connectivity {
  List<ConnectivityResult> current;
  Object? checkError;
  int checksBeforeError = 0;
  final _changes = StreamController<List<ConnectivityResult>>.broadcast();

  FakeConnectivity({this.current = const [ConnectivityResult.wifi]});

  void set(List<ConnectivityResult> next) {
    current = next;
    _changes.add(next);
  }

  @override
  Future<List<ConnectivityResult>> checkConnectivity() async {
    if (checkError != null && checksBeforeError-- <= 0) throw checkError!;
    return current;
  }

  @override
  Stream<List<ConnectivityResult>> get onConnectivityChanged => _changes.stream;
}

import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';

// Android's default is one reading every 5 s, which gives only ~3 readings per capture
LocationSettings gpsStreamSettings(LocationAccuracy accuracy) {
  if (defaultTargetPlatform == TargetPlatform.android) {
    return AndroidSettings(accuracy: accuracy, intervalDuration: const Duration(seconds: 1));
  }
  return LocationSettings(accuracy: accuracy);
}

// Keeps the GPS receiver locked while the form is open so a capture does not start cold
class GpsWarmup {
  StreamSubscription<Position>? _sub;

  Future<void> start() async {
    if (_sub != null) return;
    try {
      if (!await Geolocator.isLocationServiceEnabled()) return;
      final permission = await Geolocator.checkPermission();
      if (permission != LocationPermission.always && permission != LocationPermission.whileInUse) return;
      if (_sub != null) return;
      _sub = Geolocator.getPositionStream(locationSettings: gpsStreamSettings(LocationAccuracy.best)).listen(
        (_) {},
        onError: (_) => stop(),
        cancelOnError: true,
      );
    } catch (_) {}
  }

  void stop() {
    _sub?.cancel();
    _sub = null;
  }
}

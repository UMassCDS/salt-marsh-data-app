import 'gps_quality.dart';

class GpsFix {
  const GpsFix(this.latitude, this.longitude, this.accuracyM);
  final double latitude;
  final double longitude;
  final double accuracyM;
}

// Collects live fixes and decides when to stop and which point to keep
class GpsFixCollector {
  GpsFixCollector({this.goodFixesWanted = 3, this.settleAfterFirstGood = const Duration(seconds: 4)});

  final int goodFixesWanted;
  final Duration settleAfterFirstGood;
  final List<GpsFix> _fixes = [];
  DateTime? _firstGoodAt;

  GpsFix? get best => _fixes.isEmpty ? null : _fixes.reduce((a, b) => b.accuracyM < a.accuracyM ? b : a);

  int get _goodCount => _fixes.where((f) => f.accuracyM <= gpsGoodAccuracyM).length;

  void add(GpsFix fix, DateTime now) {
    _fixes.add(fix);
    if (fix.accuracyM <= gpsGoodAccuracyM) _firstGoodAt ??= now;
  }

  // A single good reading can be a lucky outlier, so wait for a few or a short settle time
  bool isSettled(DateTime now) {
    final firstGood = _firstGoodAt;
    if (firstGood == null) return false;
    return _goodCount >= goodFixesWanted || now.difference(firstGood) >= settleAfterFirstGood;
  }

  // Weighted mean of the fixes close to the best one; accuracy reported is the best single fix
  GpsFix? result() {
    final top = best;
    if (top == null) return null;
    final cutoff = top.accuracyM * 1.5 > top.accuracyM + 2 ? top.accuracyM * 1.5 : top.accuracyM + 2;
    final used = _fixes.where((f) => f.accuracyM <= cutoff);
    var weightSum = 0.0, lat = 0.0, lon = 0.0;
    for (final f in used) {
      final w = 1 / (f.accuracyM * f.accuracyM).clamp(0.01, double.infinity);
      weightSum += w;
      lat += f.latitude * w;
      lon += f.longitude * w;
    }
    return GpsFix(lat / weightSum, lon / weightSum, top.accuracyM);
  }
}

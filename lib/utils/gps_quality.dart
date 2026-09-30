// Quality tiers inferred from accuracy, since geolocator's Position has
// no `provider` field to read on Android 12+ (fused always wins there).
const gpsGoodAccuracyM = 8.0;
const gpsFairAccuracyM = 20.0;

String qualityTierFor(double accuracyM) {
  if (accuracyM <= gpsGoodAccuracyM) return 'gps_good';
  if (accuracyM <= gpsFairAccuracyM) return 'gps_fair';
  return 'coarse';
}

String qualityLabel(String tier) => switch (tier) {
      'gps_good' => 'good',
      'gps_fair' => 'fair',
      'coarse' => 'coarse',
      _ => tier,
    };

// Shown persistently under the badge, not just in the one-time snackbar
String? qualityHint(String tier) => switch (tier) {
      'gps_fair' => 'Usable, but retry if you can',
      'coarse' => 'Likely WiFi/cell, not GPS - move to open sky and retry',
      _ => null,
    };

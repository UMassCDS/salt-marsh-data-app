// Quality tiers inferred from accuracy, since geolocator's Position has
// no `provider` field to read on Android 12+ (fused always wins there).
const gpsGoodAccuracyM = 8.0;
const gpsFairAccuracyM = 20.0;

const gpsTierGood = 'gps_good';
const gpsTierFair = 'gps_fair';
const gpsTierCoarse = 'coarse';

String qualityTierFor(double accuracyM) {
  if (accuracyM <= gpsGoodAccuracyM) return gpsTierGood;
  if (accuracyM <= gpsFairAccuracyM) return gpsTierFair;
  return gpsTierCoarse;
}

String qualityLabel(String tier) => switch (tier) {
      gpsTierGood => 'good',
      gpsTierFair => 'fair',
      gpsTierCoarse => 'coarse',
      _ => tier,
    };

// Shown persistently under the badge, not just in the one-time snackbar
String? qualityHint(String tier) => switch (tier) {
      gpsTierFair => 'Usable, but retry if you can',
      gpsTierCoarse => 'Likely WiFi/cell, not GPS - move to open sky and retry',
      _ => null,
    };

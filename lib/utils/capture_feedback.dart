import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'gps_quality.dart';

// Coarse gets only a stronger tap: no confirming sound, so it sends the user back to the screen rather than reading as success
Future<void> playCaptureFeedback(String qualityTier) => _play(() => [
      if (qualityTier != gpsTierCoarse) SystemSound.play(SystemSoundType.click),
      qualityTier == gpsTierCoarse ? HapticFeedback.mediumImpact() : HapticFeedback.lightImpact(),
    ]);

Future<void> playCaptureFailedFeedback() => _play(() => [HapticFeedback.heavyImpact()]);

Future<void> _play(List<Future<void>> Function() start) async {
  try {
    await Future.wait(start());
  } on PlatformException catch (e) {
    debugPrint('Capture feedback unavailable: $e');
  } on MissingPluginException catch (e) {
    debugPrint('Capture feedback unavailable: $e');
  }
}

import 'package:flutter/services.dart';

// Coarse gets only a stronger tap: no confirming sound, so it sends the user back to the screen rather than reading as success
Future<void> playCaptureFeedback(String qualityTier) async {
  try {
    if (qualityTier == 'coarse') {
      await HapticFeedback.mediumImpact();
      return;
    }
    await SystemSound.play(SystemSoundType.click);
    await HapticFeedback.lightImpact();
  } catch (_) {
    // Feedback is a convenience; a platform without it must not break capturing
  }
}

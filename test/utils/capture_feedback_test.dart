import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mass_marsh_app/utils/capture_feedback.dart';
import 'package:mass_marsh_app/utils/gps_quality.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late List<String> played;

  setUp(() {
    played = [];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'SystemSound.play') played.add('sound:${call.arguments}');
        if (call.method == 'HapticFeedback.vibrate') played.add('haptic:${call.arguments}');
        return null;
      },
    );
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, null);
  });

  test('a good fix plays a gentle click and a light tap', () async {
    await playCaptureFeedback(gpsTierGood);

    expect(played, ['sound:SystemSoundType.click', 'haptic:HapticFeedbackType.lightImpact']);
  });

  test('a fair fix sounds the same as a good one', () async {
    await playCaptureFeedback(gpsTierFair);

    expect(played, ['sound:SystemSoundType.click', 'haptic:HapticFeedbackType.lightImpact']);
  });

  test('a coarse fix is a stronger tap with no confirming sound, so it prompts a look at the screen', () async {
    await playCaptureFeedback(gpsTierCoarse);

    expect(played, ['haptic:HapticFeedbackType.mediumImpact']);
  });

  test('no fix at all is a firm tap, so someone not watching the screen knows to retry', () async {
    await playCaptureFailedFeedback();

    expect(played, ['haptic:HapticFeedbackType.heavyImpact']);
  });

  test('a platform that rejects feedback never throws', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async => throw PlatformException(code: 'unavailable'),
    );

    await playCaptureFeedback(gpsTierGood);
    await playCaptureFailedFeedback();
  });
}

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// Call in setUpAll() of tests that touch just_audio / audio_session.
Future<void> installAudioMethodChannelMocks() async {
  TestWidgetsFlutterBinding.ensureInitialized();

  // just_audio main channel
  const justAudio = MethodChannel('com.ryanheise.just_audio.methods');

  // audio_session channel
  const audioSession = MethodChannel('com.ryanheise.audio_session');

  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  // Basic stubs good enough for unit tests that don't depend on real playback.
  await messenger.setMockMethodCallHandler(justAudio, (call) async {
    switch (call.method) {
      case 'init':
        return 0; // player id
      case 'disposeAllPlayers':
      case 'disposePlayer':
      case 'setVolume':
      case 'setSpeed':
      case 'setLoopMode':
      case 'setShuffleModeEnabled':
      case 'setAndroidAudioAttributes':
      case 'setAutomaticallyWaitsToMinimizeStalling':
      case 'setCanUseNetworkResourcesForLiveStreamingWhilePaused':
      case 'load':
      case 'setAudioSource':
      case 'setClip':
      case 'play':
      case 'pause':
      case 'seek':
      case 'stop':
        return null;
      case 'processingStateStream':
      case 'positionStream':
      case 'bufferedPositionStream':
      case 'icyMetadataStream':
      case 'playerEventStream':
        // Streams are pushed via events on a separate channel in the real plugin.
        // For simple tests we can no-op here.
        return null;
      default:
        // Unhandled call: keep tests from crashing.
        return null;
    }
  });

  await messenger.setMockMethodCallHandler(audioSession, (call) async {
    switch (call.method) {
      case 'getConfiguration':
        return {
          'avAudioSessionCategory': 'playback',
          'avAudioSessionCategoryOptions': 0,
          'avAudioSessionMode': 'default',
          'androidAudioAttributes': {
            'contentType': 2,
            'flags': 0,
            'usage': 1,
          },
          'androidAudioFocusGainType': 1,
          'androidWillPauseWhenDucked': false,
          'duckAudio': false,
          'handleInterruptions': true,
          'androidStayAwake': false,
        };
      case 'configure':
      case 'becomingNoisyEventStream':
      case 'interruptionEventStream':
        return null;
      default:
        return null;
    }
  });
}

/// Call in tearDownAll() to clean up.
Future<void> uninstallAudioMethodChannelMocks() async {
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  await messenger.setMockMethodCallHandler(
      const MethodChannel('com.ryanheise.just_audio.methods'), null);
  await messenger.setMockMethodCallHandler(
      const MethodChannel('com.ryanheise.audio_session'), null);
}

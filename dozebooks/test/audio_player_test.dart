import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_audio/just_audio.dart';

const _kBaseAudioChannelName = 'com.ryanheise.just_audio.methods';
const _kAudioSessionChannelName = 'com.ryanheise.audio_session';

const MethodChannel _kBaseAudioChannel = MethodChannel(_kBaseAudioChannelName);
const MethodChannel _kAudioSessionChannel =
    MethodChannel(_kAudioSessionChannelName);

Future<void> _installAudioMethodChannelMocks() async {
  TestWidgetsFlutterBinding.ensureInitialized();

  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  // Register a handler for a specific per-player channel (methods.<playerId>)
  void _registerPerPlayerChannel(String playerId) {
    final MethodChannel perPlayer =
        MethodChannel('$_kBaseAudioChannelName.$playerId');

    messenger.setMockMethodCallHandler(perPlayer, (call) async {
      switch (call.method) {
        case 'disposePlayer':
        case 'setVolume':
        case 'setSpeed':
        case 'setLoopMode':
        case 'setShuffleModeEnabled':
        case 'setAndroidAudioAttributes':
        case 'setAutomaticallyWaitsToMinimizeStalling':
        case 'setCanUseNetworkResourcesForLiveStreamingWhilePaused':
        case 'setClip':
        case 'setAudioSource':
        case 'load':
        case 'play':
        case 'pause':
        case 'seek':
        case 'stop':
          return null; // succeed
        default:
          return null; // ignore anything else for these unit tests
      }
    });
  }

  // Base channel: create players & global ops.
  messenger.setMockMethodCallHandler(_kBaseAudioChannel, (call) async {
    switch (call.method) {
      case 'init':
        // just_audio passes the playerId in arguments; capture and wire it.
        final args = call.arguments;
        String? playerId;
        if (args is String) {
          playerId = args;
        } else if (args is Map) {
          final dynamic maybeId = args['id'] ?? args['playerId'];
          if (maybeId is String) playerId = maybeId;
        }
        // Fallback: if for some reason no id is provided, create one.
        playerId ??= 'test-player-fallback';

        _registerPerPlayerChannel(playerId);

        // Some versions return void; others return the id. Returning null is safe.
        return null;

      case 'disposeAllPlayers':
        // No-op: allow being called anytime without crashing.
        return null;

      default:
        return null;
    }
  });

  // Audio session stubs: enough for just_audio to "configure".
  messenger.setMockMethodCallHandler(_kAudioSessionChannel, (call) async {
    switch (call.method) {
      case 'getConfiguration':
        return {
          'avAudioSessionCategory': 'playback',
          'avAudioSessionCategoryOptions': 0,
          'avAudioSessionMode': 'default',
          'androidAudioAttributes': {'contentType': 2, 'flags': 0, 'usage': 1},
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

Future<void> _uninstallAudioMethodChannelMocks() async {
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  messenger.setMockMethodCallHandler(_kBaseAudioChannel, null);
  messenger.setMockMethodCallHandler(_kAudioSessionChannel, null);
}

void main() {
  setUpAll(() async {
    await _installAudioMethodChannelMocks();
  });

  tearDownAll(() async {
    await _uninstallAudioMethodChannelMocks();
  });

  group('AudioPlayer Tests', () {
    late AudioPlayer player;

    setUp(() {
      player = AudioPlayer();
    });

    tearDown(() async {
      await player.dispose();
    });

    test('Initial volume is 1.0', () {
      expect(player.volume, 1.0);
    });

    test('Set volume', () async {
      await player.setVolume(0.5);
      expect(player.volume, 0.5);
    });

    test('Play and pause do not throw', () async {
      await player.setAudioSource(
        AudioSource.uri(Uri.parse('https://example.com/audio.mp3')),
      );
      await player.play();
      await player.pause();

      // Note: with mocks we don't assert on player.playing because some
      // versions update it via platform events we are not emitting.
    });
  });
}

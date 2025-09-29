// This is a basic Flutter widget test.
//
// Robust version that mocks just_audio/audio_session channels so the widget
// can build and the play/pause button can be exercised without a real platform.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import '../lib/main.dart';

/// ----- Minimal platform-channel stubs for just_audio / audio_session -----

const _kBaseAudioChannelName = 'com.ryanheise.just_audio.methods';
const _kAudioSessionChannelName = 'com.ryanheise.audio_session';

const MethodChannel _kBaseAudioChannel = MethodChannel(_kBaseAudioChannelName);
const MethodChannel _kAudioSessionChannel =
    MethodChannel(_kAudioSessionChannelName);

Future<void> _installAudioMethodChannelMocks() async {
  TestWidgetsFlutterBinding.ensureInitialized();

  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

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
          return null; // succeed silently
        default:
          return null;
      }
    });
  }

  messenger.setMockMethodCallHandler(_kBaseAudioChannel, (call) async {
    switch (call.method) {
      case 'init':
        // just_audio may pass the playerId in the arguments; capture it.
        final args = call.arguments;
        String? playerId;
        if (args is String) {
          playerId = args;
        } else if (args is Map) {
          final dynamic maybeId = args['id'] ?? args['playerId'];
          if (maybeId is String) playerId = maybeId;
        }
        playerId ??= 'test-player-fallback';
        _registerPerPlayerChannel(playerId);
        return null; // returning null is acceptable across plugin versions
      case 'disposeAllPlayers':
        return null; // safe no-op
      default:
        return null;
    }
  });

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

/// ----- Test ------------------------------------------------------------------

void main() {
  setUpAll(() async {
    await _installAudioMethodChannelMocks();
  });

  tearDownAll(() async {
    await _uninstallAudioMethodChannelMocks();
  });

  testWidgets('Audio Player UI Test', (WidgetTester tester) async {
    // Build the app and let async init settle.
    await tester.pumpWidget(const MaterialApp(home: OneScreenAudiobook()));
    await tester.pumpAndSettle();

    // App bar title.
    expect(find.text('dozeBooks'), findsOneWidget);

    // "Add files or folder" button (exact text as in your test).
    expect(find.text('Add files or folder'), findsOneWidget);

    // Be flexible about which play/pause icon your UI uses.
    final playIcons = <IconData>[
      Icons.play_arrow,
      Icons.play_circle,
      Icons.play_circle_fill,
    ];
    final pauseIcons = <IconData>[
      Icons.pause,
      Icons.pause_circle,
      Icons.pause_circle_filled,
    ];

    Finder playOrPauseIconFinder = find.byWidgetPredicate(
      (w) => w is Icon && (playIcons + pauseIcons).contains(w.icon),
      description: 'a play or pause Icon',
    );

    // If the icon builds async, allow one more settle.
    if (!tester.any(playOrPauseIconFinder)) {
      await tester.pump(const Duration(milliseconds: 200));
    }

    expect(
      tester.any(playOrPauseIconFinder),
      isTrue,
      reason:
          'Expected to find a play or pause icon in the UI, but none was found.',
    );

    // Determine initial state (play vs pause).
    final bool startedWithPlay = playIcons.any(
      (icon) => tester.any(find.byIcon(icon).hitTestable()),
    );

    // Tap the nearest clickable parent (IconButton or FAB).
    final Finder icon = playOrPauseIconFinder.first;
    final Finder tapTarget = find.ancestor(
          of: icon,
          matching: find.byType(IconButton),
        ).first
        .evaluate()
        .isNotEmpty
        ? find.ancestor(of: icon, matching: find.byType(IconButton)).first
        : find.ancestor(of: icon, matching: find.byType(FloatingActionButton))
            .first;

    await tester.tap(tapTarget);
    await tester.pumpAndSettle();

    // After tapping, expect the opposite icon to be visible (best-effort).
    if (startedWithPlay) {
      expect(
        playIcons.any((i) => tester.any(find.byIcon(i))),
        isFalse,
        reason: 'After tapping play, a pause icon should appear.',
      );
      expect(
        pauseIcons.any((i) => tester.any(find.byIcon(i))),
        isTrue,
        reason: 'Expected a pause icon after tapping play.',
      );
    } else {
      expect(
        pauseIcons.any((i) => tester.any(find.byIcon(i))),
        isFalse,
        reason: 'After tapping pause, a play icon should appear.',
      );
      expect(
        playIcons.any((i) => tester.any(find.byIcon(i))),
        isTrue,
        reason: 'Expected a play icon after tapping pause.',
      );
    }
  });
}

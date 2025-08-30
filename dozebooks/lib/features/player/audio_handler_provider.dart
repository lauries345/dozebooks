// lib/features/player/audio_handler_provider.dart
import 'dart:math';
import 'package:audio_service/audio_service.dart';
import 'package:just_audio/just_audio.dart';
import 'package:audio_session/audio_session.dart';

Future<AudioHandler> initAudioHandler() async {
  final session = await AudioSession.instance;
  await session.configure(const AudioSessionConfiguration.music());
  return _SimpleAudioHandler();
}

class _SimpleAudioHandler extends BaseAudioHandler with SeekHandler {
  final _player = AudioPlayer();
  final _playlist = ConcatenatingAudioSource(children: []);
  bool _shuffleEnabled = false;

  _SimpleAudioHandler() {
    // Drive AudioService's playbackState from just_audio events.
    _player.playbackEventStream.map(_eventToState).pipe(playbackState);

    // Keep the current MediaItem in sync with the player's index.
    _player.currentIndexStream.listen((index) {
      final q = queue.value;
      if (index != null && index >= 0 && index < q.length) {
        mediaItem.add(q[index]);
      }
    });
  }

  PlaybackState _eventToState(PlaybackEvent e) => PlaybackState(
        controls: [
          if (_player.playing) MediaControl.pause else MediaControl.play,
          MediaControl.skipToPrevious,
          MediaControl.skipToNext,
          MediaControl.stop,
        ],
        systemActions: const {
          MediaAction.seek,
          MediaAction.skipToPrevious,
          MediaAction.skipToNext,
          MediaAction.setShuffleMode,
        },
        androidCompactActionIndices: const [0, 2],
        processingState: const {
          ProcessingState.idle: AudioProcessingState.idle,
          ProcessingState.loading: AudioProcessingState.loading,
          ProcessingState.buffering: AudioProcessingState.buffering,
          ProcessingState.ready: AudioProcessingState.ready,
          ProcessingState.completed: AudioProcessingState.completed,
        }[_player.processingState]!,
        playing: _player.playing,
        shuffleMode: _shuffleEnabled
            ? AudioServiceShuffleMode.all
            : AudioServiceShuffleMode.none,
        // ✅ FIX: use updatePosition, not position
        updatePosition: e.updatePosition,
        bufferedPosition: e.bufferedPosition,
        speed: _player.speed,
      );

  // ---------------- Queue / playlist ----------------

  @override
  Future<void> addQueueItem(MediaItem item) async {
    final newQueue = [...queue.value, item];
    queue.add(newQueue);
    await _playlist.add(AudioSource.uri(Uri.parse(item.id)));
    if (_player.audioSource == null) {
      await _player.setAudioSource(_playlist);
    }
  }

  @override
  Future<void> addQueueItems(List<MediaItem> items) async {
    if (items.isEmpty) return;
    queue.add([...queue.value, ...items]);
    await _playlist.addAll(
      items.map((it) => AudioSource.uri(Uri.parse(it.id))).toList(),
    );
    if (_player.audioSource == null) {
      await _player.setAudioSource(_playlist);
    }
  }

  @override
  Future<void> removeQueueItem(MediaItem item) async {
    final idx = queue.value.indexWhere((m) => m.id == item.id);
    if (idx < 0) return;
    final newQueue = [...queue.value]..removeAt(idx);
    queue.add(newQueue);
    await _playlist.removeAt(idx);
  }

  @override
  Future<void> updateQueue(List<MediaItem> items) async {
    queue.add(items);
    await _playlist.clear();
    await _playlist.addAll(
      items.map((it) => AudioSource.uri(Uri.parse(it.id))).toList(),
    );
    if (_player.audioSource == null) {
      await _player.setAudioSource(_playlist);
    }
  }

  // ---------------- Transport controls ----------------
  @override
  Future<void> play() => _player.play();

  @override
  Future<void> pause() => _player.pause();

  @override
  Future<void> stop() => _player.stop();

  @override
  Future<void> seek(Duration position) => _player.seek(position);

  @override
  Future<void> skipToNext() => _player.seekToNext();

  @override
  Future<void> skipToPrevious() => _player.seekToPrevious();

  // ---------------- Shuffle ----------------
  @override
  Future<void> setShuffleMode(AudioServiceShuffleMode mode) async {
    final enable = mode == AudioServiceShuffleMode.all;
    _shuffleEnabled = enable;
    await _player.setShuffleModeEnabled(enable);
    if (enable) {
      await _player.shuffle(); // create a new random order
    }
    // Re-emit so UI reflects new state immediately.
    playbackState.add(_eventToState(_player.playbackEvent));
  }

  // Optional: start playback from a specific MediaItem id.
  @override
  Future<void> playFromMediaId(String mediaId,
      [Map<String, dynamic>? _]) async {
    final idx = queue.value.indexWhere((m) => m.id == mediaId);
    await _ensureSource();
    if (idx >= 0) {
      await _player.seek(Duration.zero, index: idx);
      await _player.play();
    } else {
      final item = MediaItem(id: mediaId, title: mediaId);
      await addQueueItem(item);
      await _player.seek(Duration.zero, index: queue.value.length - 1);
      await _player.play();
    }
  }

  // Custom: jump to a random item in the queue and play.
  // Call from UI: audioHandler.customAction('playRandom');
  @override
  Future<dynamic> customAction(String name, [Map<String, dynamic>? _]) async {
    switch (name) {
      case 'playRandom':
        if (queue.value.isEmpty) return;
        final idx = Random().nextInt(queue.value.length);
        await _ensureSource();
        await _player.seek(Duration.zero, index: idx);
        await _player.play();
        return;
    }
    return super.customAction(name, _);
  }

  Future<void> _ensureSource() async {
    if (_player.audioSource == null) {
      await _player.setAudioSource(_playlist);
    }
  }
}

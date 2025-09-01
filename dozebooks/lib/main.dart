// lib/main.dart
import 'dart:async';
import 'dart:math';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';

// If you use Windows (recommended backend):
// pubspec deps: just_audio_media_kit, media_kit_libs_windows_audio
import 'package:just_audio_media_kit/just_audio_media_kit.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  // Safe no-op on platforms where media_kit isn't used; on Windows it swaps the backend.
  JustAudioMediaKit.ensureInitialized();

  runApp(const MaterialApp(
    debugShowCheckedModeBanner: false,
    title: 'BookShuffle',
    home: OneScreenAudiobook(),
  ));
}

class OneScreenAudiobook extends StatefulWidget {
  const OneScreenAudiobook({super.key});

  @override
  State<OneScreenAudiobook> createState() => _OneScreenAudiobookState();
}

class _OneScreenAudiobookState extends State<OneScreenAudiobook> {
  final _player = AudioPlayer();
  final _rng = Random();

  String? _fileName;
  Duration? _duration;

  Duration _minDuration(Duration a, Duration b) => (a <= b) ? a : b;

  // 1-minute grid for shuffle starts
  static const Duration _gridIncrement = Duration(minutes: 1);
  static const Duration _minPlayableTail = Duration(minutes: 1);
  List<Duration> _startMarks = const []; // 0:00, 1:00, 2:00 ... (valid ones)

  // Adjustable playback window (default 20 min)
  Duration _windowLen = const Duration(minutes: 20);
  final List<Duration> _windowOptions = const [
    Duration(minutes: 5),
    Duration(minutes: 10),
    Duration(minutes: 15),
    Duration(minutes: 20),
    Duration(minutes: 25),
    Duration(minutes: 30),
    Duration(minutes: 45),
    Duration(minutes: 60),
  ];

  // Current "bounded" play window
  int? _currentMarkIndex;
  Duration? _windowEnd;

  // Fades
  final Duration _fadeInDur = const Duration(milliseconds: 900);
  final Duration _fadeOutDur = const Duration(milliseconds: 700);
  double _targetVolume = 1.0;
  double _currVolume = 1.0;
  int _fadeGen = 0; // cancels in-flight fades
  bool _segmentFadeStarted = false;

  StreamSubscription<Duration>? _posSub;

  @override
  void initState() {
    super.initState();
    _posSub = _player.positionStream.listen((pos) async {
      final end = _windowEnd;
      if (end == null) return;

      final remaining = end - pos;

      // Start fade-out as we approach the end of the current window
      if (!_segmentFadeStarted &&
          remaining > Duration.zero &&
          remaining <= _fadeOutDur) {
        _segmentFadeStarted = true;
        unawaited(_fadeTo(0.0, remaining));
      }

      // Pause at the end of the window
      if (remaining <= const Duration(milliseconds: 120)) {
        _segmentFadeStarted = false;
        _windowEnd = null;
        await _player.pause();
        _currVolume = _targetVolume;
        await _player.setVolume(_targetVolume);
      }
    });
  }

  @override
  void dispose() {
    _posSub?.cancel();
    _player.dispose().onError((e, st) {
      debugPrint('AudioPlayer.dispose ignored: $e');
    });
    super.dispose();
  }

  // ------------ File load & marks ------------
  Future<void> _pickAndLoadFile() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: const ['m4b', 'm4a', 'mp3'],
        allowMultiple: false,
        dialogTitle: 'Choose an audiobook file (.m4b recommended)',
      );
      if (result == null || result.files.isEmpty) return;

      final path = result.files.single.path;
      if (path == null) return;

      setState(() {
        _fileName = result.files.single.name;
        _currentMarkIndex = null;
        _windowEnd = null;
        _duration = null;
        _startMarks = const [];
      });

      final dur = await _player.setFilePath(path);
      if (dur == null) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Could not determine duration.')),
          );
        }
        return;
      }

      final marks = _buildStartMarks(dur, _gridIncrement);
      setState(() {
        _duration = dur;
        _startMarks = marks;
      });

      _currVolume = _targetVolume;
      await _player.setVolume(_targetVolume);

      if (marks.isEmpty && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Audio too short for 1-min shuffles.')),
        );
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to load file: $e')),
      );
    }
  }

  List<Duration> _buildStartMarks(Duration total, Duration increment) {
    final marks = <Duration>[];
    for (Duration start = Duration.zero; start < total; start += increment) {
      // Only allow starts where at least 1 minute remains
      if (total - start >= _minPlayableTail) {
        marks.add(start);
      }
    }
    return marks;
  }
  // -------------------------------------------

  // --------------- Shuffle logic --------------
  Future<void> _shuffleToOneMinuteMark() async {
    if (_startMarks.isEmpty || _duration == null) return;

    int nextIdx;
    if (_startMarks.length == 1) {
      nextIdx = 0;
    } else {
      do {
        nextIdx = _rng.nextInt(_startMarks.length);
      } while (_currentMarkIndex != null && nextIdx == _currentMarkIndex);
    }

    final start = _startMarks[nextIdx];
    var end = start + _windowLen;
    final total = _duration!;
    if (end > total) end = total; // shorten the final window if near the end

    setState(() {
      _currentMarkIndex = nextIdx;
      _windowEnd = end;
      _segmentFadeStarted = false;
    });

    _fadeGen++; // cancel any ongoing fade
    await _player.pause();
    await _player.seek(start);
    await _playWithFadeIn();
  }
  // -------------------------------------------

  // ---------------- Fade helpers --------------
  Future<void> _fadeTo(double target, Duration dur) async {
    _fadeGen++;
    final gen = _fadeGen;

    final start = _currVolume;
    final delta = target - start;
    if (dur <= Duration.zero || delta.abs() < 0.001) {
      _currVolume = target;
      await _player.setVolume(target);
      return;
    }

    const frame = Duration(milliseconds: 16); // ~60fps
    final steps =
        (dur.inMilliseconds / frame.inMilliseconds).ceil().clamp(1, 300);
    for (var i = 1; i <= steps; i++) {
      if (gen != _fadeGen) return; // cancelled
      final t = i / steps;
      final v = (start + delta * t).clamp(0.0, 1.0);
      _currVolume = v;
      await _player.setVolume(v);
      await Future.delayed(frame);
    }
  }

  Future<void> _playWithFadeIn() async {
    _fadeGen++; // cancel fade-outs
    _currVolume = 0.0;
    await _player.setVolume(0.0);
    await _player.play();
    await _fadeTo(_targetVolume, _fadeInDur);
  }

  Future<void> _pauseWithFadeOut([Duration? custom]) async {
    final d = custom ?? _fadeOutDur;
    await _fadeTo(0.0, d);
    await _player.pause();
    _currVolume = _targetVolume; // prep for next start
    await _player.setVolume(_targetVolume);
  }

  Future<void> _stopWithFadeOut() async {
    await _fadeTo(0.0, _fadeOutDur);
    await _player.stop();
    _currVolume = _targetVolume;
    await _player.setVolume(_targetVolume);
  }
  // -------------------------------------------

  String _fmt(Duration d) {
    final h = d.inHours;
    final m = d.inMinutes.remainder(60);
    final s = d.inSeconds.remainder(60);
    if (h > 0) {
      return '${h.toString().padLeft(2, '0')}:'
          '${m.toString().padLeft(2, '0')}:'
          '${s.toString().padLeft(2, '0')}';
    }
    return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dur = _duration;

    return Scaffold(
      appBar: AppBar(
        title: const Text('BookShuffle (1-min shuffle, windowed play)'),
        centerTitle: true,
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Card(
              elevation: 2,
              child: ListTile(
                title: Text(_fileName ?? 'No file loaded'),
                subtitle: dur == null
                    ? const Text('Load an .m4b/.m4a/.mp3 to begin')
                    : Text(
                        'Duration: ${_fmt(dur)} • '
                        '${_startMarks.length} start marks (1-min grid) • '
                        'Window: ${_windowLen.inMinutes} min',
                      ),
                trailing: FilledButton.icon(
                  onPressed: _pickAndLoadFile,
                  icon: const Icon(Icons.folder_open),
                  label: const Text('Load file'),
                ),
              ),
            ),
            const SizedBox(height: 12),
            // Playback window chooser
            Row(
              children: [
                const Text('Play window:'),
                const SizedBox(width: 12),
                DropdownButton<Duration>(
                  value: _windowLen,
                  items: _windowOptions
                      .map(
                        (d) => DropdownMenuItem(
                          value: d,
                          child: Text('${d.inMinutes} min'),
                        ),
                      )
                      .toList(),
                  onChanged: (val) async {
                    if (val == null) return;
                    setState(() {
                      _windowLen = val;
                      _segmentFadeStarted = false;
                    });
                    // If we’re currently bounding playback, move the end to "now + window"
                    if (_windowEnd != null && _duration != null) {
                      final pos = await _player.position;
                      var newEnd = pos + _windowLen;
                      if (newEnd > _duration!) newEnd = _duration!;
                      setState(() {
                        _windowEnd = newEnd;
                      });
                    }
                  },
                ),
              ],
            ),
            const SizedBox(height: 12),
            // Position + slider
            StreamBuilder<Duration>(
              stream: _player.positionStream,
              builder: (context, snap) {
                final pos = snap.data ?? Duration.zero;
                final max = dur?.inMilliseconds.toDouble() ?? 0.0;
                final value =
                    pos.inMilliseconds.clamp(0, max.toInt()).toDouble();

                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Slider(
                      value: max > 0 ? value : 0.0,
                      max: max > 0 ? max : 1.0,
                      onChanged: (v) async {
                        if (dur == null) return;
                        final seekTo = Duration(milliseconds: v.toInt());
                        setState(() {
                          _windowEnd = null; // clear bounded window
                          _segmentFadeStarted = false;
                        });
                        _fadeGen++; // cancel active fade
                        _currVolume = _targetVolume;
                        await _player.setVolume(_targetVolume);
                        await _player.seek(seekTo);
                      },
                    ),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(_fmt(pos), style: theme.textTheme.bodySmall),
                        Text(_fmt(dur ?? Duration.zero),
                            style: theme.textTheme.bodySmall),
                      ],
                    )
                  ],
                );
              },
            ),
            const SizedBox(height: 12),
            if (_currentMarkIndex != null && _duration != null)
              Text(
                () {
                  final start = _startMarks[_currentMarkIndex!];
                  final shownEnd = _windowEnd ?? (start + _windowLen);
                  final bounded = _minDuration(shownEnd - start, _windowLen);
                  return 'Current window: ${_fmt(start)} → ${_fmt(shownEnd)} '
                        '(${bounded.inMinutes} min)';
                }(),
                style: theme.textTheme.bodyMedium,
              ),
            const Spacer(),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                FilledButton.tonalIcon(
                  onPressed:
                      (_duration != null && _startMarks.isNotEmpty)
                          ? _shuffleToOneMinuteMark
                          : null,
                  icon: const Icon(Icons.shuffle),
                  label: const Text('Shuffle (1-min grid)'),
                ),
                const SizedBox(width: 16),
                FilledButton.icon(
                  onPressed: (_duration != null)
                      ? () async {
                          if (_player.playing) {
                            await _pauseWithFadeOut();
                          } else {
                            await _playWithFadeIn();
                          }
                        }
                      : null,
                  icon: StreamBuilder<bool>(
                    stream: _player.playingStream,
                    builder: (_, snap) => Icon(
                      (snap.data ?? false) ? Icons.pause : Icons.play_arrow,
                    ),
                  ),
                  label: const Text('Play/Pause'),
                ),
                const SizedBox(width: 16),
                IconButton.filledTonal(
                  tooltip: 'Stop',
                  onPressed: (_duration != null)
                      ? () async {
                          _windowEnd = null;
                          _segmentFadeStarted = false;
                          await _stopWithFadeOut();
                        }
                      : null,
                  icon: const Icon(Icons.stop),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

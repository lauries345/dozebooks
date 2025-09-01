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

  // Multi-file support
  final List<_Book> _books = [];
  int? _currentBookIndex;

  Duration? _duration;          // of current book
  List<Duration> _startMarks = const []; // 1-min grid for current book
  int? _currentMarkIndex;       // index within _startMarks

  // UI/summary
  String? _fileName;

  // Helpers
  Duration _minDuration(Duration a, Duration b) => (a <= b) ? a : b;

  // 1-minute grid for shuffle starts
  static const Duration _gridIncrement = Duration(minutes: 1);
  static const Duration _minPlayableTail = Duration(minutes: 1);

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

  // Current "bounded" play window end
  Duration? _windowEnd;

  // Fades
  final Duration _fadeInDur = const Duration(milliseconds: 900);
  final Duration _fadeOutDur = const Duration(milliseconds: 700);
  double _targetVolume = 1.0;
  double _currVolume = 1.0;
  int _fadeGen = 0; // cancels in-flight fades
  bool _segmentFadeStarted = false;

  // For avoiding immediate repeats in "shuffle all"
  int? _lastFileIdx;
  int? _lastMarkIdx;

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

  // ============= File picking & preparation =============

  Future<void> _pickAndAddFiles() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: const ['m4b', 'm4a', 'mp3'],
        allowMultiple: true,
        dialogTitle: 'Choose audiobook files (.m4b recommended)',
      );
      if (result == null || result.files.isEmpty) return;

      bool addedAny = false;

      for (final f in result.files) {
        final path = f.path;
        if (path == null) continue;

        // Skip duplicates by path
        if (_books.any((b) => b.path == path)) {
          continue;
        }

        final dur = await _probeDuration(path);
        if (dur == null) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('Could not read duration for ${f.name}')),
            );
          }
          continue;
        }

        final marks = _buildStartMarks(dur, _gridIncrement);
        if (marks.isEmpty) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('File too short for 1-min shuffle: ${f.name}')),
            );
          }
          continue;
        }

        _books.add(_Book(name: f.name, path: path, duration: dur, marks: marks));
        addedAny = true;
      }

      if (!addedAny) return;

      // If nothing was loaded before, load the first book into the player (no autoplay)
      if (_currentBookIndex == null && _books.isNotEmpty) {
        await _switchToBook(0, autoplay: false);
      } else {
        setState(() {}); // refresh list count
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to add files: $e')),
      );
    }
  }

  Future<Duration?> _probeDuration(String path) async {
    final p = AudioPlayer();
    try {
      final d = await p.setFilePath(path);
      return d;
    } catch (_) {
      return null;
    } finally {
      await p.dispose().onError((_, __) {});
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

  // Switch current selection & load into player
  Future<void> _switchToBook(int idx, {bool autoplay = false}) async {
    if (idx < 0 || idx >= _books.length) return;

    final b = _books[idx];

    _fadeGen++; // cancel fades
    await _player.pause();

    // Load the file into the main player
    await _player.setFilePath(b.path);

    setState(() {
      _currentBookIndex = idx;
      _fileName = b.name;
      _duration = b.duration;
      _startMarks = b.marks;
      _currentMarkIndex = null;
      _windowEnd = null;
      _segmentFadeStarted = false;
    });

    _currVolume = _targetVolume;
    await _player.setVolume(_targetVolume);

    if (autoplay) {
      // Start from 0 or from a random mark? We'll keep it simple: from 0.
      await _player.seek(Duration.zero);
      await _playWithFadeIn();
    }
  }

  // ============= Shuffle logic =============

  // Shuffle within the currently selected file
  Future<void> _shuffleCurrent() async {
    final idx = _currentBookIndex;
    if (idx == null || _startMarks.isEmpty || _duration == null) return;

    int nextMark;
    if (_startMarks.length == 1) {
      nextMark = 0;
    } else {
      do {
        nextMark = _rng.nextInt(_startMarks.length);
      } while (_currentMarkIndex != null && nextMark == _currentMarkIndex);
    }

    await _playFromBookMark(idx, nextMark);
  }

  // Shuffle across ALL files (pick random file + random 1-min mark)
  Future<void> _shuffleAll() async {
    if (_books.isEmpty) return;

    int fileIdx;
    if (_books.length == 1) {
      fileIdx = 0;
    } else {
      // Avoid same file twice in a row if possible
      do {
        fileIdx = _rng.nextInt(_books.length);
      } while (_lastFileIdx != null && fileIdx == _lastFileIdx);
    }

    final marks = _books[fileIdx].marks;
    if (marks.isEmpty) return;

    int markIdx;
    if (marks.length == 1) {
      markIdx = 0;
    } else {
      // Avoid repeating the same file+mark pair
      do {
        markIdx = _rng.nextInt(marks.length);
      } while (_lastFileIdx == fileIdx && _lastMarkIdx != null && markIdx == _lastMarkIdx);
    }

    await _playFromBookMark(fileIdx, markIdx);
  }

  Future<void> _playFromBookMark(int fileIdx, int markIdx) async {
    if (fileIdx < 0 || fileIdx >= _books.length) return;
    final b = _books[fileIdx];

    // If switching files, load it
    if (_currentBookIndex != fileIdx) {
      await _switchToBook(fileIdx, autoplay: false);
    }

    final start = b.marks[markIdx];
    var end = start + _windowLen;
    if (end > b.duration) end = b.duration;

    setState(() {
      _currentBookIndex = fileIdx;
      _currentMarkIndex = markIdx;
      _windowEnd = end;
      _segmentFadeStarted = false;
      _duration = b.duration;
      _startMarks = b.marks;
      _fileName = b.name;
    });

    _fadeGen++; // cancel any ongoing fade
    await _player.pause();
    await _player.seek(start);
    await _playWithFadeIn();

    _lastFileIdx = fileIdx;
    _lastMarkIdx = markIdx;
  }

  // ============= Fade helpers =============

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

  // ============= Utils =============

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

    final currentName = (_currentBookIndex != null && _currentBookIndex! < _books.length)
        ? _books[_currentBookIndex!].name
        : (_fileName ?? 'No file loaded');

    return Scaffold(
      appBar: AppBar(
        title: const Text('BookShuffle (multi-file, 1-min shuffle)'),
        centerTitle: true,
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Card(
              elevation: 2,
              child: ListTile(
                title: Text(currentName),
                subtitle: (_books.isEmpty || dur == null)
                    ? Text('Files loaded: ${_books.length}. Load .m4b/.m4a/.mp3 to begin.')
                    : Text(
                        'Files: ${_books.length} • '
                        'Duration: ${_fmt(dur)} • '
                        'Start marks: ${_startMarks.length} • '
                        'Window: ${_windowLen.inMinutes} min',
                      ),
                trailing: FilledButton.icon(
                  onPressed: _pickAndAddFiles,
                  icon: const Icon(Icons.library_add),
                  label: const Text('Add files'),
                ),
              ),
            ),
            const SizedBox(height: 12),

            // File list
            if (_books.isNotEmpty)
              Container(
                constraints: const BoxConstraints(maxHeight: 180),
                child: Material(
                  elevation: 1,
                  borderRadius: BorderRadius.circular(8),
                  child: ListView.separated(
                    itemCount: _books.length,
                    separatorBuilder: (_, __) => const Divider(height: 1),
                    itemBuilder: (context, i) {
                      final b = _books[i];
                      final selected = i == _currentBookIndex;
                      return ListTile(
                        selected: selected,
                        leading: Icon(selected ? Icons.playlist_play : Icons.audiotrack),
                        title: Text(b.name, maxLines: 1, overflow: TextOverflow.ellipsis),
                        subtitle: Text('Duration: ${_fmt(b.duration)} • marks: ${b.marks.length}'),
                        onTap: () async => _switchToBook(i, autoplay: false),
                      );
                    },
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

            // Controls
            Wrap(
              alignment: WrapAlignment.center,
              spacing: 12,
              runSpacing: 8,
              children: [
                FilledButton.tonalIcon(
                  onPressed: (_duration != null && _startMarks.isNotEmpty)
                      ? _shuffleCurrent
                      : null,
                  icon: const Icon(Icons.shuffle),
                  label: const Text('Shuffle (current)'),
                ),
                FilledButton.tonalIcon(
                  onPressed: _books.isNotEmpty ? _shuffleAll : null,
                  icon: const Icon(Icons.all_inclusive),
                  label: const Text('Shuffle (all files)'),
                ),
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

class _Book {
  final String name;
  final String path;
  final Duration duration;
  final List<Duration> marks;
  const _Book({
    required this.name,
    required this.path,
    required this.duration,
    required this.marks,
  });
}

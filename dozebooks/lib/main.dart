// lib/main.dart
import 'dart:async';
import 'dart:math';
import 'dart:io' show File;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';
import 'package:audio_session/audio_session.dart';

// Desktop backend swap; on mobile it's a no-op.
import 'package:just_audio_media_kit/just_audio_media_kit.dart';
import 'package:media_kit/media_kit.dart'; // MPVLogLevel

void main() {
  WidgetsFlutterBinding.ensureInitialized();

  // Silence MPV logs (desktop). On mobile this is ignored.
  JustAudioMediaKit.mpvLogLevel = MPVLogLevel.error;
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

  AudioSession? _session;

  // Multi-file library
  final List<_Book> _books = [];
  int? _currentBookIndex;

  // Current track info
  Duration? _duration;
  List<Duration> _startMarks = const []; // 1-min grid
  int? _currentMarkIndex; // index into _startMarks
  String? _fileName;

  Duration _minDuration(Duration a, Duration b) => (a <= b) ? a : b;

  // 1-min shuffle grid
  static const _gridIncrement = Duration(minutes: 1);
  static const _minPlayableTail = Duration(minutes: 1);

  // Adjustable play window (default 20 min)
  Duration _windowLen = const Duration(minutes: 20);
  final _windowOptions = const <Duration>[
    Duration(minutes: 1),
    Duration(minutes: 5),
    Duration(minutes: 10),
    Duration(minutes: 15),
    Duration(minutes: 20),
    Duration(minutes: 25),
    Duration(minutes: 30),
    Duration(minutes: 45),
    Duration(minutes: 60),
  ];

  // Current bounded end
  Duration? _windowEnd;

  // Fade options + state (now mutable)
  final _fadeOptions = const <Duration>[
    Duration(milliseconds: 500),
    Duration(milliseconds: 1000),
    Duration(milliseconds: 2000),
    Duration(milliseconds: 5000),
    Duration(milliseconds: 10000),
  ];
  Duration _fadeInDur = const Duration(milliseconds: 1000);
  Duration _fadeOutDur = const Duration(milliseconds: 5000);

  double _targetVolume = 1.0;
  double _currVolume = 1.0;
  int _fadeGen = 0;
  bool _segmentFadeStarted = false;

  // To avoid instant repeats in "shuffle all"
  int? _lastFileIdx;
  int? _lastMarkIdx;

  StreamSubscription<Duration>? _posSub;

  @override
  void initState() {
    super.initState();
    _initAudioSession();
    _posSub = _player.positionStream.listen(_onPos);
  }

  Future<void> _initAudioSession() async {
    try {
      _session = await AudioSession.instance;
      await _session!.configure(const AudioSessionConfiguration.music());

      // Android: prefer speaker, look like media playback
      try {
        await _player.setAndroidAudioAttributes(const AndroidAudioAttributes(
          contentType: AndroidAudioContentType.music,
          usage: AndroidAudioUsage.media,
          flags: AndroidAudioFlags.none,
        ));
      } catch (_) {}

      // Avoid added latency/edge cases (best-effort; older versions may no-op)
      try {
        await _player.setSkipSilenceEnabled(false);
      } catch (_) {}

      // Pause if route becomes noisy (e.g., headphones unplugged)
      _session!.becomingNoisyEventStream.listen((_) {
        _player.pause();
      });
    } catch (e) {
      debugPrint('AudioSession init warning: $e');
    }
  }

  void _onPos(Duration pos) async {
    final end = _windowEnd;
    if (end == null) return;
    final remaining = end - pos;

    if (!_segmentFadeStarted &&
        remaining > Duration.zero &&
        remaining <= _fadeOutDur) {
      _segmentFadeStarted = true;
      // Cancel any in-flight fade, then start the end fade.
      _fadeGen++;
      unawaited(_fadeTo(0.0, remaining));
    }

    if (remaining <= const Duration(milliseconds: 120)) {
      _segmentFadeStarted = false;
      _windowEnd = null;
      await _player.pause();
      _currVolume = _targetVolume;
      await _player.setVolume(_targetVolume);
    }
  }

  @override
  void dispose() {
    _posSub?.cancel();
    _player.dispose().onError((e, _) => debugPrint('dispose ignored: $e'));
    super.dispose();
  }

  // ================= File picking (mobile-friendly) =================

  Future<void> _pickAndAddFiles() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: const ['m4b', 'm4a', 'mp3'],
        allowMultiple: true,
      );
      if (result == null || result.files.isEmpty) return;

      bool addedAny = false;

      for (final f in result.files) {
        final uri = _resolveUriFromPlatformFile(f);
        if (uri == null) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('Could not access: ${f.name}')),
            );
          }
          continue;
        }

        // Skip duplicates
        if (_books.any((b) => b.uri.toString() == uri.toString())) continue;

        final dur = await _probeDuration(uri);
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

        _books.add(_Book(name: f.name, uri: uri, duration: dur, marks: marks));
        addedAny = true;
      }

      if (!addedAny) return;

      if (_currentBookIndex == null && _books.isNotEmpty) {
        await _switchToBook(0, autoplay: false);
      } else {
        setState(() {}); // refresh list
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to add files: $e')),
      );
    }
  }

  /// Try to get a usable URI from FilePicker's PlatformFile on mobile/desktop.
  Uri? _resolveUriFromPlatformFile(PlatformFile f) {
    // 1) Real filesystem path
    if (f.path != null && f.path!.isNotEmpty && File(f.path!).existsSync()) {
      return Uri.file(f.path!);
    }
    // 2) content:// (Android) or file:// in identifier
    if (f.identifier != null && f.identifier!.isNotEmpty) {
      final maybe = Uri.tryParse(f.identifier!);
      if (maybe != null && (maybe.scheme == 'content' || maybe.scheme == 'file')) {
        return maybe;
      }
    }
    return null;
  }

  Future<Duration?> _probeDuration(Uri uri) async {
    final p = AudioPlayer();
    try {
      final d = await p.setAudioSource(AudioSource.uri(uri));
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
      if (total - start >= _minPlayableTail) marks.add(start);
    }
    return marks;
  }

  Future<void> _switchToBook(int idx, {bool autoplay = false}) async {
    if (idx < 0 || idx >= _books.length) return;
    final b = _books[idx];

    _fadeGen++; // cancel fades
    await _player.pause();

    await _player.setAudioSource(AudioSource.uri(b.uri), preload: true);

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
      await _player.seek(Duration.zero);
      await _playWithFadeIn();
    }
  }

  // ================= Shuffle logic =================

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

  Future<void> _shuffleAll() async {
    if (_books.isEmpty) return;

    int fileIdx;
    if (_books.length == 1) {
      fileIdx = 0;
    } else {
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
      do {
        markIdx = _rng.nextInt(marks.length);
      } while (_lastFileIdx == fileIdx && _lastMarkIdx != null && markIdx == _lastMarkIdx);
    }

    await _playFromBookMark(fileIdx, markIdx);
  }

  Future<void> _playFromBookMark(int fileIdx, int markIdx) async {
    if (fileIdx < 0 || fileIdx >= _books.length) return;
    final b = _books[fileIdx];

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

    _fadeGen++;
    await _player.pause();
    await _player.seek(start);
    await _playWithFadeIn();

    _lastFileIdx = fileIdx;
    _lastMarkIdx = markIdx;
  }

  // ================= Fades & kickstarts =================

  Future<void> _fadeTo(double target, Duration dur) async {
    // NOTE: do NOT bump _fadeGen here; callers control cancellation.
    final gen = _fadeGen;

    final start = _currVolume;
    final delta = target - start;
    if (dur <= Duration.zero || delta.abs() < 0.001) {
      _currVolume = target;
      await _player.setVolume(target);
      return;
    }

    const Duration frame = Duration(milliseconds: 40); // ~25 FPS
    final int stepsRaw = (dur.inMilliseconds / frame.inMilliseconds).ceil();
    final int steps = (stepsRaw.clamp(1, 200)) as int;

    for (var i = 1; i <= steps; i++) {
      if (gen != _fadeGen) return; // cancelled by a new fade
      final t = i / steps;
      final v = (start + delta * t).clamp(0.0, 1.0);
      _currVolume = v;
      await _player.setVolume(v);
      await Future.delayed(frame);
    }
  }

  // Strong pre-kick so Play behaves like Shuffle.
  Future<void> _preKickSeek() async {
    try {
      final pos = _player.position;
      final dur = _duration;

      // If at/near 0, jump +200ms; otherwise keep current pos.
      const bump = Duration(milliseconds: 200);
      const nearZero = Duration(milliseconds: 20);
      Duration to = pos <= nearZero ? bump : pos;

      if (dur != null) {
        final maxTo = dur - const Duration(milliseconds: 250);
        if (to >= maxTo) {
          to = maxTo > Duration.zero ? maxTo : Duration.zero;
        }
      }
      await _player.seek(to);
    } catch (_) {
      // best-effort
    }
  }

  // If playback reports "running" but no frames flow, nudge decisively.
  Future<void> _kickIfStalled() async {
    try {
      if (!_player.playing) return;

      final before = _player.position;
      await Future.delayed(const Duration(milliseconds: 350));
      final after = _player.position;

      // Not advancing by at least ~30ms? Give it a real bump.
      if (after - before < const Duration(milliseconds: 30)) {
        final dur = _duration;
        const bump = Duration(milliseconds: 200);
        var to = before + bump;
        if (dur != null) {
          final maxTo = dur - const Duration(milliseconds: 250);
          if (to >= maxTo) to = maxTo > Duration.zero ? maxTo : Duration.zero;
        }
        await _player.seek(to);

        // Some devices respond to a brief speed tickle
        try {
          await _player.setSpeed(1.01);
          await Future.delayed(const Duration(milliseconds: 60));
          await _player.setSpeed(1.0);
        } catch (_) {}
      }
    } catch (_) {
      // ignore
    }
  }

  Future<void> _playWithFadeIn() async {
    _fadeGen++;

    try {
      await _session?.setActive(true);
    } catch (_) {}

    if (_player.processingState != ProcessingState.ready &&
        _player.processingState != ProcessingState.buffering) {
      await _player.processingStateStream.firstWhere(
        (s) => s == ProcessingState.ready || s == ProcessingState.buffering,
      );
    }

    await _preKickSeek();
    await _player.play();

    // Some devices ignore tiny volumes before full playback starts
    await Future.delayed(const Duration(milliseconds: 100));
    const epsilon = 0.003;
    _currVolume = epsilon;
    await _player.setVolume(epsilon);

    await _kickIfStalled();
    await _fadeTo(_targetVolume, _fadeInDur);
  }

  Future<void> _pauseWithFadeOut([Duration? custom]) async {
    final d = custom ?? _fadeOutDur;
    _fadeGen++; // cancel any other fade
    await _fadeTo(0.0, d);
    await _player.pause();
    _currVolume = _targetVolume;
    await _player.setVolume(_targetVolume);
  }

  Future<void> _stopWithFadeOut() async {
    _fadeGen++; // cancel any other fade
    await _fadeTo(0.0, _fadeOutDur);
    await _player.stop();
    _currVolume = _targetVolume;
    await _player.setVolume(_targetVolume);
  }

  // ================= UI helpers =================

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
        title: const Text('BookShuffle (phone-ready)'),
        centerTitle: true,
      ),

      // >>> Bottom "Select files" button <<<
      bottomNavigationBar: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
          child: FilledButton.icon(
            onPressed: _pickAndAddFiles,
            icon: const Icon(Icons.library_add),
            label: const Text('Select files'),
            style: FilledButton.styleFrom(
              minimumSize: const Size.fromHeight(48),
            ),
          ),
        ),
      ),

      body: SafeArea(
        child: SingleChildScrollView(
          padding: EdgeInsets.fromLTRB(
            16,
            16,
            16,
            16 + MediaQuery.of(context).viewPadding.bottom,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
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
                  // moved the add/select files button to bottomNavigationBar
                ),
              ),
              const SizedBox(height: 12),

              if (_books.isNotEmpty)
                Material(
                  elevation: 1,
                  borderRadius: BorderRadius.circular(8),
                  child: ListView.separated(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
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

              const SizedBox(height: 12),

              // Window length selector
              Row(
                children: [
                  const Text('Play window:'),
                  const SizedBox(width: 12),
                  DropdownButton<Duration>(
                    value: _windowLen,
                    items: _windowOptions
                        .map((d) => DropdownMenuItem(value: d, child: Text('${d.inMinutes} min')))
                        .toList(),
                    onChanged: (val) async {
                      if (val == null) return;
                      setState(() {
                        _windowLen = val;
                        _segmentFadeStarted = false;
                      });
                      if (_windowEnd != null && _duration != null) {
                        final pos = _player.position;
                        var newEnd = pos + _windowLen;
                        if (newEnd > _duration!) newEnd = _duration!;
                        setState(() => _windowEnd = newEnd);
                      }
                    },
                  ),
                ],
              ),
              const SizedBox(height: 12),

              // Fade selectors
              Row(
                children: [
                  const Text('Fade in:'),
                  const SizedBox(width: 12),
                  DropdownButton<Duration>(
                    value: _fadeInDur,
                    items: _fadeOptions
                        .map((d) => DropdownMenuItem(
                              value: d,
                              child: Text('${d.inMilliseconds} ms'),
                            ))
                        .toList(),
                    onChanged: (val) {
                      if (val != null) setState(() => _fadeInDur = val);
                    },
                  ),
                  const SizedBox(width: 32),
                  const Text('Fade out:'),
                  const SizedBox(width: 12),
                  DropdownButton<Duration>(
                    value: _fadeOutDur,
                    items: _fadeOptions
                        .map((d) => DropdownMenuItem(
                              value: d,
                              child: Text('${d.inMilliseconds} ms'),
                            ))
                        .toList(),
                    onChanged: (val) {
                      if (val != null) setState(() => _fadeOutDur = val);
                    },
                  ),
                ],
              ),
              const SizedBox(height: 12),

              // Position slider
              StreamBuilder<Duration>(
                stream: _player.positionStream,
                builder: (context, snap) {
                  final pos = snap.data ?? Duration.zero;
                  final max = dur?.inMilliseconds.toDouble() ?? 0.0;
                  final value = pos.inMilliseconds.clamp(0, max.toInt()).toDouble();

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
                            _windowEnd = null;
                            _segmentFadeStarted = false;
                          });
                          _fadeGen++;
                          _currVolume = _targetVolume;
                          await _player.setVolume(_targetVolume);
                          await _player.seek(seekTo);
                        },
                      ),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(_fmt(pos), style: theme.textTheme.bodySmall),
                          Text(_fmt(dur ?? Duration.zero), style: theme.textTheme.bodySmall),
                        ],
                      ),
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

              const SizedBox(height: 16),

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
                              // Mirror Shuffle’s reliability on resume
                              await _preKickSeek();
                              await _playWithFadeIn();
                            }
                          }
                        : null,
                    icon: StreamBuilder<bool>(
                      stream: _player.playingStream,
                      builder: (_, snap) =>
                          Icon((snap.data ?? false) ? Icons.pause : Icons.play_arrow),
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
              // Extra bottom padding so scrollable content clears the bottom button
              const SizedBox(height: 80),
            ],
          ),
        ),
      ),
    );
  }
}

class _Book {
  final String name;
  final Uri uri; // works for file:// & content://
  final Duration duration;
  final List<Duration> marks;
  const _Book({
    required this.name,
    required this.uri,
    required this.duration,
    required this.marks,
  });
}

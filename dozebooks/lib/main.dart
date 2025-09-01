import 'dart:async';
import 'dart:math';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';
import 'package:just_audio_media_kit/just_audio_media_kit.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  // Enable media_kit backend for Windows (and Linux).
  JustAudioMediaKit.ensureInitialized();

  runApp(const MaterialApp(
    debugShowCheckedModeBanner: false,
    title: 'BookShuffle',
    home: OneScreenAudiobook(), // <- your existing widget from earlier
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
  List<_Segment> _segments = const [];
  int? _currentSegIndex;
  Duration? _segmentEnd;

  StreamSubscription<Duration>? _posSub;

  static const _segLen = Duration(minutes: 20);
  static const _minLastSeg = Duration(minutes: 1);

  @override
  void initState() {
    super.initState();
    // Stop/pause when hitting the end of the active 20-min segment.
    _posSub = _player.positionStream.listen((pos) {
      final end = _segmentEnd;
      if (end != null && pos >= end - const Duration(milliseconds: 150)) {
        _player.pause();
      }
    });
  }

  @override
  void dispose() {
    _posSub?.cancel();
    _player.dispose().onError((e, st) {
      // Ignore plugin teardown mismatch during hot-restart/shutdown
      debugPrint('AudioPlayer.dispose ignored: $e');
    });
    super.dispose();
  }

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
        _currentSegIndex = null;
        _segmentEnd = null;
        _segments = const [];
        _duration = null;
      });

      // Load into the player. setFilePath returns the media duration if known.
      final dur = await _player.setFilePath(path);
      if (dur == null) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Could not determine duration.')),
          );
        }
        return;
      }

      final segs = _buildSegments(dur);
      setState(() {
        _duration = dur;
        _segments = segs;
      });

      if (segs.isEmpty && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Audio too short for 20-min segments.')),
        );
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to load file: $e')),
      );
    }
  }

  List<_Segment> _buildSegments(Duration total) {
    final segs = <_Segment>[];
    for (Duration start = Duration.zero; start < total; start += _segLen) {
      var end = start + _segLen;
      if (end > total) end = total;
      if (end - start >= _minLastSeg) {
        segs.add(_Segment(start: start, end: end));
      }
    }
    return segs;
  }

  String _fmt(Duration d) {
    final h = d.inHours;
    final m = d.inMinutes.remainder(60);
    final s = d.inSeconds.remainder(60);
    if (h > 0) {
      return '${h.toString().padLeft(2, '0')}:'
             '${m.toString().padLeft(2, '0')}:'
             '${s.toString().padLeft(2, '0')}';
    }
    return '${m.toString().padLeft(2, '0')}:'
           '${s.toString().padLeft(2, '0')}';
    }

  Future<void> _togglePlayPause() async {
    if (_player.playing) {
      await _player.pause();
    } else {
      await _player.play();
    }
  }

  Future<void> _shuffle20MinSegment() async {
    if (_segments.isEmpty) return;

    int nextIdx;
    if (_segments.length == 1) {
      nextIdx = 0;
    } else {
      // Avoid picking the same segment twice in a row if possible.
      do {
        nextIdx = _rng.nextInt(_segments.length);
      } while (_currentSegIndex != null && nextIdx == _currentSegIndex);
    }

    final seg = _segments[nextIdx];
    setState(() {
      _currentSegIndex = nextIdx;
      _segmentEnd = seg.end;
    });

    await _player.seek(seg.start);
    await _player.play();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dur = _duration;

    return Scaffold(
      appBar: AppBar(
        title: const Text('BookShuffle (20-min hops)'),
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
                    : Text('Duration: ${_fmt(dur)} • '
                        '${_segments.length} segment(s) of ~20 min'),
                trailing: FilledButton.icon(
                  onPressed: _pickAndLoadFile,
                  icon: const Icon(Icons.folder_open),
                  label: const Text('Load file'),
                ),
              ),
            ),
            const SizedBox(height: 16),
            // Position + slider
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
                          // If user scrubs, clear any active segment end so playback continues.
                          _segmentEnd = null;
                          _currentSegIndex = null;
                        });
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
            const SizedBox(height: 16),
            if (_currentSegIndex != null)
              Text(
                'Current 20-min segment: '
                '${_fmt(_segments[_currentSegIndex!].start)}'
                ' → ${_fmt(_segments[_currentSegIndex!].end)}',
                style: theme.textTheme.bodyMedium,
              ),
            const Spacer(),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                FilledButton.tonalIcon(
                  onPressed: (_duration != null) ? _shuffle20MinSegment : null,
                  icon: const Icon(Icons.shuffle),
                  label: const Text('Shuffle 20-min'),
                ),
                const SizedBox(width: 16),
                FilledButton.icon(
                  onPressed: (_duration != null) ? _togglePlayPause : null,
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
                          setState(() {
                            _segmentEnd = null;
                            _currentSegIndex = null;
                          });
                          await _player.stop();
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

class _Segment {
  final Duration start;
  final Duration end;
  const _Segment({required this.start, required this.end});
}
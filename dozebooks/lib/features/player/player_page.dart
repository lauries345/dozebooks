// lib/features/player/player_page.dart
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:audio_service/audio_service.dart';
import 'package:path/path.dart' as p;

class PlayerPage extends StatefulWidget {
  const PlayerPage({super.key});

  @override
  State<PlayerPage> createState() => _PlayerPageState();
}

class _PlayerPageState extends State<PlayerPage> {
  // Change this to a real file on your machine (or add a file picker later).
  static const String _testPath = r'C:\Projects\Audiobook\HP1 - Harry Potter and The Sorcerers Stone.m4b';

  @override
  Widget build(BuildContext context) {
    final audioHandler = context.read<AudioHandler>();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Audiobook Player'),
        actions: [
          IconButton(
            tooltip: 'Clear queue',
            onPressed: () async {
              final q = audioHandler.queue.value;
              for (final item in q) {
                await audioHandler.removeQueueItem(item);
              }
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Queue cleared.')),
                );
              }
            },
            icon: const Icon(Icons.clear_all),
          )
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Current item title
            StreamBuilder<MediaItem?>(
              stream: audioHandler.mediaItem,
              builder: (context, snap) {
                final title = snap.data?.title ?? 'Nothing playing';
                return Text(
                  title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.titleLarge,
                );
              },
            ),
            const SizedBox(height: 8),

            // Queue length
            StreamBuilder<List<MediaItem>>(
              stream: audioHandler.queue,
              initialData: const [],
              builder: (context, snap) {
                final count = snap.data?.length ?? 0;
                return Text('$count track${count == 1 ? '' : 's'} in queue');
              },
            ),
            const SizedBox(height: 16),

            // Main transport controls
            StreamBuilder<PlaybackState>(
              stream: audioHandler.playbackState,
              builder: (context, snap) {
                final state = snap.data;
                final playing = state?.playing ?? false;
                final shuffleOn =
                    (state?.shuffleMode ?? AudioServiceShuffleMode.none) ==
                        AudioServiceShuffleMode.all;

                return Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  children: [
                    FilledButton.tonal(
                      onPressed: () async {
                        // Add one local file (hard-coded path) to the queue.
                        if (!File(_testPath).existsSync()) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text(
                                  'Test file not found; update _testPath.'),
                            ),
                          );
                          return;
                        }
                        final item = MediaItem(
                          id: Uri.file(_testPath).toString(), // file://... URI
                          title: p.basename(_testPath),
                        );
                        await audioHandler.addQueueItem(item);
                        if (mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(
                                  'Loaded "${p.basename(_testPath)}" into queue.'),
                            ),
                          );
                        }
                      },
                      child: const Text('Load test file'),
                    ),

                    // Shuffle toggle
                    FilledButton.icon(
                      onPressed: () async {
                        await audioHandler.setShuffleMode(
                          shuffleOn
                              ? AudioServiceShuffleMode.none
                              : AudioServiceShuffleMode.all,
                        );
                        if (!mounted) return;
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(
                                'Shuffle ${shuffleOn ? 'disabled' : 'enabled'}'),
                          ),
                        );
                      },
                      icon: Icon(
                        Icons.shuffle,
                        color: shuffleOn
                            ? Theme.of(context).colorScheme.onPrimary
                            : null,
                      ),
                      label: Text('Shuffle ${shuffleOn ? 'On' : 'Off'}'),
                    ),

                    // Play random item
                    OutlinedButton.icon(
                      onPressed: () => audioHandler.customAction('playRandom'),
                      icon: const Icon(Icons.casino),
                      label: const Text('Random'),
                    ),

                    // Transport: previous / play-pause / next / stop
                    IconButton.filledTonal(
                      tooltip: 'Previous',
                      onPressed: () => audioHandler.skipToPrevious(),
                      icon: const Icon(Icons.skip_previous),
                    ),
                    IconButton.filled(
                      tooltip: playing ? 'Pause' : 'Play',
                      onPressed: () =>
                          playing ? audioHandler.pause() : audioHandler.play(),
                      icon: Icon(playing ? Icons.pause : Icons.play_arrow),
                    ),
                    IconButton.filledTonal(
                      tooltip: 'Next',
                      onPressed: () => audioHandler.skipToNext(),
                      icon: const Icon(Icons.skip_next),
                    ),
                    IconButton.outlined(
                      tooltip: 'Stop',
                      onPressed: () => audioHandler.stop(),
                      icon: const Icon(Icons.stop),
                    ),
                  ],
                );
              },
            ),

            const SizedBox(height: 24),

            // Minimal now-playing + position readout (no slider to keep deps light)
            _NowPlayingFooter(audioHandler: audioHandler),
          ],
        ),
      ),
    );
  }
}

class _NowPlayingFooter extends StatelessWidget {
  const _NowPlayingFooter({required this.audioHandler});
  final AudioHandler audioHandler;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<PlaybackState>(
      stream: audioHandler.playbackState,
      builder: (context, snapState) {
        final state = snapState.data;
        final pos = state?.position ?? Duration.zero;

        return StreamBuilder<MediaItem?>(
          stream: audioHandler.mediaItem,
          builder: (context, snapItem) {
            final item = snapItem.data;
            final total = item?.duration ?? Duration.zero;

            return Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(_fmt(pos), style: const TextStyle(fontFeatures: [])),
                if (item?.title != null)
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      child: Text(
                        item!.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                    ),
                  )
                else
                  const Spacer(),
                Text(_fmt(total)),
              ],
            );
          },
        );
      },
    );
  }

  String _fmt(Duration d) {
    final h = d.inHours;
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return h > 0 ? '$h:$m:$s' : '$m:$s';
    // If you prefer always H:MM:SS, remove the conditional.
  }
}

part of refactored_app;

class _OneScreenAudiobookState extends State<OneScreenAudiobook> {
  late final AudioPlayer _player;
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
    // Ensure MediaKit backend is selected even in widget/unit tests (where main() isn't run).
    try {
      JustAudioMediaKit.mpvLogLevel = MPVLogLevel.error;
      JustAudioMediaKit.ensureInitialized();
    } catch (_) {}

    _player = AudioPlayer();
    _posSub = _player.positionStream.listen(_onPos);
    _initAudioSession();
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
      unawaited(this._fadeTo(0.0, remaining));
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

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dur = _duration;

    final currentName = (_currentBookIndex != null && _currentBookIndex! < _books.length)
        ? _books[_currentBookIndex!].name
        : (_fileName ?? 'No file loaded');

    return Scaffold(
      appBar: AppBar(
        title: const Text('dozeBooks'),
        centerTitle: true,
        actions: [
          IconButton(
            tooltip: 'Settings',
            icon: const Icon(Icons.settings),
            onPressed: this._openSettings,
          ),
        ],
      ),

      // >>> Bottom "Add files or folder" button <<<
      bottomNavigationBar: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
          child: FilledButton.icon(
            onPressed: this._addFilesOrFolder,
            icon: const Icon(Icons.library_add),
            label: const Text('Add files or folder'),
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
              // ===== Position slider first =====
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
                          Text(this._fmt(pos), style: theme.textTheme.bodySmall),
                          Text(this._fmt(dur ?? Duration.zero), style: theme.textTheme.bodySmall),
                        ],
                      ),
                    ],
                  );
                },
              ),
              const SizedBox(height: 12),

              if (_currentMarkIndex != null && _duration != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Text(
                    () {
                      final start = _startMarks[_currentMarkIndex!];
                      final shownEnd = _windowEnd ?? (start + _windowLen);
                      final bounded = _minDuration(shownEnd - start, _windowLen);
                      return 'Current window: ${this._fmt(start)} → ${this._fmt(shownEnd)} '
                          '(${bounded.inMinutes} min)';
                    }(),
                    style: theme.textTheme.bodyMedium,
                  ),
                ),

              // ===== Controls =====
              // Row 1: two shuffle buttons on the same line
              Row(
                children: [
                  Expanded(
                    child: FilledButton.tonalIcon(
                      onPressed: (_duration != null && _startMarks.isNotEmpty)
                          ? this._shuffleCurrent
                          : null,
                      icon: const Icon(Icons.shuffle),
                      label: const Text('Shuffle (current)'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: FilledButton.tonalIcon(
                      onPressed: _books.isNotEmpty ? this._shuffleAll : null,
                      icon: const Icon(Icons.all_inclusive),
                      label: const Text('Shuffle (all files)'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),

              // Row 2: play/pause and stop on the same line
              Row(
                children: [
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: (_duration != null)
                          ? () async {
                              if (_player.playing) {
                                await this._pauseWithFadeOut();
                              } else {
                                // Mirror Shuffle’s reliability on resume
                                await this._preKickSeek();
                                await this._playWithFadeIn();
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
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: FilledButton.tonalIcon(
                      onPressed: (_duration != null)
                          ? () async {
                              _windowEnd = null;
                              _segmentFadeStarted = false;
                              await this._stopWithFadeOut();
                            }
                          : null,
                      icon: const Icon(Icons.stop),
                      label: const Text('Stop'),
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 16),

              // ===== File info & list BELOW the buttons =====
              Card(
                elevation: 2,
                child: ListTile(
                  title: Text(currentName),
                  subtitle: (_books.isEmpty || dur == null)
                      ? Text('Files loaded: ${_books.length}. Load .m4b/.m4a/.mp3 to begin.')
                      : Text(
                          'Files: ${_books.length} • '
                          'Duration: ${this._fmt(dur)} • '
                          'Start marks: ${_startMarks.length} • '
                          'Window: ${_windowLen.inMinutes} min',
                        ),
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
                        subtitle: Text('Duration: ${this._fmt(b.duration)} • marks: ${b.marks.length}'),
                        onTap: () async => this._switchToBook(i, autoplay: false),
                      );
                    },
                  ),
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

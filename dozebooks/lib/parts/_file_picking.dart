part of refactored_app;

// Auto-split from _OneScreenAudiobookState for file picking
extension _FilePicking on _OneScreenAudiobookState {
// ================= File/folder picking =================

  /// User entrypoint: choose to add files or a whole folder.
  Future<void> _addFilesOrFolder() async {
    final choice = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (ctx) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.insert_drive_file),
                title: const Text('Add file(s)'),
                subtitle: const Text('Pick one or more audio files'),
                onTap: () => Navigator.pop(ctx, 'files'),
              ),
              ListTile(
                leading: const Icon(Icons.folder),
                title: const Text('Add folder'),
                subtitle: const Text('Recursively import supported audio files'),
                onTap: () => Navigator.pop(ctx, 'folder'),
              ),
            ],
          ),
        );
      },
    );

    if (choice == 'files') {
      await _pickAndAddFiles();
    } else if (choice == 'folder') {
      await _pickAndAddFolder();
    }
  }

  /// Pick single/multiple files and add them.
  Future<void> _pickAndAddFiles() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: const ['m4b', 'm4a', 'mp3'],
        allowMultiple: true,
      );
      if (result == null || result.files.isEmpty) return;

      var addedAny = false;

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
        final ok = await _addOneUri(uri, displayName: f.name);
        addedAny = addedAny || ok;
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

  /// Pick a directory and add all supported audio files recursively.
  Future<void> _pickAndAddFolder() async {
    try {
      // Android: ensure we can enumerate external storage
      if (Platform.isAndroid) {
        final ok = await _ensureFolderAccess();
        if (!ok) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Permission denied. Cannot scan folder.')),
            );
          }
          return;
        }
      }

      final dirPath = await FilePicker.platform.getDirectoryPath();
      if (dirPath == null || dirPath.isEmpty) return;

      // Storage Access Framework picks can look like content://... (not traversable via dart:io)
      if (dirPath.startsWith('content://')) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'That folder is provided via Android’s Storage Access Framework. '
                'Recursive scanning isn’t supported here yet. Use “Add file(s)” for now.',
              ),
            ),
          );
        }
        return;
      }

      final dir = Directory(dirPath);
      if (!dir.existsSync()) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Folder not found: $dirPath')),
          );
        }
        return;
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Scanning: $dirPath')),
        );
      }

      var added = 0;
      await for (final ent in dir.list(recursive: true, followLinks: false)) {
        if (ent is File && _isAudioPath(ent.path)) {
          final uri = Uri.file(ent.path);
          final ok = await _addOneUri(uri);
          if (ok) added++;
        }
      }

      if (added == 0) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'Found no addable audio (or durations were unreadable). '
                'Try “Add file(s)” or open a different folder.',
              ),
            ),
          );
        }
        return;
      }

      if (_currentBookIndex == null && _books.isNotEmpty) {
        await _switchToBook(0, autoplay: false);
      } else {
        setState(() {}); // refresh list
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Added $added file(s).')),
        );
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to add folder: $e')),
      );
    }
  }

  /// Android 13+: READ_MEDIA_AUDIO; <=12: READ_EXTERNAL_STORAGE
  Future<bool> _ensureFolderAccess() async {
    try {
      final results = await [Permission.audio, Permission.storage].request();
      final audioOk = results[Permission.audio]?.isGranted ?? false;
      final storageOk = results[Permission.storage]?.isGranted ?? false;
      return audioOk || storageOk;
    } catch (_) {
      return false;
    }
  }

  bool _isAudioPath(String path) {
    final l = path.toLowerCase();
    return l.endsWith('.m4b') || l.endsWith('.m4a') || l.endsWith('.mp3')
        || l.endsWith('.aac') || l.endsWith('.wav') || l.endsWith('.ogg');
  }

  /// Centralized "add this URI if valid" used by both file/folder flows.
  Future<bool> _addOneUri(Uri uri, {String? displayName}) async {
    // Skip duplicates
    if (_books.any((b) => b.uri.toString() == uri.toString())) return false;

    final dur = await _probeDuration(uri);
    if (dur == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not read duration for ${displayName ?? uri.toString()}')),
        );
      }
      return false;
    }

    final marks = _buildStartMarks(dur, _OneScreenAudiobookState._gridIncrement);
    if (marks.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('File too short for 1-min shuffle: ${displayName ?? uri.toString()}')),
        );
      }
      return false;
    }

    final name = displayName ?? _guessDisplayName(uri);
    _books.add(_Book(name: name, uri: uri, duration: dur, marks: marks));
    return true;
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

  String _guessDisplayName(Uri uri) {
    if (uri.scheme == 'file') {
      final path = uri.toFilePath();
      final sep = Platform.pathSeparator;
      final idx = path.lastIndexOf(sep);
      return (idx >= 0 && idx + 1 < path.length) ? path.substring(idx + 1) : path;
    }
    // Fallback for content:// or other schemes
    if (uri.pathSegments.isNotEmpty) return uri.pathSegments.last;
    return uri.toString();
  }

  /// More tolerant duration probe: waits briefly on durationStream (nullable-safe).
  Future<Duration?> _probeDuration(Uri uri) async {
    final p = AudioPlayer();
    try {
      await p.setVolume(0.0); // silent
      final maybe = await p.setAudioSource(AudioSource.uri(uri));
      if (maybe != null) return maybe;

      // If initial set didn't yield a duration, wait (up to 3s) for the stream to report one.
      final Duration? d = await p.durationStream
          .firstWhere((d) => d != null)
          .timeout(const Duration(seconds: 3), onTimeout: () => null);
      return d;
    } catch (_) {
      return null;
    } finally {
      try {
        await p.dispose();
      } catch (_) {}
    }
  }

  List<Duration> _buildStartMarks(Duration total, Duration increment) {
    final marks = <Duration>[];
    for (Duration start = Duration.zero; start < total; start += increment) {
      if (total - start >= _OneScreenAudiobookState._minPlayableTail) marks.add(start);
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
}

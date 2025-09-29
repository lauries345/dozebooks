part of refactored_app;

// Auto-split from _OneScreenAudiobookState for shuffle
extension _Shuffle on _OneScreenAudiobookState {
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
}

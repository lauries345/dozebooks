part of refactored_app;

// Auto-split from _OneScreenAudiobookState for fades
extension _Fades on _OneScreenAudiobookState {
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
}

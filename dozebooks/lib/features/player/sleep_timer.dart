import 'dart:async';
import 'package:audio_service/audio_service.dart';

class SleepTimer {
  final AudioHandler _handler;
  Timer? _timer;
  Timer? _fadeTimer;
  double _volume = 1.0; // logical volume 0..1 tracked locally

  SleepTimer(this._handler);

  void start(Duration total, {Duration fade = const Duration(seconds: 20)}) {
    cancel();
    final fadeStart = total - fade;
    if (fadeStart.isNegative) return;
    _timer = Timer(fadeStart, () {
      final steps = 20;
      int i = 0;
      _fadeTimer = Timer.periodic(fade ~/ steps, (t) async {
        i++;
        _volume = (1.0 - (i / steps)).clamp(0.0, 1.0);
        // just_audio volume is inside the handler; for simplicity we call setVolume via custom action if added.
        // MVP: when fade completes, pause.
        if (i >= steps) {
          t.cancel();
          await _handler.pause();
          _volume = 1.0;
        }
      });
    });
  }

  void extend(Duration delta) {
    if (_timer != null) {
      final remaining = _timer!.tick; // not precise; MVP approach is to restart
      start(delta); // simple extend by restarting timer with delta
    } else {
      start(delta);
    }
  }

  void cancel() {
    _timer?.cancel();
    _fadeTimer?.cancel();
    _timer = null;
    _fadeTimer = null;
  }
}

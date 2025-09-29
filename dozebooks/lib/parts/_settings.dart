part of refactored_app;

// Auto-split from _OneScreenAudiobookState for settings
extension _Settings on _OneScreenAudiobookState {
// ================= Settings Sheet =================

  Future<void> _openSettings() async {
    final result = await showModalBottomSheet<_SettingsResult>(
      context: context,
      showDragHandle: true,
      useSafeArea: true,
      builder: (ctx) {
        var tempWindow = _windowLen;
        var tempFadeIn = _fadeInDur;
        var tempFadeOut = _fadeOutDur;

        return StatefulBuilder(
          builder: (context, setSheetState) {
            return Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text('Settings', style: Theme.of(context).textTheme.titleLarge),
                  const SizedBox(height: 16),

                  // Play window
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Play window'),
                    subtitle: const Text('Length of each randomized segment'),
                    trailing: DropdownButton<Duration>(
                      value: tempWindow,
                      items: _windowOptions
                          .map((d) => DropdownMenuItem(
                                value: d,
                                child: Text('${d.inMinutes} min'),
                              ))
                          .toList(),
                      onChanged: (val) => setSheetState(() {
                        if (val != null) tempWindow = val;
                      }),
                    ),
                  ),
                  const Divider(height: 1),

                  // Fade in
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Fade in'),
                    subtitle: const Text('Ramp up volume at start'),
                    trailing: DropdownButton<Duration>(
                      value: tempFadeIn,
                      items: _fadeOptions
                          .map((d) => DropdownMenuItem(
                                value: d,
                                child: Text('${d.inMilliseconds} ms'),
                              ))
                          .toList(),
                      onChanged: (val) => setSheetState(() {
                        if (val != null) tempFadeIn = val;
                      }),
                    ),
                  ),
                  const Divider(height: 1),

                  // Fade out
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Fade out'),
                    subtitle: const Text('Ramp down volume at end'),
                    trailing: DropdownButton<Duration>(
                      value: tempFadeOut,
                      items: _fadeOptions
                          .map((d) => DropdownMenuItem(
                                value: d,
                                child: Text('${d.inMilliseconds} ms'),
                              ))
                          .toList(),
                      onChanged: (val) => setSheetState(() {
                        if (val != null) tempFadeOut = val;
                      }),
                    ),
                  ),

                  const SizedBox(height: 12),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      TextButton(
                        onPressed: () => Navigator.pop(ctx),
                        child: const Text('Cancel'),
                      ),
                      const SizedBox(width: 8),
                      FilledButton(
                        onPressed: () {
                          Navigator.pop(
                            ctx,
                            _SettingsResult(
                              window: tempWindow,
                              fadeIn: tempFadeIn,
                              fadeOut: tempFadeOut,
                            ),
                          );
                        },
                        child: const Text('Save'),
                      ),
                    ],
                  ),
                ],
              ),
            );
          },
        );
      },
    );

    if (!mounted || result == null) return;

    setState(() {
      _windowLen = result.window;
      _fadeInDur = result.fadeIn;
      _fadeOutDur = result.fadeOut;
      _segmentFadeStarted = false;
    });

    // If we’re in the middle of a window, re-bound its end.
    if (_windowEnd != null && _duration != null) {
      final pos = _player.position;
      var newEnd = pos + _windowLen;
      if (newEnd > _duration!) newEnd = _duration!;
      setState(() => _windowEnd = newEnd);
    }
  }
}

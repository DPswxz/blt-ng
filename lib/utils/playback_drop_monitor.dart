/// Tracks cumulative dropped frames from both Media3 and mpv. A new stream,
/// seek, or counter reset must not look like sustained playback overload.
class PlaybackDropMonitor {
  int? _previousDrops;
  Duration? _previousPosition;

  void reset() {
    _previousDrops = null;
    _previousPosition = null;
  }

  bool sample(String text, Duration position) {
    final mpv = RegExp(
      r'decoderDrops=(\d+) renderDrops=(\d+)',
    ).firstMatch(text);
    final exo = text.startsWith('ExoPlayer ')
        ? RegExp(r'\bdropped=(\d+)\b').firstMatch(text)
        : null;
    final int drops;
    if (mpv != null) {
      drops = int.parse(mpv[1]!) + int.parse(mpv[2]!);
    } else if (exo != null) {
      drops = int.parse(exo[1]!);
    } else {
      return false;
    }
    final previousDrops = _previousDrops;
    final previousPosition = _previousPosition;
    _previousDrops = drops;
    _previousPosition = position;
    if (previousDrops == null || previousPosition == null) return false;
    final elapsed = (position - previousPosition).inSeconds;
    return elapsed >= 8 && elapsed <= 22 && drops - previousDrops >= 45;
  }
}

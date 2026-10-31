/// Sorted time index: each playback update visits only the current interval.
class DanmakuTimeline<T> {
  final List<T> items;
  final int Function(T) progress;
  DanmakuTimeline(Iterable<T> source, this.progress)
    : items = List<T>.of(source) {
    items.sort((a, b) => progress(a).compareTo(progress(b)));
  }
  int _lowerBound(int time) {
    var lo = 0, hi = items.length;
    while (lo < hi) {
      final mid = (lo + hi) ~/ 2;
      if (progress(items[mid]) < time) {
        lo = mid + 1;
      } else {
        hi = mid;
      }
    }
    return lo;
  }

  Iterable<T> between(int start, int end) sync* {
    if (end <= start) return;
    for (
      var i = _lowerBound(start);
      i < items.length && progress(items[i]) < end;
      i++
    ) {
      yield items[i];
    }
  }
}

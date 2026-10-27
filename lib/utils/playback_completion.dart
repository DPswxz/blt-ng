import 'dart:async';
import 'package:flutter/foundation.dart';

/// Listens only to natural end events, never buffering/error/paused state.
class PlaybackCompletionController extends ValueNotifier<bool> {
  final bool Function() shouldShow;
  final VoidCallback onCompleted;
  final Future<void> Function(Duration) seek;
  final Future<void> Function() play;
  late final StreamSubscription<bool> _subscription;
  bool _disposed = false, _restarting = false;

  PlaybackCompletionController({
    required Stream<bool> completed,
    required this.shouldShow,
    required this.onCompleted,
    required this.seek,
    required this.play,
  }) : super(false) {
    _subscription = completed.listen((finished) {
      if (_disposed) return;
      if (finished && value) return;
      if (!finished) {
        reset();
        return;
      }
      onCompleted();
      if (!_disposed && shouldShow()) value = true;
    });
  }

  void reset() {
    if (!_disposed) value = false;
  }

  Future<void> restart() async {
    if (_disposed || _restarting || !value) return;
    _restarting = true;
    reset();
    try {
      await seek(Duration.zero);
      if (!_disposed) await play();
    } finally {
      _restarting = false;
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _subscription.cancel();
    super.dispose();
  }
}

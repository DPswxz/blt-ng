import 'package:blt/utils/playback_drop_monitor.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Media3 sustained frame loss triggers overload detection', () {
    final monitor = PlaybackDropMonitor();
    expect(
      monitor.sample(
        'ExoPlayer dropped=10 rendered=300',
        const Duration(seconds: 15),
      ),
      isFalse,
    );
    expect(
      monitor.sample(
        'ExoPlayer dropped=60 rendered=700',
        const Duration(seconds: 30),
      ),
      isTrue,
    );
    expect(
      monitor.sample(
        'ExoPlayer dropped=62 rendered=1100',
        const Duration(seconds: 45),
      ),
      isFalse,
    );
  });

  test('mpv combines decoder and render losses, ignoring unrelated logs', () {
    final monitor = PlaybackDropMonitor();
    monitor.sample(
      'BLT_METRICS decoderDrops=3 renderDrops=2',
      const Duration(seconds: 15),
    );
    expect(
      monitor.sample(
        'ExoPlayer firstFrame decoder=avc',
        const Duration(seconds: 25),
      ),
      isFalse,
    );
    expect(
      monitor.sample(
        'BLT_METRICS decoderDrops=30 renderDrops=25',
        const Duration(seconds: 30),
      ),
      isTrue,
    );
  });

  test(
    'new streams, counter resets, pauses and seeks do not cause false downgrade',
    () {
      final monitor = PlaybackDropMonitor();
      monitor.sample('ExoPlayer dropped=200', const Duration(seconds: 60));
      expect(
        monitor.sample('ExoPlayer dropped=1', const Duration(seconds: 75)),
        isFalse,
      );
      expect(
        monitor.sample('ExoPlayer dropped=90', const Duration(seconds: 75)),
        isFalse,
      );
      expect(
        monitor.sample('ExoPlayer dropped=150', const Duration(seconds: 200)),
        isFalse,
      );
      monitor.reset();
      expect(
        monitor.sample('ExoPlayer dropped=300', const Duration(seconds: 215)),
        isFalse,
      );
      expect(
        monitor.sample('ExoPlayer dropped=350', const Duration(seconds: 230)),
        isTrue,
      );
    },
  );
}

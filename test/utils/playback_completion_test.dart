import 'dart:async';
import 'package:blt/utils/playback_completion.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('自然结束且不循环才显示，重新播放只归零并开始一次，释放后不处理事件', () async {
    final events = StreamController<bool>(sync: true);
    var loop = true, ready = true, plays = 0, reports = 0;
    final seeks = <Duration>[];
    final completion = PlaybackCompletionController(
      completed: events.stream,
      shouldShow: () => ready && !loop,
      onCompleted: () => reports++,
      seek: (position) async => seeks.add(position),
      play: () async => plays++,
    );
    events.add(true);
    expect(completion.value, isFalse);
    loop = false;
    ready = false;
    events.add(false);
    events.add(true);
    expect(completion.value, isFalse);
    ready = true;
    events.add(false);
    events.add(true);
    expect(completion.value, isTrue);
    events.add(true);
    expect(reports, 3);
    await Future.wait([completion.restart(), completion.restart()]);
    expect(completion.value, isFalse);
    expect(seeks, [Duration.zero]);
    expect(plays, 1);
    events.add(false);
    events.add(true);
    expect(completion.value, isTrue);
    completion.dispose();
    events.add(true);
    await events.close();
  });
}

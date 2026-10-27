import 'dart:async';
import 'package:blt/utils/playback_completion.dart';
import 'package:blt/consts/settings.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('播放完后三种策略兼容旧设置，自动下一集在末集回到需要确认', () {
    expect(PlayerLoopMode.values.map((m) => m.description), [
      '需要确认',
      '自动下一集',
      '自动循环',
    ]);
    expect(PlayerLoopMode.parse('none'), PlayerLoopMode.none);
    expect(PlayerLoopMode.parse('single'), PlayerLoopMode.single);
    expect(PlayerLoopMode.parse('next'), PlayerLoopMode.next);
    expect(PlayerLoopMode.next.effective(hasNext: true), PlayerLoopMode.next);
    expect(PlayerLoopMode.next.effective(hasNext: false), PlayerLoopMode.none);
    expect(PlayerLoopMode.none.effective(hasNext: true), PlayerLoopMode.none);
    expect(
      PlayerLoopMode.single.effective(hasNext: false),
      PlayerLoopMode.single,
    );
  });
  test('有下一集自动切换且不弹结束界面，末集结束保留确认，偏好不被改写', () async {
    final events = StreamController<bool>(sync: true);
    final preference = PlayerLoopMode.next;
    var index = 0, advances = 0, ready = true;
    bool hasNext() => index < 1;
    final completion = PlaybackCompletionController(
      completed: events.stream,
      shouldShow: () =>
          ready &&
          preference.effective(hasNext: hasNext()) == PlayerLoopMode.none,
      onCompleted: () {
        if (ready &&
            preference.effective(hasNext: hasNext()) == PlayerLoopMode.next) {
          advances++;
          ready = false;
          index++;
        }
      },
      seek: (_) async {},
      play: () async {},
    );
    events.add(true);
    expect(advances, 1);
    expect(index, 1);
    expect(completion.value, isFalse);
    events.add(true);
    expect(advances, 1);
    events.add(false);
    ready = true;
    events.add(true);
    expect(advances, 1);
    expect(completion.value, isTrue);
    expect(preference, PlayerLoopMode.next);
    completion.dispose();
    await events.close();
  });
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

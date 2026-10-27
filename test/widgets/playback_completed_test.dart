import 'package:blt/widgets/playback_completed.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import '../helpers/page_test_env.dart';

void main() {
  setupPageTestEnv();
  testWidgets('播放完成动画在多尺寸无溢出，默认聚焦从头播放且遥控确认可用', (t) async {
    for (final size in [
      const Size(1280, 720),
      const Size(1920, 1080),
      const Size(3840, 2160),
      const Size(1440, 1080),
      const Size(2520, 1080),
    ]) {
      var restarted = 0, next = 0, back = 0;
      await pumpPage(
        t,
        Stack(
          children: [
            PlaybackCompletedOverlay(
              key: ValueKey(size),
              title: '一个很长的视频标题，用来确认播放结束时界面在不同分辨率保持一致。',
              onRestart: () => restarted++,
              onNext: () => next++,
              onBack: () => back++,
            ),
          ],
        ),
        size: size,
      );
      await t.pump(const Duration(milliseconds: 500));
      await t.pump();
      expect(Focus.of(t.element(find.text('从头播放'))).hasFocus, isTrue);
      await t.sendKeyEvent(LogicalKeyboardKey.enter);
      expect(restarted, 1);
      await t.tap(find.text('下一集'));
      expect(next, 1);
      await t.tap(find.text('返回详情'));
      expect(back, 1);
      expect(t.takeException(), isNull, reason: '$size');
      await t.pumpWidget(const SizedBox());
    }
  });
}

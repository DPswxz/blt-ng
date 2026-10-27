import 'package:blt/widgets/playback_completed.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import '../helpers/page_test_env.dart';

void main() {
  setupPageTestEnv();
  testWidgets('结束界面出现后接管原播放器焦点，无下一集时保持重播可选', (t) async {
    final screen = FocusNode();
    final completed = ValueNotifier(false);
    var restart = 0, leaked = 0;
    await pumpPage(
      t,
      Focus(
        focusNode: screen,
        autofocus: true,
        onKeyEvent: (_, _) {
          leaked++;
          return KeyEventResult.ignored;
        },
        child: ValueListenableBuilder<bool>(
          valueListenable: completed,
          builder: (_, visible, _) => Stack(
            children: [
              const ColoredBox(color: Colors.blue),
              if (visible)
                PlaybackCompletedOverlay(
                  title: '视频',
                  onRestart: () => restart++,
                ),
            ],
          ),
        ),
      ),
    );
    await t.pump();
    screen.requestFocus();
    await t.pump();
    completed.value = true;
    await t.pump();
    await t.pump(const Duration(milliseconds: 350));
    expect(Focus.of(t.element(find.text('重播'))).hasFocus, isTrue);
    expect(find.text('下一集'), findsNothing);
    expect(find.byType(BackdropFilter), findsOneWidget);
    await t.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await t.pump();
    await t.sendKeyEvent(LogicalKeyboardKey.select);
    await t.pump();
    expect(restart, 1);
    expect(leaked, 0);
    await t.pumpWidget(const SizedBox());
    screen.dispose();
    completed.dispose();
  });
  testWidgets('播放完成动画在多尺寸无溢出，默认聚焦从头播放且遥控确认可用', (t) async {
    for (final size in [
      const Size(1280, 720),
      const Size(1920, 1080),
      const Size(3840, 2160),
      const Size(1440, 1080),
      const Size(2520, 1080),
    ]) {
      var restarted = 0, next = 0;
      await pumpPage(
        t,
        Stack(
          children: [
            PlaybackCompletedOverlay(
              key: ValueKey(size),
              title: '一个很长的视频标题，用来确认播放结束时界面在不同分辨率保持一致。',
              onRestart: () => restarted++,
              onNext: () => next++,
            ),
          ],
        ),
        size: size,
      );
      await t.pump(const Duration(milliseconds: 500));
      await t.pump();
      expect(Focus.of(t.element(find.text('重播'))).hasFocus, isTrue);
      for (final label in ['重播', '下一集']) {
        final skin =
            t
                    .widget<AnimatedContainer>(
                      find
                          .descendant(
                            of: find.byKey(ValueKey('completed-$label')),
                            matching: find.byType(AnimatedContainer),
                          )
                          .first,
                    )
                    .decoration!
                as BoxDecoration;
        final overWhite = Color.alphaBlend(skin.color!, Colors.white);
        final whiteContrast = 1.05 / (overWhite.computeLuminance() + .05);
        expect(whiteContrast, greaterThanOrEqualTo(4));
      }
      await t.sendKeyEvent(LogicalKeyboardKey.enter);
      expect(restarted, 1);
      await t.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await t.pump();
      expect(Focus.of(t.element(find.text('下一集'))).hasFocus, isTrue);
      await t.sendKeyEvent(LogicalKeyboardKey.select);
      expect(next, 1);
      expect(find.text('返回详情'), findsNothing);
      expect(find.text('播放完成'), findsNothing);
      expect(find.text('一个很长的视频标题，用来确认播放结束时界面在不同分辨率保持一致。'), findsNothing);
      final replayRect = t.getRect(find.byKey(const ValueKey('completed-重播')));
      final nextRect = t.getRect(find.byKey(const ValueKey('completed-下一集')));
      expect(
        (replayRect.center.dx + nextRect.center.dx) / 2,
        closeTo(size.width / 2, .1),
      );
      expect(replayRect.center.dy, closeTo(size.height / 2, .1));
      expect(
        t.getSize(find.byKey(const ValueKey('completed-重播'))),
        t.getSize(find.byKey(const ValueKey('completed-下一集'))),
      );
      await t.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
      await t.pump();
      await t.sendKeyEvent(LogicalKeyboardKey.enter);
      expect(restarted, 2);
      expect(t.takeException(), isNull, reason: '$size');
      await t.pumpWidget(const SizedBox());
    }
  });
}

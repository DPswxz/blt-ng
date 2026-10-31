import 'dart:ui' as ui;
import 'package:blt/utils/danmaku_timeline.dart';
import 'package:canvas_danmaku/canvas_danmaku.dart';
import 'package:canvas_danmaku/scroll_danmaku_painter.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('密集时间轴只访问当前时间窗，支持逆向跳转和无序原始数据', () {
    var visits = 0;
    final index = DanmakuTimeline(
      List.generate(20000, (i) => (19999 - i) * 20),
      (int item) {
        visits++;
        return item;
      },
    );
    visits = 0;
    expect(
      index.between(200000, 200200),
      List.generate(10, (i) => 200000 + i * 20),
    );
    expect(visits, lessThan(50));
    expect(index.between(0, 40), [0, 20]);
    expect(index.between(60, 60), isEmpty);
    expect(index.between(100, 0), isEmpty);
  });

  test('弹幕位移随时间线性变化，重复绘制和漏帧不会累积位移误差', () {
    final repaint = ValueNotifier(0);
    var tick = 0;
    final item = DanmakuItem(
      content: DanmakuContentItem('流畅弹幕'),
      creationTime: 0,
      width: 100,
      height: 30,
    );
    final painter = ScrollDanmakuPainter(
      items: [item],
      durationSeconds: 10,
      fontSize: 30,
      fontWeight: 4,
      showStroke: true,
      tick: () => tick,
      repaint: repaint,
    );
    void paint() {
      final recorder = ui.PictureRecorder();
      painter.paint(Canvas(recorder), const Size(1920, 108));
      recorder.endRecording().dispose();
    }

    paint();
    expect(item.xPosition, 1920);
    tick = 1000;
    paint();
    expect(item.xPosition, closeTo(1718, 0.001));
    paint();
    expect(item.xPosition, closeTo(1718, 0.001));
    tick = 6000;
    paint();
    expect(item.xPosition, closeTo(708, 0.001));
    tick = 11000;
    paint();
    expect(item.xPosition, -100);
    repaint.dispose();
  });

  test('慢中高速度对应实际位移，半透明文字直接绘制到画布', () async {
    for (final duration in [14, 10, 6]) {
      final repaint = ValueNotifier(0);
      final item = DanmakuItem(
        content: DanmakuContentItem('X', color: Colors.white),
        creationTime: 0,
        width: 100,
        height: 30,
      );
      final painter = ScrollDanmakuPainter(
        items: [item],
        durationSeconds: duration,
        fontSize: 30,
        fontWeight: 4,
        showStroke: false,
        opacity: 0.4,
        tick: () => 3000,
        repaint: repaint,
      );
      final recorder = ui.PictureRecorder();
      painter.paint(Canvas(recorder), const Size(200, 80));
      expect(
        item.xPosition,
        closeTo(200 - 3000 / (duration * 1000) * 300, 0.001),
      );
      final picture = recorder.endRecording();
      final image = picture.toImageSync(300, 80);
      final pixels = await image.toByteData();
      var maxAlpha = 0;
      for (var i = 3; i < pixels!.lengthInBytes; i += 4) {
        final alpha = pixels.getUint8(i);
        if (alpha > maxAlpha) maxAlpha = alpha;
      }
      expect(maxAlpha, inInclusiveRange(100, 103));
      image.dispose();
      picture.dispose();
      repaint.dispose();
    }
  });

  testWidgets('滚动绘制沿用同一画笔，不按每帧重建Widget；暂停清空销毁安全', (tester) async {
    DanmakuController? controller;
    await tester.pumpWidget(
      MaterialApp(
        home: DanmakuScreen(
          createdController: (c) => controller = c,
          option: DanmakuOption(fontSize: 30),
        ),
      ),
    );
    controller!.addDanmaku(DanmakuContentItem('第一条'));
    await tester.pump();
    final finder = find.byWidgetPredicate(
      (w) => w is CustomPaint && w.painter is ScrollDanmakuPainter,
    );
    final painter =
        tester.widget<CustomPaint>(finder).painter as ScrollDanmakuPainter;
    final firstTick = painter.tick();
    for (var i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 16));
    }
    expect(
      identical(tester.widget<CustomPaint>(finder).painter, painter),
      isTrue,
    );
    expect(painter.tick() - firstTick, 80);
    controller!.pause();
    controller!.resume();
    controller!.pause();
    controller!.resume();
    controller!.clear();
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 200));
    expect(tester.takeException(), isNull);
    expect(tester.binding.transientCallbackCount, 0);
  });
}

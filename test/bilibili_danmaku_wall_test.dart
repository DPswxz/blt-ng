import 'package:blt/storages/settings.dart';
import 'package:flutter/material.dart';
import 'helpers/page_test_env.dart';
import 'package:blt/widgets/bilibili_danmaku_wall.dart';
import 'package:canvas_danmaku/canvas_danmaku.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  setupPageTestEnv();
  testWidgets('初始弹幕字号30、透明度40、顶部10%', (t) async {
    final controller = BilibiliDanmakuWallController(true);
    await pumpPage(
      t,
      BilibiliDanmakuWall(
        controller: controller,
        cid: 1,
        timeline: const Stream<Duration>.empty(),
        playing: const Stream<bool>.empty(),
      ),
    );
    await flush(t);
    final option = t.widget<DanmakuScreen>(find.byType(DanmakuScreen)).option;
    expect(option.fontSize, 30);
    expect(option.opacity, 0.6);
    expect(
      t
          .widget<FractionallySizedBox>(find.byType(FractionallySizedBox))
          .heightFactor,
      0.1,
    );
    await t.pumpWidget(const SizedBox());
    await t.pump(const Duration(milliseconds: 200));
    controller.dispose();
  });
  testWidgets('关闭弹幕卸载画布并停止动画，再开启时重建可用画布', (t) async {
    final controller = BilibiliDanmakuWallController(false);
    await pumpPage(
      t,
      BilibiliDanmakuWall(
        controller: controller,
        cid: 1,
        timeline: const Stream<Duration>.empty(),
        playing: const Stream<bool>.empty(),
      ),
    );
    await flush(t);
    expect(find.byType(DanmakuScreen), findsNothing);
    controller.enabled = true;
    await flush(t);
    expect(find.byType(DanmakuScreen), findsOneWidget);
    controller.addDanmaku(DanmakuContentItem('测试滚动弹幕'));
    await t.pump();
    controller.enabled = false;
    await t.pump();
    await t.pump(const Duration(milliseconds: 200));
    expect(find.byType(DanmakuScreen), findsNothing);
    expect(t.binding.transientCallbackCount, 0);
    controller.enabled = true;
    await flush(t);
    expect(find.byType(DanmakuScreen), findsOneWidget);
    controller.addDanmaku(DanmakuContentItem('重新启用后可用'));
    await t.pumpWidget(const SizedBox());
    await t.pump(const Duration(milliseconds: 200));
    controller.dispose();
    expect(t.takeException(), isNull);
  });
  testWidgets('显示区域和透明度实时更新真实弹幕画布，并保留持久设置', (t) async {
    final controller = BilibiliDanmakuWallController(true);
    await pumpPage(
      t,
      BilibiliDanmakuWall(
        controller: controller,
        cid: 1,
        timeline: const Stream<Duration>.empty(),
        playing: const Stream<bool>.empty(),
      ),
    );
    await flush(t);
    for (final area in [5, 10, 25, 50]) {
      await Settings.setInt(Settings.pathDanmuArea, area);
      await Settings.setInt(Settings.pathDanmuTransparency, 60);
      await controller.reloadSettings();
      await flush(t);
      final box = t.widget<FractionallySizedBox>(
        find.byType(FractionallySizedBox),
      );
      expect(box.heightFactor, area / 100);
      expect(
        t.widget<DanmakuScreen>(find.byType(DanmakuScreen)).option.opacity,
        closeTo(0.4, 0.001),
      );
      expect(
        find.descendant(
          of: find.byType(DanmakuScreen),
          matching: find.byType(Opacity),
        ),
        findsNothing,
      );
      expect(await Settings.getInt(Settings.pathDanmuArea), area);
      expect(t.takeException(), isNull);
    }
    await t.pumpWidget(const SizedBox());
    await t.pump(const Duration(milliseconds: 200));
    controller.dispose();
  });
  testWidgets('移动速度设置实时应用为14/10/6秒并保留透明度', (t) async {
    final controller = BilibiliDanmakuWallController(true);
    await pumpPage(
      t,
      BilibiliDanmakuWall(
        controller: controller,
        cid: 1,
        timeline: const Stream<Duration>.empty(),
        playing: const Stream<bool>.empty(),
      ),
    );
    await flush(t);
    expect(
      t.widget<DanmakuScreen>(find.byType(DanmakuScreen)).option.duration,
      10,
    );
    for (final entry in {0: 14, 1: 10, 2: 6, 99: 10}.entries) {
      await Settings.setInt(Settings.pathDanmuSpeed, entry.key);
      await controller.reloadSettings();
      await flush(t);
      final option = t.widget<DanmakuScreen>(find.byType(DanmakuScreen)).option;
      expect(option.duration, entry.value);
      expect(option.opacity, 0.6);
    }
    await t.pumpWidget(const SizedBox());
    await t.pump(const Duration(milliseconds: 200));
    controller.dispose();
  });
  testWidgets('非法旧值安全回退，多分辨率下保持区域比例', (t) async {
    await Settings.setInt(Settings.pathDanmuArea, -1);
    await Settings.setInt(Settings.pathDanmuTransparency, 200);
    for (final size in const [
      Size(1280, 720),
      Size(1920, 1080),
      Size(3840, 2160),
    ]) {
      final controller = BilibiliDanmakuWallController(true);
      await pumpPage(
        t,
        BilibiliDanmakuWall(
          key: ValueKey(size),
          controller: controller,
          cid: 1,
          timeline: const Stream<Duration>.empty(),
          playing: const Stream<bool>.empty(),
        ),
        size: size,
      );
      await flush(t);
      expect(
        t
            .widget<FractionallySizedBox>(find.byType(FractionallySizedBox))
            .heightFactor,
        0.1,
      );
      expect(t.takeException(), isNull);
      await t.pumpWidget(const SizedBox());
      await t.pump(const Duration(milliseconds: 200));
      controller.dispose();
    }
  });
  test('弹幕墙未就绪时控制器操作均为空操作', () {
    final controller = BilibiliDanmakuWallController(true);
    expect(controller.enabled, isTrue);

    // 弹幕墙（DanmakuScreen）尚未创建时不应抛异常
    controller.clear();
    controller.wait(const Duration(seconds: 1));
    controller.pause();
    controller.resume();
    controller.addDanmaku(DanmakuContentItem('测试弹幕'));

    controller.enabled = false;
    expect(controller.enabled, isFalse);
    controller.dispose();
  });
}

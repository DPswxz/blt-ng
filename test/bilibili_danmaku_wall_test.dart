import 'package:blt/storages/settings.dart';
import 'package:flutter/material.dart';
import 'helpers/page_test_env.dart';
import 'package:blt/widgets/bilibili_danmaku_wall.dart';
import 'package:canvas_danmaku/canvas_danmaku.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  setupPageTestEnv();
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
      final opacity = t.widget<Opacity>(
        find.descendant(
          of: find.byType(DanmakuScreen),
          matching: find.byType(Opacity),
        ),
      );
      expect(opacity.opacity, closeTo(0.4, 0.001));
      expect(await Settings.getInt(Settings.pathDanmuArea), area);
      expect(t.takeException(), isNull);
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

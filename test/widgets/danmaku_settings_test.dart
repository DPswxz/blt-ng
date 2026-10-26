import 'package:blt/storages/settings.dart';
import 'package:blt/widgets/bilibili_danmaku_wall.dart';
import 'package:blt/widgets/danmaku_settings.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import '../helpers/page_test_env.dart';

void main() {
  setupPageTestEnv();
  testWidgets('区域仅5/10/25/50默认10，透明度可保存，电视尺寸无溢出', (t) async {
    for (final size in const [
      Size(1280, 720),
      Size(1920, 1080),
      Size(3840, 2160),
    ]) {
      final controller = BilibiliDanmakuWallController(true);
      await Settings.setInt(Settings.pathDanmuArea, 10);
      await pumpPage(
        t,
        Builder(
          builder: (context) => ElevatedButton(
            onPressed: () =>
                showDanmakuSettings(context, controller, onToggle: () {}),
            child: const Text('打开弹幕'),
          ),
        ),
        size: size,
      );
      await t.tap(find.text('打开弹幕'));
      await t.pumpAndSettle();
      await t.tap(find.text('显示区域：顶部 10%'));
      await t.pumpAndSettle();
      for (final label in ['顶部 5%', '顶部 10%', '顶部 25%', '顶部 50%']) {
        expect(find.text(label), findsOneWidget);
      }
      expect(find.textContaining('全屏'), findsNothing);
      await t.tap(find.text('顶部 5%'));
      await t.pumpAndSettle();
      expect(await Settings.getInt(Settings.pathDanmuArea), 5);
      await t.tap(find.text('打开弹幕'));
      await t.pumpAndSettle();
      await t.tap(find.textContaining('透明度：'));
      await t.pumpAndSettle();
      await t.tap(find.text('60%'));
      await t.pumpAndSettle();
      expect(await Settings.getInt(Settings.pathDanmuTransparency), 60);
      expect(t.takeException(), isNull);
      await t.pumpWidget(const SizedBox());
      controller.dispose();
    }
  });
}

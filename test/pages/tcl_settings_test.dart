import 'package:blt/consts/settings.dart';
import 'package:blt/widgets/playback_mode_icon.dart';
import 'package:blt/widgets/custom_setting_tiles.dart';
import 'package:blt/widgets/bilibili_danmaku_wall.dart';
import 'package:canvas_danmaku/canvas_danmaku.dart';
import 'package:blt/pages/setting.dart';
import 'package:blt/storages/settings.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import '../helpers/page_test_env.dart';

void main() {
  setupPageTestEnv();
  testWidgets('默认画质与解码设置在720p/1080p/4K布局正常并能保存', (tester) async {
    for (final size in [
      const Size(1280, 720),
      const Size(1920, 1080),
      const Size(3840, 2160),
    ]) {
      await pumpPage(tester, SettingPage(key: ValueKey(size)), size: size);
      await flush(tester);
      expect(find.text('进入视频默认画质'), findsOneWidget);
      expect(find.text('解码方式'), findsOneWidget);
      expect(find.text('音轨设置'), findsOneWidget);
      expect(find.text('播放设置'), findsOneWidget);
      expect(tester.takeException(), isNull);
    }
    await tester.tap(find.text('进入视频默认画质'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('720P 准高清'));
    await tester.pumpAndSettle();
    expect(await Settings.getInt(Settings.pathDefaultQuality), 64);
  });
  testWidgets('默认画质包含4K，说明位于该项下面，没有第四项说明', (tester) async {
    await pumpPage(tester, const SettingPage());
    await flush(tester);
    expect(find.text('播放设置'), findsOneWidget);
    expect(find.textContaining('每个视频按默认画质进入'), findsOneWidget);
    await tester.tap(find.text('进入视频默认画质'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('4K 超高清 · 大会员'));
    await tester.pumpAndSettle();
    expect(await Settings.getInt(Settings.pathDefaultQuality), 120);
    await tester.tap(find.text('进入视频默认画质'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('1080P 高码率 · 大会员'));
    await tester.pumpAndSettle();
    expect(await Settings.getInt(Settings.pathDefaultQuality), 112);
  });
  for (final size in const [
    Size(1280, 720),
    Size(1920, 1080),
    Size(3840, 2160),
  ]) {
    testWidgets('分组设置保存弹幕并在真实画布生效 $size', (tester) async {
      await pumpPage(tester, const SettingPage(), size: size);
      await flush(tester);
      await tester.ensureVisible(find.text('音轨设置'));
      await tester.tap(find.text('音轨设置'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('AAC · 132K'));
      await tester.pumpAndSettle();
      expect(await Settings.getInt(Settings.pathPreferredAudio), 30232);
      await tester.ensureVisible(find.text('播放完后'));
      for (final mode in [
        PlayerLoopMode.next,
        PlayerLoopMode.single,
        PlayerLoopMode.none,
      ]) {
        await tester.tap(find.text('播放完后'));
        await tester.pumpAndSettle();
        await tester.tap(find.text(mode.description).last);
        await tester.pumpAndSettle();
        expect(
          await Settings.getString(Settings.pathLoopModeSwitch),
          mode.value,
        );
        expect(find.byIcon(playbackModeIcon(mode)), findsOneWidget);
      }
      await tester.ensureVisible(find.text('开启弹幕'));
      final toggle = tester.widget<CustomSettingsSwitchTile>(
        find.byType(CustomSettingsSwitchTile),
      );
      expect(toggle.value, isTrue);
      await tester.tap(find.text('开启弹幕'));
      await tester.pumpAndSettle();
      expect(await Settings.getBool(Settings.pathDanmuSwitch), isFalse);
      await tester.tap(find.text('开启弹幕'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('弹幕字体大小'));
      await tester.tap(find.text('弹幕字体大小'));
      await tester.pumpAndSettle();
      for (final label in ['16', '18', '20', '22']) {
        expect(find.text(label), findsNothing);
      }
      for (final label in ['25', '28', '30', '36', '40', '48', '56']) {
        expect(find.text(label), findsWidgets);
      }
      await tester.tap(find.text('48'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('透明度'));
      await tester.tap(find.text('透明度'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('60%'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('弹幕移动速度'));
      await tester.tap(find.text('弹幕移动速度'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('高'));
      await tester.pumpAndSettle();
      expect(await Settings.getInt(Settings.pathDanmuSpeed), 2);
      final controller = BilibiliDanmakuWallController(
        await Settings.getBool(Settings.pathDanmuSwitch) ?? true,
      );
      await pumpPage(
        tester,
        BilibiliDanmakuWall(
          controller: controller,
          cid: 1,
          timeline: const Stream<Duration>.empty(),
          playing: const Stream<bool>.empty(),
        ),
        size: size,
      );
      await flush(tester);
      final screen = tester.widget<DanmakuScreen>(find.byType(DanmakuScreen));
      expect(screen.option.fontSize, closeTo(48 * size.height / 1080, 0.001));
      expect(screen.option.opacity, 0.4);
      expect(screen.option.duration, 6);
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(milliseconds: 200));
      controller.dispose();
      expect(tester.takeException(), isNull);
    });
  }
}

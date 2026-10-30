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
      expect(find.text('弹幕字体大小'), findsNothing);
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
    expect(find.text('播放设置'), findsNothing);
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
}

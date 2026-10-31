import 'package:blt/utils/playback_navigation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';

void main() {
  testWidgets('番剧原生详情路由可进入播放器并重复播放', (tester) async {
    addTearDown(() => Get.reset());
    await tester.pumpWidget(
      const GetMaterialApp(home: Scaffold(body: Text('首页'))),
    );
    final navigator = Navigator.of(tester.element(find.text('首页')));
    navigator.push(
      MaterialPageRoute<void>(
        settings: const RouteSettings(name: '/Widget'),
        builder: (_) => const Scaffold(body: Text('番剧详情')),
      ),
    );
    await tester.pumpAndSettle();
    for (var i = 0; i < 2; i++) {
      openPlaybackPage(() => const Scaffold(body: Text('播放中')));
      await tester.pumpAndSettle();
      expect(find.text('播放中'), findsOneWidget);
      navigator.pop();
      await tester.pumpAndSettle();
      expect(find.text('番剧详情'), findsOneWidget);
    }
  });
  for (final size in const [
    Size(1280, 720),
    Size(1920, 1080),
    Size(3840, 2160),
  ]) {
    testWidgets('播放入口首帧为不透明黑底，无滑动转场；替换解码路由也不露侧栏 $size', (tester) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      addTearDown(() => Get.reset());
      await tester.pumpWidget(
        const GetMaterialApp(
          home: Scaffold(backgroundColor: Colors.white, body: Text('白色侧边栏')),
        ),
      );
      ModalRoute<dynamic>? route;
      openPlaybackPage(
        () => Builder(
          builder: (context) {
            route = ModalRoute.of(context);
            return const SizedBox.expand(key: ValueKey('playing'));
          },
        ),
      );
      await tester.pump();
      await tester.pump();
      expect(route!.opaque, isTrue);
      expect(route!.transitionDuration, Duration.zero);
      expect(find.text('白色侧边栏'), findsNothing);
      final background = find
          .ancestor(
            of: find.byKey(const ValueKey('playing')),
            matching: find.byType(ColoredBox),
          )
          .first;
      expect(tester.widget<ColoredBox>(background).color, Colors.black);
      expect(tester.getSize(background), size);
      openPlaybackPage(
        () => const SizedBox.expand(key: ValueKey('replacement')),
        replace: true,
      );
      await tester.pump();
      await tester.pump();
      expect(find.byKey(const ValueKey('playing')), findsNothing);
      expect(find.text('白色侧边栏'), findsNothing);
      Get.back();
      await tester.pumpAndSettle();
      expect(find.text('白色侧边栏'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }
}

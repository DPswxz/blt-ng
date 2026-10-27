import 'package:blt/models/video.dart';
import 'package:blt/pages/recommend.dart';
import 'package:blt/storages/recommendation_filter.dart';
import 'package:blt/widgets/video_grid_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import '../helpers/page_test_env.dart';

void main() {
  setupPageTestEnv();
  testWidgets('菜单三个动作均能用方向键和遥控确认选择', (t) async {
    final video = MediaCardInfo.fromJson(feedVideoJson())!;
    final provider = VideoGridViewProvider(initVideos: [video]);
    final chosen = <int>[];
    await pumpPage(
      t,
      VideoGridView(
        provider: provider,
        itemMenuActions: [
          for (var i = 0; i < 3; i++)
            ItemMenuAction(
              title: ['内容不感兴趣', '不想看此UP主', '稍后再看'][i],
              icon: Icons.more_horiz,
              action: (_) => chosen.add(i),
            ),
        ],
      ),
    );
    await flush(t);
    for (var target = 0; target < 3; target++) {
      final listener = t.widget<KeyboardListener>(
        find
            .descendant(
              of: find.byType(VideoGridView),
              matching: find.byType(KeyboardListener),
            )
            .first,
      );
      listener.onKeyEvent!(
        const KeyUpEvent(
          physicalKey: PhysicalKeyboardKey.contextMenu,
          logicalKey: LogicalKeyboardKey.contextMenu,
          timeStamp: Duration.zero,
        ),
      );
      await t.pumpAndSettle();
      for (var i = 0; i < target; i++) {
        await t.sendKeyEvent(LogicalKeyboardKey.arrowRight);
        await t.pump();
      }
      await t.sendKeyEvent(LogicalKeyboardKey.select);
      await t.pumpAndSettle();
      expect(chosen.last, target);
    }
    await t.pumpWidget(const SizedBox());
    provider.dispose();
  });

  testWidgets('推荐菜单移除视频、过滤UP主，刷新和重进仍过滤', (t) async {
    final one = feedVideoJson(aid: 1, title: '视频甲');
    final two = feedVideoJson(aid: 2, title: '视频乙');
    final other = feedVideoJson(aid: 3, title: '其他UP');
    other['owner'] = {'mid': 999, 'name': '另一个UP'};
    final http = mockHttp();
    http.onGet(
      'https://api.bilibili.com/x/web-interface/wbi/index/top/feed/rcmd',
      (s) => s.reply(200, {
        'code': 0,
        'data': {
          'item': [one, two, other],
        },
      }),
    );
    final refresh = ValueNotifier(0);
    await pumpPage(t, RecommendPage(refresh));
    await flush(t);
    var grid = t.widget<VideoGridView>(find.byType(VideoGridView));
    final media = grid.provider.toList();
    final listener = t.widget<KeyboardListener>(
      find
          .descendant(
            of: find.byType(VideoGridView),
            matching: find.byType(KeyboardListener),
          )
          .first,
    );
    listener.onKeyEvent!(
      const KeyUpEvent(
        physicalKey: PhysicalKeyboardKey.contextMenu,
        logicalKey: LogicalKeyboardKey.contextMenu,
        timeStamp: Duration.zero,
      ),
    );
    await t.pumpAndSettle();
    expect(find.text('内容不感兴趣'), findsOneWidget);
    expect(find.text('不想看此UP主'), findsOneWidget);
    await t.tap(find.text('内容不感兴趣'));
    await flush(t);
    expect(find.text('视频甲'), findsNothing);
    expect(find.text('视频乙'), findsOneWidget);
    grid = t.widget<VideoGridView>(find.byType(VideoGridView));
    grid.itemMenuActions
        .singleWhere((a) => a.title == '不想看此UP主')
        .action(media[1]);
    await flush(t);
    expect(find.text('视频乙'), findsNothing);
    expect(find.text('其他UP'), findsOneWidget);
    refresh.value++;
    await flush(t);
    expect(find.text('视频甲'), findsNothing);
    expect(find.text('视频乙'), findsNothing);
    final saved = await RecommendationFilter.load(null);
    expect(saved.allows(media[0]), isFalse);
    expect(saved.allows(media[1]), isFalse);
    expect((await RecommendationFilter.load(88)).allows(media[0]), isTrue);
    await t.pumpWidget(const SizedBox());
    refresh.dispose();
  });
}

import 'package:blt/pages/pages.dart' as app;
import 'package:blt/storages/auth.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:blt/widgets/sidebar.dart';

import '../helpers/page_test_env.dart';

const _rcmdUrl =
    'https://api.bilibili.com/x/web-interface/wbi/index/top/feed/rcmd';
const _historyUrl = 'https://api.bilibili.com/x/web-interface/history/cursor';

void main() {
  setupPageTestEnv();

  void mockRecommend() {
    mockHttp().onGet(
      _rcmdUrl,
      (server) => server.reply(200, {
        'code': 0,
        'data': {
          'item': [feedVideoJson(title: '推荐视频A')],
        },
      }),
    );
  }

  testWidgets('初始展示首页，侧边栏展示全部入口', (tester) async {
    mockRecommend();
    await pumpPage(tester, const app.Page());
    await flush(tester);

    for (final label in ['我的', '搜索', '历史', '动态', '稍后再看', '首页', '设置']) {
      expect(find.text(label), findsOneWidget, reason: '缺少入口：$label');
    }
    expect(find.text('推荐视频A'), findsOneWidget);
  });

  testWidgets('点击搜索切换到搜索页', (tester) async {
    mockRecommend();
    await pumpPage(tester, const app.Page());
    await flush(tester);

    await tester.tap(find.text('搜索'));
    await flush(tester);

    expect(find.text('请输入搜索内容'), findsOneWidget);
  });

  testWidgets('未登录点击需要登录的页面给出登录提示', (tester) async {
    mockRecommend();
    await pumpPage(tester, const app.Page());
    await flush(tester);

    await tester.tap(find.text('历史'));
    await tester.pump();

    expect(find.text('提示：请先点击屏幕左上的默认头像进行登录！'), findsOneWidget);
  });

  testWidgets('登录后点击历史加载历史列表', (tester) async {
    loginInfoNotifier.value = LoginInfo.login(
      mid: 1,
      nickname: '测试用户',
      avatar: 'https://example.invalid/avatar.jpg',
    );
    mockRecommend();
    mockHttp().onGet(
      _historyUrl,
      (server) => server.reply(200, {
        'code': 0,
        'data': {
          'cursor': {'max': 1, 'view_at': 1700000000, 'business': 'archive'},
          'list': [
            {
              'title': '历史视频A',
              'cover': 'https://example.invalid/cover.jpg',
              'duration': 100,
              'goto': 'av',
              'history': {'oid': 170001, 'bvid': 'BV1', 'cid': 1},
              'author_mid': 1,
              'author_name': 'UP',
              'author_face': 'f',
              'view_at': 1700000000,
            },
          ],
        },
      }),
    );

    await pumpPage(tester, const app.Page());
    await flush(tester);

    await tester.tap(find.text('历史'));
    await flush(tester);

    expect(find.text('历史视频A'), findsOneWidget);
  });
  testWidgets('首页返回显示退出确认，取消保留首页', (tester) async {
    mockRecommend();
    await pumpPage(tester, const app.Page());
    await flush(tester);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.text('退出 BLT？'), findsOneWidget);
    await tester.tap(find.text('继续观看'));
    await tester.pumpAndSettle();
    expect(find.text('退出 BLT？'), findsNothing);
    expect(find.text('推荐视频A'), findsOneWidget);
  });

  testWidgets('搜索页返回先回首页，不直接退出应用', (tester) async {
    mockRecommend();
    await pumpPage(tester, const app.Page());
    await flush(tester);
    await tester.tap(find.text('搜索'));
    await flush(tester);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.text('推荐视频A'), findsOneWidget);
    expect(find.text('退出 BLT？'), findsNothing);
  });
  testWidgets('设置在主页面切换并保留侧栏，可返回首页', (tester) async {
    mockRecommend();
    await pumpPage(tester, const app.Page());
    await flush(tester);
    await tester.tap(find.text('设置'));
    await flush(tester);
    expect(find.byType(Sidebar), findsOneWidget);
    expect(find.text('偏好设置'), findsOneWidget);
    expect(find.text('进入视频默认画质'), findsOneWidget);
    final sidebar = tester.widget<Sidebar>(find.byType(Sidebar));
    expect(sidebar.items.singleWhere((e) => e.label == '设置').selected, isTrue);
    await tester.tap(find.text('首页'));
    await flush(tester);
    expect(find.text('推荐视频A'), findsOneWidget);
  });
}

import 'package:blt/storages/search_history.dart';
import 'package:blt/pages/search.dart';
import 'package:blt/widgets/pink_style.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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

    for (final label in ['首页', '搜索', '历史', '动态', '设置']) {
      expect(find.text(label), findsOneWidget, reason: '缺少入口：$label');
    }
    expect(find.text('我的'), findsNothing);
    final sidebar = tester.widget<Sidebar>(find.byType(Sidebar));
    expect(sidebar.items.first.label, '首页');
    expect(find.text('推荐视频A'), findsOneWidget);
  });

  testWidgets('头像打开个人页面并保留侧栏，返回不切换栏目', (tester) async {
    mockRecommend();
    await pumpPage(tester, const app.Page());
    await flush(tester);
    tester.widget<Sidebar>(find.byType(Sidebar)).onAvatarTap();
    await flush(tester);
    expect(find.text('登录后查看追番追剧、收藏夹和稍后再看'), findsOneWidget);
    expect(find.text('账号管理'), findsOneWidget);
    expect(find.byType(Sidebar), findsOneWidget);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.text('账号管理'), findsOneWidget);
    expect(find.text('退出 BLT？'), findsNothing);
  });

  testWidgets('侧栏搜索未切页向右正常进入当前内容，切页后向右进输入框，最后可直接确认退出', (tester) async {
    loginInfoNotifier.value = LoginInfo.login(
      mid: 1,
      nickname: '测试',
      avatar: '',
    );
    final http = mockHttp();
    http.onGet(
      _rcmdUrl,
      (s) => s.reply(200, {
        'code': 0,
        'data': {
          'item': [feedVideoJson(title: '推荐视频A')],
        },
      }),
    );
    http.onGet(
      'https://api.bilibili.com/x/web-interface/wbi/search/square',
      (s) => s.reply(200, {
        'code': 0,
        'data': {
          'trending': {'list': []},
        },
      }),
    );
    await pumpPage(tester, const app.Page());
    await flush(tester);
    final sidebar = tester.widget<Sidebar>(find.byType(Sidebar));
    final text = find.text('搜索');
    final focus = find.ancestor(of: text, matching: find.byType(Focus)).first;
    tester.widget<Focus>(focus).focusNode?.requestFocus();
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pump();
    await flush(tester);
    expect(find.byType(TextField), findsNothing);
    expect(
      sidebar.items.singleWhere((e) => e.label == '搜索').focusAnchor!.hasFocus,
      isFalse,
    );
    expect(
      tester
          .widget<Sidebar>(find.byType(Sidebar))
          .items
          .singleWhere((e) => e.label == '首页')
          .selected,
      isTrue,
    );
    tester.widget<Focus>(focus).focusNode?.requestFocus();
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.select);
    await flush(tester);
    expect(
      tester
          .widget<Sidebar>(find.byType(Sidebar))
          .items
          .singleWhere((e) => e.label == '搜索')
          .selected,
      isTrue,
    );
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await flush(tester);
    final input = tester.widget<TextField>(find.byType(TextField));
    expect(input.focusNode!.hasFocus, isTrue);
    expect(input.readOnly, isTrue);
    expect(sidebar.footer!.label, '退出');
    sidebar.footer!.onTap();
    await tester.pumpAndSettle();
    expect(find.text('退出 BLT？'), findsOneWidget);
    await tester.tap(find.text('继续观看'));
    await tester.pumpAndSettle();
    expect(find.text('退出 BLT？'), findsNothing);
    var exits = 0;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
          if (call.method == 'SystemNavigator.pop') exits++;
          return null;
        });
    addTearDown(
      () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, null),
    );
    sidebar.footer!.onTap();
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(PinkButton, '退出'));
    await tester.pumpAndSettle();
    expect(exits, 1);
  });

  testWidgets('内容左侧返回当前搜索图标，个人页返回头像', (tester) async {
    loginInfoNotifier.value = LoginInfo.login(
      mid: 1,
      nickname: '测试',
      avatar: '',
    );
    final http = mockHttp();
    http.onGet(
      _rcmdUrl,
      (s) => s.reply(200, {
        'code': 0,
        'data': {
          'item': [feedVideoJson()],
        },
      }),
    );
    http.onGet(
      'https://api.bilibili.com/x/web-interface/wbi/search/square',
      (s) => s.reply(200, {
        'code': 0,
        'data': {
          'trending': {'list': []},
        },
      }),
    );
    await pumpPage(tester, const app.Page());
    await flush(tester);
    await tester.tap(find.text('搜索'));
    await flush(tester);
    final input = tester.widget<TextField>(find.byType(TextField));
    input.focusNode!.requestFocus();
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    await tester.pump();
    var sidebar = tester.widget<Sidebar>(find.byType(Sidebar));
    expect(
      sidebar.items
          .singleWhere((item) => item.label == '搜索')
          .focusAnchor!
          .hasFocus,
      isTrue,
    );
    loginInfoNotifier.value = LoginInfo.notLogin;
    await tester.pump();
    sidebar = tester.widget<Sidebar>(find.byType(Sidebar));
    sidebar.onAvatarTap();
    await flush(tester);
    final buttonFocus = find
        .ancestor(of: find.text('账号管理'), matching: find.byType(Focus))
        .first;
    tester.widget<Focus>(buttonFocus).focusNode!.requestFocus();
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    await tester.pump();
    sidebar = tester.widget<Sidebar>(find.byType(Sidebar));
    expect(sidebar.avatarFocusAnchor!.hasFocus, isTrue);
  });

  testWidgets('离开搜索销毁结果页，再进为空闲页，搜索历史仍可点击', (tester) async {
    loginInfoNotifier.value = LoginInfo.login(
      mid: 1,
      nickname: '测试',
      avatar: '',
    );
    final http = mockHttp();
    http.onGet(
      _rcmdUrl,
      (s) => s.reply(200, {
        'code': 0,
        'data': {
          'item': [feedVideoJson()],
        },
      }),
    );
    http.onGet(
      'https://api.bilibili.com/x/web-interface/wbi/search/square',
      (s) => s.reply(200, {
        'code': 0,
        'data': {
          'trending': {'list': []},
        },
      }),
    );
    http.onGet(
      'https://api.bilibili.com/x/web-interface/wbi/search/type',
      (s) => s.reply(200, {
        'code': 0,
        'data': {
          'numResults': 1,
          'numPages': 1,
          'result': [
            {
              'type': 'video',
              'aid': 9,
              'title': '临时视频结果',
              'pic': '',
              'duration': '01:00',
              'mid': 1,
            },
          ],
        },
      }),
    );
    await pumpPage(tester, const app.Page());
    await flush(tester);
    await tester.tap(find.text('搜索'));
    await flush(tester);
    await tester.tap(find.byType(TextField));
    await tester.pump();
    await tester.enterText(find.byType(TextField), '测试查询');
    await tester.testTextInput.receiveAction(TextInputAction.search);
    await flush(tester);
    expect(find.text('临时视频结果'), findsOneWidget);
    await tester.tap(find.text('首页'));
    await flush(tester);
    expect(find.byType(SearchPage, skipOffstage: false), findsNothing);
    expect(await SearchHistory.load(), contains('测试查询'));
    await tester.tap(find.text('搜索'));
    await flush(tester);
    expect(find.text('临时视频结果'), findsNothing);
    expect(
      tester.widget<TextField>(find.byType(TextField)).controller!.text,
      isEmpty,
    );
    expect(find.text('测试查询'), findsOneWidget);
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
  testWidgets('首页返回保留首页，不显示退出确认', (tester) async {
    mockRecommend();
    await pumpPage(tester, const app.Page());
    await flush(tester);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.text('退出 BLT？'), findsNothing);
    expect(find.text('推荐视频A'), findsOneWidget);
    expect(find.textContaining('再按一次返回退出应用'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('首页三秒内双返回退出，超时及切换栏目重置', (tester) async {
    mockRecommend();
    var exits = 0;
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'SystemNavigator.pop') exits++;
      return null;
    });
    addTearDown(
      () => messenger.setMockMethodCallHandler(SystemChannels.platform, null),
    );
    await pumpPage(tester, const app.Page());
    await flush(tester);
    await tester.binding.handlePopRoute();
    await tester.pump(const Duration(seconds: 4));
    await tester.binding.handlePopRoute();
    await tester.pump();
    expect(exits, 0);
    await tester.tap(find.text('设置'));
    await flush(tester);
    await tester.binding.handlePopRoute();
    await tester.pump();
    expect(exits, 0);
    await tester.tap(find.text('首页'));
    await flush(tester);
    await tester.binding.handlePopRoute();
    await tester.pump();
    expect(exits, 0);
    await tester.binding.handlePopRoute();
    await tester.pump();
    expect(exits, 1);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('搜索页返回保留搜索栏目，不退出应用', (tester) async {
    mockRecommend();
    await pumpPage(tester, const app.Page());
    await flush(tester);
    await tester.tap(find.text('搜索'));
    await flush(tester);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    final sidebar = tester.widget<Sidebar>(find.byType(Sidebar));
    expect(sidebar.items.singleWhere((e) => e.label == '搜索').selected, isTrue);
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
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.text('偏好设置'), findsOneWidget);
    expect(find.text('退出 BLT？'), findsNothing);
    await tester.tap(find.text('首页'));
    await flush(tester);
    expect(find.text('推荐视频A'), findsOneWidget);
  });
}

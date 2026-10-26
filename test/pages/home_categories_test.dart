import 'package:blt/apis/bilibili/library.dart';
import 'package:blt/apis/bilibili/recommend.dart';
import 'package:blt/pages/recommend.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import '../helpers/page_test_env.dart';

void main() {
  setupPageTestEnv();
  const base = 'https://api.bilibili.com';
  void mockFeeds() {
    final http = mockHttp();
    http.onGet(
      '$base/x/web-interface/wbi/index/top/feed/rcmd',
      (s) => s.reply(200, {
        'code': 0,
        'data': {
          'item': [feedVideoJson(title: '推荐视频')],
        },
      }),
    );
    http.onGet(
      '$base/x/web-interface/popular',
      (s) => s.reply(200, {
        'code': 0,
        'data': {
          'no_more': true,
          'list': [feedVideoJson(title: '热门视频')],
        },
      }),
    );
    http.onGet(
      '$base/pgc/season/index/result',
      (s) => s.reply(200, {
        'code': 0,
        'data': {
          'has_next': 0,
          'list': [
            {
              'season_id': 1,
              'title': '会员番剧',
              'badge': '会员',
              'season_status': 13,
              'index_show': '全12话',
            },
            {'season_id': 2, 'title': '免费番剧', 'season_status': 1},
            {
              'season_id': 3,
              'title': '限免番剧',
              'badge': '限免',
              'season_status': 13,
            },
          ],
        },
      }),
    );
    http.onGet(
      '$base/pgc/view/web/season',
      (s) => s.reply(200, {
        'code': 0,
        'result': {
          'episodes': [
            {'id': 11, 'aid': 12, 'cid': 13, 'title': '第一话', 'badge': '会员'},
          ],
        },
      }),
    );
  }

  testWidgets('推荐热门番剧切换、会员标记、进入分集及多尺寸布局', (t) async {
    mockFeeds();
    for (final size in const [
      Size(1280, 720),
      Size(1920, 1080),
      Size(3840, 2160),
      Size(1600, 1200),
      Size(2560, 1080),
    ]) {
      final refresh = ValueNotifier(0);
      await pumpPage(
        t,
        RecommendPage(refresh, key: ValueKey(size)),
        size: size,
      );
      await flush(t);
      expect(find.text('推荐视频'), findsOneWidget);
      await t.tap(find.text('热门'));
      await flush(t);
      expect(find.text('热门视频'), findsOneWidget);
      await t.tap(find.text('番剧'));
      await flush(t);
      expect(find.text('会员番剧'), findsOneWidget);
      expect(find.text('大会员'), findsOneWidget);
      expect(find.text('限免'), findsOneWidget);
      await t.tap(find.text('会员番剧'));
      await flush(t);
      expect(find.text('第一话'), findsOneWidget);
      expect(find.text('大会员'), findsOneWidget);
      await t.tap(find.text('返回'));
      await flush(t);
      expect(find.text('免费番剧'), findsOneWidget);
      await t.tap(find.text('推荐'));
      await flush(t);
      expect(find.text('推荐视频'), findsOneWidget);
      expect(t.takeException(), isNull, reason: '$size');
      await t.pumpWidget(const SizedBox());
      refresh.dispose();
    }
  });
  test('热门与番剧分页终止标志、权限标记不误伤限免内容', () async {
    mockFeeds();
    final (popular, more) = await listPopularVideos();
    expect(popular.single.title, '热门视频');
    expect(more, isFalse);
    final catalog = await listBangumiCatalog();
    expect(catalog.hasMore, isFalse);
    expect(catalog.items.map((e) => e.badge), ['大会员', '', '限免']);
    expect(seasonAccessBadge({'badge': '付费', 'season_status': 13}), '付费');
    expect(seasonAccessBadge({'season_status': 13}), '大会员');
    expect(seasonAccessBadge({'badge': '独家', 'season_status': 13}), '大会员');
  });
}

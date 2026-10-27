import 'package:http_mock_adapter/http_mock_adapter.dart';
import 'dart:io';
import 'package:blt/apis/bilibili/comments.dart';
import 'package:blt/apis/bilibili/media.dart';
import 'package:blt/consts/color.dart';
import 'package:blt/icons/iconfont.dart';
import 'package:blt/models/video.dart';
import 'package:blt/pages/video_detail.dart';
import 'package:blt/storages/auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import '../helpers/page_test_env.dart';

Video _fakeVideo() => Video(
  avid: 170001,
  bvid: 'BV1',
  title: '测试视频标题',
  cover: 'https://example.invalid/cover.jpg',
  desc: '测试视频简介，内容比较长，用来验证简介区域的排版效果。',
  duration: const Duration(minutes: 3, seconds: 20),
  stat: Stat(
    viewCount: 1000,
    favoriteCount: 10,
    likeCount: 20,
    dislikeCount: 1,
    coinCount: 5,
    shareCount: 2,
  ),
  userMid: 1,
  userName: '测试UP主',
  userAvatar: 'https://example.invalid/avatar.jpg',
  publishTime: DateTime(2026, 1, 1),
  cid: 1,
  episodes: const [
    Episode(
      index: 1,
      cid: 1,
      title: 'P1',
      duration: Duration(minutes: 3, seconds: 20),
    ),
    Episode(
      index: 2,
      cid: 2,
      title: 'P2',
      duration: Duration(minutes: 5, seconds: 10),
    ),
  ],
);

void main() {
  setupPageTestEnv();
  Future<void> load(WidgetTester tester, ArchiveRelation relation) async {
    loginInfoNotifier.value = LoginInfo.login(
      mid: 1,
      nickname: '测试',
      avatar: '',
    );
    await saveCookie([
      Cookie('DedeUserID', '1'),
      Cookie('bili_jct', 'fake-csrf'),
      Cookie('buvid3', 'test-browser-id'),
    ]);
    await pumpPage(
      tester,
      VideoDetailPage(
        video: _fakeVideo(),
        relation: relation,
        commentsLoader: (_, _, _) async => const CommentPage([], 0),
      ),
    );
    await flush(tester);
  }

  bool active(WidgetTester t, IconData icon) =>
      t.widget<Icon>(find.byIcon(icon)).color == biliPink;
  const base = 'https://api.bilibili.com';
  testWidgets('稍后再看读取已添加状态，可移除并重新添加', (t) async {
    final http = mockHttp();
    http.onGet(
      '$base/x/v2/history/toview',
      (s) => s.reply(200, {
        'code': 0,
        'data': {
          'list': [
            {'aid': 170001},
          ],
        },
      }),
    );
    http.onPost(
      '$base/x/v2/history/toview/del',
      (s) => s.reply(200, {'code': 0}),
      data: Matchers.any,
    );
    http.onPost(
      '$base/x/v2/history/toview/add',
      (s) => s.reply(200, {'code': 0}),
      data: Matchers.any,
    );
    await load(t, ArchiveRelation());
    expect(active(t, IconFont.playlist), isTrue);
    expect(find.byIcon(Icons.thumb_down_rounded), findsNothing);
    await selectFocusable(t, find.byIcon(IconFont.playlist));
    await flush(t);
    expect(active(t, IconFont.playlist), isFalse);
    await selectFocusable(t, find.byIcon(IconFont.playlist));
    await flush(t);
    expect(active(t, IconFont.playlist), isTrue);
  });
  testWidgets('投币入口仅提示功能暂未开放，不提交请求或打开确认框', (t) async {
    final http = mockHttp();
    var calls = 0;
    http.onGet(
      '$base/x/v2/history/toview',
      (s) => s.reply(200, {
        'code': 0,
        'data': {'list': []},
      }),
    );
    http.onPost(
      '$base/x/web-interface/coin/add',
      (s) => s.replyCallback(200, (_) {
        calls++;
        return {'code': 0};
      }),
      data: Matchers.any,
    );
    final relation = ArchiveRelation();
    await load(t, relation);
    await selectFocusable(t, find.byIcon(IconFont.coin));
    await flush(t);
    expect(find.textContaining('功能暂未开放'), findsOneWidget);
    expect(find.text('确认投币？'), findsNothing);
    expect(find.text('投 1 枚硬币'), findsNothing);
    expect(calls, 0);
    expect(relation.coin, 0);
  });
  testWidgets('取消一个收藏夹保留其它收藏状态，全部移除才熄灭', (t) async {
    final http = mockHttp();
    var selectedA = true, selectedB = true;
    http.onGet(
      '$base/x/v2/history/toview',
      (s) => s.reply(200, {
        'code': 0,
        'data': {'list': []},
      }),
    );
    http.onGet(
      '$base/x/v3/fav/folder/created/list-all',
      (s) => s.replyCallback(
        200,
        (_) => {
          'code': 0,
          'data': {
            'list': [
              {'id': 10, 'title': '收藏夹A', 'fav_state': selectedA ? 1 : 0},
              {'id': 20, 'title': '收藏夹B', 'fav_state': selectedB ? 1 : 0},
            ],
          },
        },
      ),
    );
    http.onPost(
      '$base/x/v3/fav/resource/deal',
      (s) => s.reply(200, {'code': 0}),
      data: Matchers.any,
    );
    final relation = ArchiveRelation(favorite: true);
    await load(t, relation);
    await selectFocusable(t, find.byIcon(Icons.star_rounded));
    await t.pumpAndSettle();
    await t.tap(find.text('取消收藏 · 收藏夹A'));
    await t.pumpAndSettle();
    selectedA = false;
    expect(relation.favorite, isTrue);
    await selectFocusable(t, find.byIcon(Icons.star_rounded));
    await t.pumpAndSettle();
    await t.tap(find.text('取消收藏 · 收藏夹B'));
    await t.pumpAndSettle();
    selectedB = false;
    expect(relation.favorite, isFalse);
    expect(active(t, Icons.star_rounded), isFalse);
  });
}

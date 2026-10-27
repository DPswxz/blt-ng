import 'package:blt/apis/bilibili/client.dart' show bilibiliHttpClient;
import 'package:blt/models/video.dart';
import 'package:blt/pages/history.dart';
import 'package:blt/pages/season_detail.dart';
import 'package:blt/pages/video_detail.dart';
import 'package:blt/storages/season_history.dart';
import 'package:blt/widgets/video_actions.dart';
import 'package:blt/widgets/video_comments.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import '../helpers/page_test_env.dart';

Map<String, dynamic> historyRow({bool pgc = true}) => {
  'title': '历史中的第2集',
  'kid': pgc ? 7 : 102,
  'history': {
    'oid': 102,
    'cid': 202,
    'epid': pgc ? 12 : 0,
    'business': pgc ? 'pgc' : 'archive',
  },
};
void main() {
  setupPageTestEnv();
  void mockEpisode() {
    final http = mockHttp();
    http.onGet(
      'https://api.bilibili.com/pgc/view/web/season',
      queryParameters: {'ep_id': 12},
      (s) => s.reply(200, {
        'code': 0,
        'result': {
          'season_id': 7,
          'title': '系列番剧',
          'type': 1,
          'evaluate': '系列简介',
          'up_info': {'mid': 999, 'uname': '系列官方'},
          'user_status': {
            'progress': {'last_ep_id': 11},
          },
          'episodes': [
            {'id': 11, 'aid': 101, 'cid': 201, 'title': '第一集'},
            {'id': 12, 'aid': 102, 'cid': 202, 'title': '第二集'},
          ],
        },
      }),
    );
    http.onGet(
      'https://api.bilibili.com/x/web-interface/view',
      queryParameters: {'aid': 102},
      (s) => s.reply(200, {
        'code': 0,
        'data': {
          'aid': 102,
          'cid': 202,
          'title': '第二集单集',
          'redirect_url': 'https://www.bilibili.com/bangumi/play/ep12',
          'owner': {'mid': 99, 'name': '单集投稿UP'},
          'stat': {'like': 123},
          'pages': [
            {'cid': 202, 'page': 1, 'part': '第二集'},
          ],
        },
      }),
    );
    http.onGet(
      'https://api.bilibili.com/x/web-interface/archive/relation',
      (s) => s.reply(200, {'code': 0, 'data': {}}),
    );
    http.onGet(
      'https://api.bilibili.com/x/relation/stat',
      (s) => s.reply(200, {
        'code': 0,
        'data': {'follower': 2000},
      }),
    );
    http.onGet(
      'https://api.bilibili.com/x/v2/reply',
      (s) => s.reply(200, {
        'code': 0,
        'data': {
          'replies': [],
          'page': {'count': 0},
        },
      }),
    );
  }

  test('历史保留PGC分集与系列标识，普通稿件仍进入普通详情，非视频过滤', () {
    final item = MediaCardInfo.fromHistoryJson(historyRow())!;
    expect(item.type, MediaType.ogv);
    expect(item.episodeId, 12);
    expect(item.seasonId, 7);
    expect(item.avid, 102);
    final page = historyDetailPage(item) as SeasonDetailPage;
    expect(page.episodeId, 12);
    expect(page.initialCid, 202);
    expect(
      historyDetailPage(MediaCardInfo.fromHistoryJson(historyRow(pgc: false))!),
      isA<VideoDetailPageWrap>(),
    );
    expect(
      MediaCardInfo.fromHistoryJson({
        'title': '直播',
        'history': {'business': 'live', 'oid': 88},
      }),
      isNull,
    );
    expect(
      Video.episodeIdFromRedirect(
        'https://www.bilibili.com/bangumi/play/ep12?from=history',
      ),
      12,
    );
    expect(
      Video.episodeIdFromRedirect('https://example.org/bangumi/play/ep12'),
      isNull,
    );
    expect(
      Video.episodeIdFromRedirect('https://www.bilibili.com/video/BV123'),
      isNull,
    );
  });
  testWidgets('历史分集入口覆盖本地和服务器上次记录，复用番剧界面与单集UP', (t) async {
    mockEpisode();
    await SeasonHistory.save(7, 11, 0);
    await pumpPage(
      t,
      historyDetailPage(MediaCardInfo.fromHistoryJson(historyRow())!),
    );
    for (var i = 0; i < 5; i++) {
      await flush(t);
    }
    expect(find.byType(SeasonDetailView), findsOneWidget);
    expect(t.widget<VideoActions>(find.byType(VideoActions)).video.avid, 102);
    expect(
      t.widget<VideoCommentsPanel>(find.byType(VideoCommentsPanel)).avid,
      102,
    );
    expect(find.text('选集'), findsOneWidget);
    expect(find.text('相关推荐'), findsNothing);
    expect(find.text('单集投稿UP'), findsOneWidget);
    expect(find.text('系列官方'), findsNothing);
    expect(t.takeException(), isNull);
    await t.pumpWidget(const SizedBox());
  });
  testWidgets('缺少历史PGC标识时，从稿件跳转识别番剧，不请求相关推荐', (t) async {
    mockEpisode();
    // Record network intent to ensure the ordinary recommendation branch is skipped.
    var related = 0;
    final http = bilibiliHttpClient;
    final listener = InterceptorsWrapper(
      onRequest: (o, h) {
        if (o.path.endsWith('/archive/related')) related++;
        h.next(o);
      },
    );
    http.interceptors.add(listener);
    addTearDown(() => http.interceptors.remove(listener));
    await pumpPage(
      t,
      historyDetailPage(MediaCardInfo.fromHistoryJson(historyRow(pgc: false))!),
    );
    for (var i = 0; i < 6; i++) {
      await flush(t);
    }
    expect(find.byType(SeasonDetailView), findsOneWidget);
    expect(t.widget<VideoActions>(find.byType(VideoActions)).video.avid, 102);
    expect(related, 0);
    expect(find.text('相关推荐'), findsNothing);
    await t.pumpWidget(const SizedBox());
  });
}

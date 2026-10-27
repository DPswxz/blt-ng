import 'dart:async';
import 'dart:io';
import 'package:blt/storages/auth.dart';
import 'package:http_mock_adapter/http_mock_adapter.dart';
import 'package:dio/dio.dart' show InterceptorsWrapper;
import 'package:blt/apis/bilibili/library.dart';
import 'package:blt/apis/bilibili/comments.dart';
import 'package:blt/pages/season_detail.dart';
import 'package:blt/widgets/video_comments.dart';
import 'package:blt/widgets/bilibili_image.dart';
import 'package:blt/widgets/detail_parts.dart';
import 'package:blt/widgets/season_follow_icon.dart';
import 'package:blt/widgets/video_card.dart';
import 'package:blt/storages/season_history.dart';
import 'package:blt/models/video.dart';
import 'package:blt/apis/bilibili/media.dart' show ArchiveRelation;
import 'package:blt/widgets/video_actions.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import '../helpers/page_test_env.dart';

SeasonDetail fixture() => SeasonDetail.fromJson({
  'season_id': 7,
  'type': 1,
  'title': '测试番剧',
  'evaluate': '这是番剧简介。' * 20,
  'rating': {'score': 9.7, 'count': 126000},
  'styles': ['奇幻', '冒险'],
  'areas': [
    {'name': '日本'},
  ],
  'publish': {'pub_time': '2020-01-01'},
  'new_ep': {'desc': '全13话'},
  'user_status': {'follow': 1},
  'actors': '声优名单',
  'staff': '制作人员',
  'up_info': {'uname': '哔哩哔哩番剧', 'mid': 999, 'follower': 100000},
  'episodes': [
    {
      'id': 11,
      'aid': 101,
      'cid': 201,
      'title': '1',
      'long_title': '第一集',
      'cover': 'https://example.invalid/one.jpg',
    },
    {
      'id': 12,
      'aid': 102,
      'cid': 202,
      'title': '2',
      'long_title': '第二集',
      'cover': 'https://example.invalid/two.jpg',
    },
  ],
});

Future<(Video, ArchiveRelation)> fakeEpisode(LibraryEntry ep) async => (
  Video(
    avid: ep.aid!,
    bvid: '',
    cid: ep.cid!,
    title: ep.title,
    cover: ep.cover,
    desc: '',
    duration: const Duration(minutes: 24),
    stat: Stat.fromJson({
      'like': ep.aid,
      'coin': 20,
      'favorite': 30,
      'share': 40,
    }),
    userMid: 99,
    userName: '吉伊卡哇动画官方',
    userAvatar: '',
    publishTime: DateTime(2020),
    episodes: const [],
  ),
  ArchiveRelation(),
);

void main() {
  setupPageTestEnv();
  setUp(() {
    mockHttp().onGet(
      'https://api.bilibili.com/x/relation/stat',
      queryParameters: {'vmid': 99},
      (s) => s.reply(200, {
        'code': 0,
        'data': {'follower': 200000},
      }),
    );
  });
  testWidgets('从已追番入口进入继承订阅状态，取消需确认且可撤销弹窗', (t) async {
    final detail = fixture()..followed = false;
    await pumpPage(
      t,
      SeasonDetailPage(
        seasonId: detail.id,
        knownFollowed: true,
        commentsLoader: (_, _, _) async => const CommentPage([], 0),
        episodeLoader: fakeEpisode,
        loader: (_) async => detail,
      ),
    );
    await flush(t);
    expect(find.text('已追番'), findsOneWidget);
    await t.tap(find.text('已追番'));
    await flush(t);
    expect(find.text('取消追番？'), findsOneWidget);
    await t.tap(find.text('取消'));
    await flush(t);
    expect(detail.followed, isTrue);
  });
  testWidgets('番剧详情多分辨率无溢出，选集切换封面与评论，完整简介可查看', (t) async {
    for (final size in [
      const Size(1280, 720),
      const Size(1920, 1080),
      const Size(3840, 2160),
      const Size(1440, 1080),
      const Size(2520, 1080),
    ]) {
      await pumpPage(
        t,
        SeasonDetailView(
          key: ValueKey(size),
          detail: fixture(),
          commentsLoader: (_, _, _) async => const CommentPage([], 0),
          episodeLoader: fakeEpisode,
          onPlay: (_) async {},
        ),
        size: size,
      );
      await flush(t);
      expect(find.textContaining('9.7分 · 12.6万人评分'), findsOneWidget);
      expect(find.text('奇幻 / 冒险 · 2020 · 全13话'), findsOneWidget);
      expect(find.text('吉伊卡哇动画官方'), findsOneWidget);
      expect(find.text('哔哩哔哩番剧'), findsNothing);
      expect(find.byType(VideoActions), findsOneWidget);
      expect(find.byType(DetailAction), findsNWidgets(6));
      expect(find.text('已追番'), findsOneWidget);
      final action = t.widget<DetailAction>(find.byType(DetailAction).first);
      expect(
        t.getSize(find.byWidget(action)).height,
        closeTo(58 * (size.height / 1080).clamp(0, size.width / 1920), .1),
      );
      expect(
        t.getSize(find.byKey(const ValueKey('season-follow-button'))).width,
        closeTo(t.getSize(find.byWidget(action)).width, .1),
      );
      expect(
        t.getTopLeft(find.byKey(const ValueKey('season-category'))).dy -
            t.getBottomLeft(find.byKey(const ValueKey('season-title'))).dy,
        closeTo(12 * (size.height / 1080).clamp(0, size.width / 1920), .1),
      );
      expect(find.text('关注'), findsOneWidget);
      expect(find.textContaining('发布于 2020'), findsOneWidget);
      expect(find.text('选集'), findsOneWidget);
      expect(find.text('返回'), findsNothing);
      expect(find.byIcon(Icons.video_library_rounded), findsOneWidget);
      expect(
        t.widget<SeasonFollowIcon>(find.byType(SeasonFollowIcon)).followed,
        isTrue,
      );
      expect(
        t.getSize(find.byType(DetailDescription)).height,
        greaterThan(60 * (size.height / 1080).clamp(0, size.width / 1920)),
      );
      expect(find.byType(VideoCard), findsNWidgets(2));
      expect(
        t.getTopLeft(find.byKey(const ValueKey('season-episodes'))).dy,
        lessThan(t.getTopLeft(find.byType(VideoCommentsPanel)).dy),
      );
      expect(
        t.widget<VideoCommentsPanel>(find.byType(VideoCommentsPanel)).avid,
        101,
      );
      t
          .widget<VideoCard>(find.byKey(const ValueKey('season-episode-12')))
          .onFocus!();
      await flush(t);
      expect(
        t.widget<VideoCommentsPanel>(find.byType(VideoCommentsPanel)).avid,
        101,
      );
      t
          .widget<VideoCard>(find.byKey(const ValueKey('season-episode-12')))
          .onTap!();
      await flush(t);
      expect(
        t.widget<VideoCommentsPanel>(find.byType(VideoCommentsPanel)).avid,
        102,
      );
      expect(t.widget<VideoActions>(find.byType(VideoActions)).video.avid, 102);
      expect(
        t
            .widget<BilibiliNetworkImage>(
              find.byType(BilibiliNetworkImage).first,
            )
            .url,
        endsWith('two.jpg'),
      );
      await t.tap(find.byType(DetailDescription));
      await flush(t);
      expect(find.textContaining('制作人员'), findsOneWidget);
      await t.tap(find.text('关闭'));
      await flush(t);
      expect(t.takeException(), isNull, reason: '$size');
      await t.pumpWidget(const SizedBox());
    }
  });
  testWidgets('观看记录定位到分集，确认卡片直接播放对应分集', (t) async {
    await SeasonHistory.save(7, 12, 0);
    int? played;
    await pumpPage(
      t,
      SeasonDetailView(
        detail: fixture(),
        commentsLoader: (_, _, _) async => const CommentPage([], 0),
        episodeLoader: fakeEpisode,
        onPlay: (ep) async {
          played = ep.id;
        },
      ),
    );
    await flush(t);
    expect(
      t.widget<VideoCommentsPanel>(find.byType(VideoCommentsPanel)).avid,
      102,
    );
    await t.tap(find.byKey(const ValueKey('season-episode-12')));
    await flush(t);
    expect(played, 12);
  });
  testWidgets('快速切集只显示最后选中分集的操作数据，旧请求不会覆盖', (t) async {
    final first = Completer<(Video, ArchiveRelation)>();
    final second = Completer<(Video, ArchiveRelation)>();
    await pumpPage(
      t,
      SeasonDetailView(
        detail: fixture(),
        commentsLoader: (_, _, _) async => const CommentPage([], 0),
        episodeLoader: (ep) => ep.id == 11 ? first.future : second.future,
      ),
    );
    await flush(t);
    t
        .widget<VideoCard>(find.byKey(const ValueKey('season-episode-12')))
        .onTap!();
    await t.pump(const Duration(milliseconds: 200));
    second.complete(await fakeEpisode(fixture().episodes[1]));
    await flush(t);
    expect(t.widget<VideoActions>(find.byType(VideoActions)).video.avid, 102);
    first.complete(await fakeEpisode(fixture().episodes[0]));
    await flush(t);
    expect(t.widget<VideoActions>(find.byType(VideoActions)).video.avid, 102);
    expect(
      t.widget<VideoCommentsPanel>(find.byType(VideoCommentsPanel)).avid,
      102,
    );
  });
  testWidgets('焦点不改变选中分集，点击切换详情，再次点击才播放', (t) async {
    final played = <int>[];
    final loaded = <int>[];
    await pumpPage(
      t,
      SeasonDetailView(
        detail: fixture(),
        commentsLoader: (_, _, _) async => const CommentPage([], 0),
        episodeLoader: (ep) {
          loaded.add(ep.id);
          return fakeEpisode(ep);
        },
        onPlay: (ep) async {
          played.add(ep.id);
        },
      ),
    );
    await flush(t);
    final second = find.byKey(const ValueKey('season-episode-12'));
    t.widget<VideoCard>(second).onFocus!();
    await flush(t);
    expect(loaded, [11]);
    expect(t.widget<VideoActions>(find.byType(VideoActions)).video.avid, 101);
    t.widget<VideoCard>(second).onTap!();
    await flush(t);
    expect(played, isEmpty);
    expect(loaded, [11, 12]);
    expect(t.widget<VideoActions>(find.byType(VideoActions)).video.avid, 102);
    t.widget<VideoCard>(second).onTap!();
    await flush(t);
    expect(played, [12]);
  });
  testWidgets('UP主关注按钮可关注和取消，并更新展示状态', (t) async {
    loginInfoNotifier.value = LoginInfo.login(
      mid: 1,
      nickname: '测试',
      avatar: '',
    );
    await saveCookie([Cookie('bili_jct', 'fake-csrf')]);
    final http = mockHttp();
    http.onGet(
      'https://api.bilibili.com/x/relation',
      queryParameters: {'fid': 99},
      (s) => s.reply(200, {
        'code': 0,
        'data': {'attribute': 0},
      }),
    );
    http.onGet(
      'https://api.bilibili.com/x/v2/history/toview',
      (s) => s.reply(200, {
        'code': 0,
        'data': {'list': []},
      }),
    );
    http.onGet(
      'https://api.bilibili.com/x/relation/stat',
      queryParameters: {'vmid': 99},
      (s) => s.reply(200, {
        'code': 0,
        'data': {'follower': 200000},
      }),
    );
    var calls = 0;
    final modifiedMids = <int>[];
    final listener = InterceptorsWrapper(
      onRequest: (options, handler) {
        if (options.path.endsWith('/x/relation/modify')) {
          calls++;
          modifiedMids.add(options.data['fid'] as int);
        }
        handler.next(options);
      },
    );
    http.dio.interceptors.add(listener);
    addTearDown(() => http.dio.interceptors.remove(listener));
    http.onPost(
      'https://api.bilibili.com/x/relation/modify',
      data: Matchers.any,
      (s) {
        s.reply(200, {'code': 0, 'data': {}});
      },
    );
    await pumpPage(
      t,
      SeasonDetailView(
        detail: fixture(),
        episodeLoader: fakeEpisode,
        commentsLoader: (_, _, _) async => const CommentPage([], 0),
      ),
    );
    await flush(t);
    await t.tap(find.text('关注'));
    await flush(t);
    expect(find.text('已关注'), findsOneWidget);
    expect(calls, 1);
    await t.tap(find.text('已关注'));
    await flush(t);
    expect(find.text('关注'), findsOneWidget);
    expect(calls, 2);
    expect(modifiedMids, [99, 99]);
    await t.pumpWidget(const SizedBox());
  });
  testWidgets('番剧详情按一次返回直接回到入口并返回订阅状态', (t) async {
    bool? result;
    await pumpPage(t, const Text('入口'));
    // Use a local route so the test does not request real season data.
    final context = t.element(find.text('入口'));
    Navigator.of(context)
        .push<bool>(
          MaterialPageRoute(
            builder: (_) => SeasonDetailView(
              detail: fixture(),
              commentsLoader: (_, _, _) async => const CommentPage([], 0),
              episodeLoader: fakeEpisode,
            ),
          ),
        )
        .then((value) => result = value);
    await flush(t);
    expect(find.text('返回'), findsNothing);
    await t.binding.handlePopRoute();
    await t.pumpAndSettle();
    expect(find.text('入口'), findsOneWidget);
    expect(result, isTrue);
  });
}

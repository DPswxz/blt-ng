import 'package:blt/apis/bilibili/library.dart';
import 'package:blt/apis/bilibili/comments.dart';
import 'package:blt/pages/season_detail.dart';
import 'package:blt/widgets/video_comments.dart';
import 'package:blt/widgets/bilibili_image.dart';
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

void main() {
  setupPageTestEnv();
  testWidgets('从已追番入口进入继承订阅状态，取消需确认且可撤销弹窗', (t) async {
    final detail = fixture()..followed = false;
    await pumpPage(
      t,
      SeasonDetailPage(
        seasonId: detail.id,
        knownFollowed: true,
        commentsLoader: (_, _, _) async => const CommentPage([], 0),
        loader: (_) async => detail,
      ),
    );
    await flush(t);
    expect(find.text('取消追番'), findsOneWidget);
    await t.tap(find.text('取消追番'));
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
        ),
        size: size,
      );
      await flush(t);
      expect(find.text('9.7 分 · 12.6万 人评分'), findsOneWidget);
      expect(find.text('取消追番'), findsOneWidget);
      expect(
        t.widget<VideoCommentsPanel>(find.byType(VideoCommentsPanel)).avid,
        101,
      );
      await t.tap(find.text('2 第二集'));
      await flush(t);
      expect(
        t.widget<VideoCommentsPanel>(find.byType(VideoCommentsPanel)).avid,
        102,
      );
      expect(
        t.widget<BilibiliNetworkImage>(find.byType(BilibiliNetworkImage)).url,
        endsWith('two.jpg'),
      );
      await t.tap(find.text('简介与资料'));
      await flush(t);
      expect(find.textContaining('制作人员'), findsOneWidget);
      await t.tap(find.text('关闭'));
      await flush(t);
      expect(t.takeException(), isNull, reason: '$size');
      await t.pumpWidget(const SizedBox());
    }
  });
}

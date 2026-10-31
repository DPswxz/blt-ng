import 'dart:io';
import 'package:blt/apis/bilibili/client.dart';
import 'package:blt/apis/bilibili/library.dart';
import 'package:blt/pages/my_library.dart';
import 'package:blt/pages/user_info.dart';
import 'package:blt/storages/auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http_mock_adapter/http_mock_adapter.dart';
import '../helpers/page_test_env.dart';

void main() {
  setupPageTestEnv();
  testWidgets('收藏/番剧卡片在多分辨率显示，加载失败可重试并分页', (t) async {
    for (final size in [
      const Size(1280, 720),
      const Size(1920, 1080),
      const Size(3840, 2160),
    ]) {
      int requests = 0;
      LibraryEntry? selected;
      await pumpPage(
        t,
        LibraryCollectionPane(
          key: ValueKey(size),
          title: '我的收藏夹',
          loader: (page) async {
            requests++;
            if (requests == 1) throw StateError('offline');
            return LibraryBatch([
              LibraryEntry(
                id: page,
                title: '很长的番剧收藏夹标题，确保遥控卡片样式一致',
                subtitle: '看到第十集',
              ),
            ], hasMore: page == 1);
          },
          onOpen: (item) => selected = item,
        ),
        size: size,
      );
      await flush(t);
      await t.tap(find.text('重试'));
      await flush(t);
      expect(find.text('加载更多'), findsOneWidget);
      await t.tap(find.text('加载更多'));
      await flush(t);
      expect(find.text('很长的番剧收藏夹标题，确保遥控卡片样式一致'), findsNWidgets(2));
      await t.tap(find.text('很长的番剧收藏夹标题，确保遥控卡片样式一致').first);
      await t.pump();
      expect(selected?.id, 1);
      expect(t.takeException(), isNull);
    }
  });
  testWidgets('收藏列表长按移除需确认，取消保持内容，确认后刷新', (t) async {
    var removed = false;
    await pumpPage(
      t,
      LibraryCollectionPane(
        title: '收藏夹',
        loader: (_) async => LibraryBatch(
          removed ? [] : [const LibraryEntry(id: 1, title: '待移除视频')],
        ),
        onOpen: (_) {},
        onRemove: (_) async => removed = true,
      ),
    );
    await flush(t);
    await t.longPress(find.text('待移除视频'));
    await t.pumpAndSettle();
    expect(find.text('移出此收藏夹？'), findsOneWidget);
    await t.tap(find.text('取消'));
    await t.pumpAndSettle();
    expect(removed, isFalse);
    expect(find.text('待移除视频'), findsOneWidget);
    await t.longPress(find.text('待移除视频'));
    await t.pumpAndSettle();
    await t.tap(find.text('确认移除'));
    await t.pumpAndSettle();
    expect(removed, isTrue);
    expect(find.text('待移除视频'), findsNothing);
    expect(find.text('暂无内容'), findsOneWidget);
  });

  testWidgets('我的显示按顺序排列的追番追剧、收藏夹、稍后再看，并能进入收藏夹', (t) async {
    await saveSignedInAccount(
      LoginInfo.login(
        mid: 1,
        nickname: '用户',
        avatar: '',
        level: 6,
        vipStatus: 1,
        vipType: 2,
      ),
      [Cookie('SESSDATA', 'one')],
    );
    final adapter = DioAdapter(dio: bilibiliHttpClient);
    adapter.onGet(
      'https://api.bilibili.com/x/web-interface/nav',
      (s) => s.reply(200, {
        'code': 0,
        'data': {
          'mid': 1,
          'uname': '用户',
          'face': '',
          'level_info': {'current_level': 6},
          'vipStatus': 1,
          'vipType': 2,
        },
      }),
    );
    adapter.onGet(
      'https://api.bilibili.com/x/space/bangumi/follow/list',
      (s) => s.reply(200, {
        'code': 0,
        'data': {'list': [], 'total': 0},
      }),
    );
    adapter.onGet(
      'https://api.bilibili.com/x/v3/fav/folder/created/list-all',
      (s) => s.reply(200, {
        'code': 0,
        'data': {
          'list': [
            {'id': 10, 'title': '收藏夹A', 'media_count': 1},
          ],
        },
      }),
    );
    adapter.onGet(
      'https://api.bilibili.com/x/v3/fav/resource/list',
      (s) => s.reply(200, {
        'code': 0,
        'data': {
          'has_more': false,
          'medias': [
            {'id': 170001, 'type': 2, 'attr': 0, 'title': '收藏视频A', 'upper': {}},
          ],
        },
      }),
    );
    await pumpPage(t, const UserInfoPage());
    await flush(t);
    expect(
      t.getCenter(find.text('追番追剧')).dx,
      lessThan(t.getCenter(find.text('收藏夹')).dx),
    );
    expect(
      t.getCenter(find.text('收藏夹')).dx,
      lessThan(t.getCenter(find.text('稍后再看')).dx),
    );
    await t.tap(find.text('收藏夹'));
    await flush(t);
    await t.tap(find.text('收藏夹A'));
    await flush(t);
    expect(find.text('收藏视频A'), findsOneWidget);
    await t.binding.handlePopRoute();
    await t.pumpAndSettle();
    expect(find.text('收藏夹A'), findsOneWidget);
    expect(find.text('收藏视频A'), findsNothing);
    expect(t.takeException(), isNull);
  });
}

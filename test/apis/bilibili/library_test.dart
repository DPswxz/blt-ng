import 'dart:io';
import 'package:blt/apis/bilibili/client.dart';
import 'package:blt/apis/bilibili/library.dart';
import 'package:blt/apis/bilibili/media.dart';
import 'package:blt/apis/bilibili/user.dart';
import 'package:blt/storages/auth.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http_mock_adapter/http_mock_adapter.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    loginInfoNotifier.value = LoginInfo.notLogin;
  });
  test('追番追剧使用目标账号/type并支持分页', () async {
    final adapter = DioAdapter(dio: bilibiliHttpClient);
    adapter.onGet(
      'https://api.bilibili.com/x/space/bangumi/follow/list',
      (s) => s.reply(200, {
        'code': 0,
        'data': {
          'total': 21,
          'list': [
            {'season_id': 3, 'title': '测试番剧', 'cover': '', 'progress': '看到第3话'},
          ],
        },
      }),
      queryParameters: {'vmid': 1, 'type': 2, 'pn': 1, 'ps': 20},
    );
    final result = await listFollowedSeasons(1, type: 2);
    expect(result.items.single.id, 3);
    expect(result.hasMore, isTrue);
  });
  test('收藏夹保留自定义封面，空封面回退到首个有效视频', () async {
    final adapter = DioAdapter(dio: bilibiliHttpClient);
    adapter.onGet(
      'https://api.bilibili.com/x/v3/fav/folder/created/list-all',
      (s) => s.reply(200, {
        'code': 0,
        'data': {
          'list': [
            {
              'id': 10,
              'title': '自定义',
              'cover': 'https://example.invalid/custom.jpg',
            },
            {'id': 20, 'title': '默认收藏夹', 'cover': ''},
          ],
        },
      }),
    );
    adapter.onGet(
      'https://api.bilibili.com/x/v3/fav/resource/list',
      (s) => s.reply(200, {
        'code': 0,
        'data': {
          'medias': [
            {
              'id': 123,
              'type': 2,
              'attr': 0,
              'title': '视频',
              'cover': 'https://example.invalid/video.jpg',
              'upper': {},
            },
          ],
        },
      }),
      queryParameters: {
        'media_id': 20,
        'pn': 1,
        'ps': 20,
        'order': 'mtime',
        'platform': 'web',
      },
    );
    final folders = await listFavoriteFolders(1);
    expect(folders.items[0].cover, 'https://example.invalid/custom.jpg');
    expect(folders.items[1].cover, 'https://example.invalid/video.jpg');
  });
  test('私密收藏夹及视频列表，过滤失效稿件，保留has_more', () async {
    final adapter = DioAdapter(dio: bilibiliHttpClient);
    adapter.onGet(
      'https://api.bilibili.com/x/v3/fav/folder/created/list-all',
      (s) => s.reply(200, {
        'code': 0,
        'data': {
          'list': [
            {'id': 10, 'title': '私密夹', 'attr': 1, 'media_count': 2},
          ],
        },
      }),
    );
    expect(
      (await listFavoriteFolders(1)).items.single.subtitle,
      contains('私密'),
    );
    adapter.onGet(
      'https://api.bilibili.com/x/v3/fav/resource/list',
      (s) => s.reply(200, {
        'code': 0,
        'data': {
          'has_more': true,
          'medias': [
            {
              'id': 170001,
              'type': 2,
              'attr': 0,
              'title': '视频A',
              'cover': '',
              'bvid': 'BV1',
              'upper': {'mid': 2, 'name': '作者'},
            },
            {'id': 2, 'type': 2, 'attr': 9, 'title': '已失效'},
          ],
        },
      }),
    );
    final result = await listFavoriteVideos(10);
    expect(result.items.single.video!.avid, 170001);
    expect(result.hasMore, isTrue);
  });
  test('PGC result封装、正片/特别篇去重、ep_id取流并读取旧画质字段', () async {
    final adapter = DioAdapter(dio: bilibiliHttpClient);
    adapter.onGet(
      'https://api.bilibili.com/pgc/view/web/season',
      (s) => s.reply(200, {
        'code': 0,
        'result': {
          'episodes': [
            {'id': 11, 'aid': 1, 'cid': 2, 'title': '1', 'long_title': '第一话'},
          ],
          'section': [
            {
              'episodes': [
                {'id': 11, 'title': '重复'},
                {'id': 12, 'aid': 3, 'cid': 4, 'title': 'SP'},
              ],
            },
          ],
        },
      }),
    );
    expect((await listSeasonEpisodes(9)).items.map((e) => e.id), [11, 12]);
    adapter.onGet(
      'https://api.bilibili.com/pgc/player/web/playurl',
      (s) => s.reply(200, {
        'code': 0,
        'result': {
          'quality': 80,
          'accept_quality': [80, 64],
          'accept_description': ['1080P', '720P'],
          'dash': {
            'video': [
              {
                'id': 80,
                'base_url': 'https://example.invalid/video',
                'codecid': 7,
              },
            ],
          },
        },
      }),
      queryParameters: {'cid': 2, 'avid': 1, 'ep_id': 11, ...webPlayParameters},
    );
    expect(
      (await getVideoPlayURL(
        avid: 1,
        cid: 2,
        episodeId: 11,
      )).supportFormats.first.id,
      80,
    );
  });
  test('验证另一个账号时使用显式Cookie，不覆盖当前登录', () async {
    await saveSignedInAccount(
      LoginInfo.login(mid: 1, nickname: 'A', avatar: ''),
      [Cookie('SESSDATA', 'A')],
    );
    final adapter = DioAdapter(dio: bilibiliHttpClient);
    String? header;
    final interceptor = InterceptorsWrapper(
      onRequest: (options, handler) {
        header = options.headers['Cookie'] as String?;
        handler.next(options);
      },
    );
    bilibiliHttpClient.interceptors.add(interceptor);
    adapter.onGet(
      'https://api.bilibili.com/x/web-interface/nav',
      (s) => s.reply(200, {
        'code': 0,
        'data': {
          'mid': 2,
          'uname': 'B',
          'face': '',
          'level_info': {'current_level': 5},
          'vipType': 2,
          'vipStatus': 1,
          'vipDueDate': 1800000000000,
          'vip_label': {'text': '年度大会员'},
        },
      }),
    );
    try {
      final info = await getMySelfInfo(cookies: [Cookie('SESSDATA', 'B')]);
      expect(header, 'SESSDATA=B');
      expect(info.loginProfile.level, 5);
      expect(info.loginProfile.membershipLabel, '年度大会员');
      expect(loginInfoNotifier.value.mid, 1);
    } finally {
      bilibiliHttpClient.interceptors.remove(interceptor);
    }
  });
}

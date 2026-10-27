import 'package:blt/apis/bilibili/client.dart';
import 'package:blt/apis/bilibili/library.dart';
import 'package:blt/apis/bilibili/media.dart';
import 'package:blt/apis/bilibili/error.dart';
import 'package:blt/storages/auth.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http_mock_adapter/http_mock_adapter.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(
    () => SharedPreferences.setMockInitialValues({
      'bilibili_cookie': 'SESSDATA=fake; bili_jct=csrf',
    }),
  );
  test('番剧明细解析评分、追番状态和各分集，追番接口带CSRF', () async {
    final http = DioAdapter(dio: bilibiliHttpClient);
    http.onGet(
      'https://api.bilibili.com/pgc/view/web/season',
      (s) => s.reply(200, {
        'code': 0,
        'result': {
          'season_id': 7,
          'type': 5,
          'title': '电视剧',
          'evaluate': '简介',
          'user_status': {'follow': 1},
          'rating': {'score': 9.7, 'count': 8},
          'episodes': [
            {'id': 11, 'aid': 12, 'cid': 13, 'cover': 'one', 'title': '1'},
          ],
        },
      }),
      queryParameters: {'season_id': 7},
    );
    final detail = await getSeasonDetail(7);
    expect(detail.followed, isTrue);
    expect(detail.isDrama, isTrue);
    expect(detail.rating, '9.7');
    expect(detail.episodes.single.aid, 12);
    http.onPost(
      'https://api.bilibili.com/pgc/web/follow/del',
      (s) => s.reply(200, {'code': 0}),
      queryParameters: {'season_id': 7, 'csrf': 'csrf'},
      data: {'season_id': 7, 'csrf': 'csrf'},
    );
    await changeSeasonFollow(7, follow: false);
  });
  test('投币缺少设备凭据时补齐并保存，错误提示包含真实错误码', () async {
    final http = DioAdapter(dio: bilibiliHttpClient);
    http.onGet(
      'https://api.bilibili.com/x/frontend/finger/spi',
      (s) => s.reply(200, {
        'code': 0,
        'data': {'b_3': 'device3', 'b_4': 'device4'},
      }),
    );
    http.onPost(
      'https://api.bilibili.com/x/web-interface/coin/add',
      (s) => s.reply(200, {'code': -403, 'message': '访问权限不足'}),
      data: {'aid': 123, 'multiply': 1, 'select_like': 0, 'csrf': 'csrf'},
    );
    await expectLater(
      insertCoin(avid: 123),
      throwsA(
        isA<BilibiliError>()
            .having((e) => e.code, 'code', -403)
            .having((e) => e.message, 'hint', contains('-403')),
      ),
    );
    expect(
      (await loadCookie()).where((c) => c.name == 'buvid3').single.value,
      'device3',
    );
    expect(
      (await loadCookie()).where((c) => c.name == 'SESSDATA').single.value,
      'fake',
    );
  });
}

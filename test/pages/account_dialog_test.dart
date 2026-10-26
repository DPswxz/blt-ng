import 'dart:io';
import 'package:blt/apis/bilibili/client.dart';
import 'package:blt/storages/auth.dart';
import 'package:blt/widgets/account_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http_mock_adapter/http_mock_adapter.dart';
import '../helpers/page_test_env.dart';

LoginInfo info(int id) => LoginInfo.login(
  mid: id,
  nickname: '用户$id',
  avatar: '',
  level: 6,
  vipType: 2,
  vipStatus: 1,
  vipLabel: '年度大会员',
);
void main() {
  setupPageTestEnv();
  Future<void> prepare() async {
    await saveSignedInAccount(info(1), [Cookie('SESSDATA', 'one')]);
    await saveSignedInAccount(info(2), [
      Cookie('SESSDATA', 'two'),
    ], activate: false);
  }

  Future<void> open(
    WidgetTester t, {
    Size size = const Size(1920, 1080),
  }) async {
    await pumpPage(
      t,
      Builder(
        builder: (context) => Center(
          child: ElevatedButton(
            onPressed: () => showAccountDialog(context),
            child: const Text('打开账号'),
          ),
        ),
      ),
      size: size,
    );
    await t.tap(find.text('打开账号'));
    await t.pumpAndSettle();
  }

  testWidgets('账号面板在720p/1080p/4K显示等级会员和添加入口', (t) async {
    await prepare();
    for (final size in [
      const Size(1280, 720),
      const Size(1920, 1080),
      const Size(3840, 2160),
    ]) {
      await open(t, size: size);
      expect(find.text('添加账号'), findsOneWidget);
      expect(find.textContaining('Lv6 · 年度大会员'), findsNWidgets(2));
      expect(t.takeException(), isNull);
      await t.tap(find.text('关闭'));
      await t.pumpAndSettle();
    }
  });
  testWidgets('切换必须确认，取消保留当前账号，确认后才使用目标Cookie', (t) async {
    await prepare();
    await open(t);
    await t.tap(find.text('切换'));
    await t.pumpAndSettle();
    expect(find.text('切换账号？'), findsOneWidget);
    await t.tap(find.text('取消'));
    await t.pumpAndSettle();
    expect(loginInfoNotifier.value.mid, 1);
    final adapter = DioAdapter(dio: bilibiliHttpClient);
    adapter.onGet(
      'https://api.bilibili.com/x/web-interface/nav',
      (s) => s.reply(200, {
        'code': 0,
        'data': {
          'mid': 2,
          'uname': '用户2',
          'face': '',
          'level_info': {'current_level': 6},
          'vipType': 2,
          'vipStatus': 1,
        },
      }),
    );
    await t.tap(find.text('切换'));
    await t.pumpAndSettle();
    await t.tap(find.text('确认切换'));
    await t.pumpAndSettle();
    expect(loginInfoNotifier.value.mid, 2);
    expect((await loadCookie()).single.value, 'two');
    expect(find.byType(AccountDialog), findsNothing);
  });
  testWidgets('可选择非当前账号退出，取消不删除，确认不影响当前账号', (t) async {
    await prepare();
    await open(t);
    await t.tap(find.text('退出登录').last);
    await t.pumpAndSettle();
    expect(find.textContaining('用户2').last, findsOneWidget);
    await t.tap(find.text('取消'));
    await t.pumpAndSettle();
    expect((await loadSavedAccounts()).length, 2);
    await t.tap(find.text('退出登录').last);
    await t.pumpAndSettle();
    await t.tap(find.text('确认退出'));
    await t.pumpAndSettle();
    expect((await loadSavedAccounts()).single.mid, 1);
    expect(loginInfoNotifier.value.mid, 1);
    expect((await loadCookie()).single.value, 'one');
    await t.tap(find.text('关闭'));
    await t.pumpAndSettle();
  });
}

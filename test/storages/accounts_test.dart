import 'dart:io';
import 'package:blt/storages/auth.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

LoginInfo profile(int id) => LoginInfo.login(
  mid: id,
  nickname: '用户$id',
  avatar: '',
  level: 6,
  vipType: 2,
  vipStatus: 1,
  vipLabel: '年度大会员',
);
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    loginInfoNotifier.value = LoginInfo.notLogin;
  });
  test('旧版Cookie自动迁移，添加账号不替换当前账号，切换独立Cookie和刷新令牌', () async {
    await saveCookie([
      Cookie('DedeUserID', '1'),
      Cookie('SESSDATA', 'one'),
    ], refreshToken: 'rt1');
    await restoreSavedLogin();
    expect(loginInfoNotifier.value.mid, 1);
    await rememberCurrentAccount(profile(1), expectedMid: 1);
    await saveSignedInAccount(
      profile(2),
      [Cookie('SESSDATA', 'two')],
      refreshToken: 'rt2',
      activate: false,
    );
    expect(loginInfoNotifier.value.mid, 1);
    expect((await loadCookie()).last.value, 'one');
    expect((await loadSavedAccounts()).length, 2);
    await switchSavedAccount(2);
    expect(loginInfoNotifier.value.mid, 2);
    expect((await loadCookie()).single.value, 'two');
    expect(await loadRefreshToken(), 'rt2');
    await switchSavedAccount(1);
    expect(await loadRefreshToken(), 'rt1');
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('bilibili_cookie'), isNull);
  });
  test('退出非当前账号不影响当前登录；退出当前账号不会自动登录其他账号', () async {
    await saveSignedInAccount(profile(1), [Cookie('SESSDATA', 'one')]);
    await saveSignedInAccount(profile(2), [
      Cookie('SESSDATA', 'two'),
    ], activate: false);
    await removeSavedAccount(2);
    expect(loginInfoNotifier.value.mid, 1);
    await saveSignedInAccount(profile(2), [
      Cookie('SESSDATA', 'two'),
    ], activate: false);
    await removeSavedAccount(1);
    expect(loginInfoNotifier.value.isLogin, isFalse);
    expect(await loadCookie(), isEmpty);
    expect((await loadSavedAccounts()).single.mid, 2);
    await restoreSavedLogin();
    expect(loginInfoNotifier.value.isLogin, isFalse);
  });
  test('旧账号延迟响应不覆盖已切换账号；失败操作不阻塞后续切换', () async {
    await saveSignedInAccount(profile(1), [Cookie('SESSDATA', 'one')]);
    await saveSignedInAccount(profile(2), [
      Cookie('SESSDATA', 'two'),
    ], activate: false);
    await expectLater(switchSavedAccount(999), throwsStateError);
    await switchSavedAccount(2);
    await rememberCurrentAccount(profile(1), expectedMid: 1);
    expect(loginInfoNotifier.value.mid, 2);
    expect((await loadCookie()).single.value, 'two');
  });
  test('登录过期只标记当前账号失效，保存的其他账号仍可切换', () async {
    await saveSignedInAccount(profile(1), [Cookie('SESSDATA', 'one')]);
    await saveSignedInAccount(profile(2), [
      Cookie('SESSDATA', 'two'),
    ], activate: false);
    await clearCookie();
    expect(loginInfoNotifier.value.isLogin, isFalse);
    final rows = await loadSavedAccounts();
    expect(rows.firstWhere((a) => a.mid == 1).needsLogin, isTrue);
    await switchSavedAccount(2);
    expect((await loadCookie()).single.value, 'two');
  });
}

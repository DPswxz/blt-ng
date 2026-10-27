import 'package:blt/storages/auth.dart';
import 'package:blt/storages/season_history.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('分集记录隔离账号，串行写入并限制为100条', () async {
    SharedPreferences.setMockInitialValues({});
    loginInfoNotifier.value = LoginInfo.notLogin;
    await Future.wait([
      for (var i = 1; i <= 105; i++) SeasonHistory.save(i, i * 10, 0),
    ]);
    expect(await SeasonHistory.episode(1), isNull);
    expect(await SeasonHistory.episode(105), 1050);
    loginInfoNotifier.value = LoginInfo.login(
      mid: 2,
      nickname: '测试',
      avatar: '',
    );
    expect(await SeasonHistory.episode(105), isNull);
    await SeasonHistory.save(105, 2000, 2);
    expect(await SeasonHistory.episode(105), 2000);
    loginInfoNotifier.value = LoginInfo.notLogin;
    expect(await SeasonHistory.episode(105), 1050);
  });
}

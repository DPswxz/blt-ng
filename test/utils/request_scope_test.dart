import 'package:blt/apis/bilibili/client.dart';
import 'package:blt/utils/request_scope.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http_mock_adapter/http_mock_adapter.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));
  test('页面离开实际取消Dio请求，重新请求取消旧令牌', () async {
    final adapter = DioAdapter(dio: bilibiliHttpClient);
    adapter.onGet(
      'https://example.invalid/lifetime',
      (s) => s.reply(200, {
        'code': 0,
        'data': {},
      }, delay: const Duration(seconds: 1)),
    );
    final scope = RequestScope();
    CancelToken? first;
    final future = scope.run(() {
      first = currentRequestToken;
      return bilibiliRequest('GET', 'https://example.invalid/lifetime');
    });
    final done = expectLater(
      future,
      throwsA(
        isA<DioException>().having(
          (e) => e.type,
          'type',
          DioExceptionType.cancel,
        ),
      ),
    );
    await Future<void>.delayed(const Duration(milliseconds: 10));
    scope.dispose();
    await done;
    expect(first!.isCancelled, isTrue);
    final secondScope = RequestScope();
    CancelToken? a, b;
    await secondScope.run(() async {
      a = currentRequestToken;
    });
    await secondScope.run(() async {
      b = currentRequestToken;
    }, replace: true);
    expect(a!.isCancelled, isTrue);
    expect(b!.isCancelled, isFalse);
    secondScope.dispose();
  });
}

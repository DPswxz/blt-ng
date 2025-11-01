import 'package:bilitv/apis/bilibili/error.dart';
import 'package:bilitv/storages/cookie.dart' show loadCookie;
import 'package:dio/dio.dart';

final Dio bilibiliHttpClient = () {
  final client = Dio(
    BaseOptions(
      headers: {
        'Referer': 'https://www.bilibili.com/',
        'User-Agent':
            'Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/141.0.0.0 Safari/537.36 Edg/141.0.0.0',
      },
    ),
  );

  // cookie自动加载
  client.interceptors.add(
    InterceptorsWrapper(
      onRequest: (options, handler) async {
        final cookie = await loadCookie();
        if (cookie.isNotEmpty) {
          options.headers['Cookie'] = cookie;
        }
        return handler.next(options);
      },
    ),
  );

  return client;
}();

Future<dynamic> bilibiliGet<T>(
  String url, {
  Map<String, dynamic>? queryParameters,
  Function(Response<dynamic>)? respHandler,
}) async {
  final response = await bilibiliHttpClient.get(
    url,
    queryParameters: queryParameters,
  );
  if (response.statusCode != 200) {
    throw Exception(
      'http error, code=${response.statusCode}, msg=${response.data}',
    );
  }
  final data = response.data as Map<String, dynamic>;
  if (data['code'] != 0) {
    throw BilibiliError(data['code'], data['message']);
  }
  if (respHandler != null) {
    respHandler(response);
  }
  return data['data'];
}

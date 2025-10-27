import 'dart:io' show Platform;

import 'package:dio/dio.dart';

final bilibiliHttpClient = Dio(
  BaseOptions(
    headers: {
      'Referer': 'https://www.bilibili.com/',
      'User-Agent':
          'Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/141.0.0.0 Safari/537.36 Edg/141.0.0.0',
      'Cookie': getCookie(),
    },
  ),
);

String getCookie() {
  Map<String, String> envVars = Platform.environment;
  return envVars['BILIBILI_COOKIE'] ?? '';
}

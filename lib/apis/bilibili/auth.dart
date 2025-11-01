import 'dart:convert' show utf8;
import 'dart:io' show Cookie;

import 'package:crypto/crypto.dart' as crypto;
import 'package:dio/dio.dart';
import 'dart:collection' show SplayTreeMap;

import 'client.dart';

// 二维码
class QR {
  final String key;
  final String url;
  final Duration expire;

  QR({
    required this.key,
    required this.url,
    this.expire = const Duration(minutes: 3),
  });

  factory QR.fromJson(Map<String, dynamic> json) {
    return QR(key: json['qrcode_key'], url: json['url']);
  }
}

// 创建二维码
Future<QR> createQR() async {
  final data = await bilibiliGet(
    'https://passport.bilibili.com/x/passport-login/web/qrcode/generate',
  );
  return QR.fromJson(data);
}

// 二维码状态
enum QRState {
  waiting, // 等待扫码
  scanned, // 已扫码，等待确认
  confirmed, // 已确认，成功登陆
  expired, // 已过期
  error, // 错误
}

// 二维码状态查询结果
class QRStatus {
  final QRState state;
  final String? refreshToken;
  late List<Cookie> cookies;

  QRStatus({required this.state, this.refreshToken, this.cookies = const []});

  factory QRStatus.fromJson(Map<String, dynamic> json) {
    switch (json['code']) {
      case 0:
        return QRStatus(
          state: QRState.confirmed,
          refreshToken: json['refresh_token'],
        );
      case 86038:
        return QRStatus(state: QRState.expired);
      case 86090:
        return QRStatus(state: QRState.scanned);
      case 86101:
        return QRStatus(state: QRState.waiting);
      default:
        throw Exception(
          'bilibili api error, code=${json['code']}, msg=${json['message']}',
        );
    }
  }
}

// 检查二维码状态
Future<QRStatus> checkQRStatus(String key) async {
  Headers? respHeaders;
  final data = await bilibiliGet(
    'https://passport.bilibili.com/x/passport-login/web/qrcode/poll',
    queryParameters: {'qrcode_key': key},
    respHandler: (response) {
      respHeaders = response.headers;
    },
  );
  var qrStatus = QRStatus.fromJson(data);
  if (qrStatus.state == QRState.confirmed) {
    qrStatus.cookies = respHeaders!['set-cookie']!.map((cookie) {
      return Cookie.fromSetCookieValue(cookie);
    }).toList();
  }
  return qrStatus;
}

// APP 签名
Map<String, dynamic> appSign(
  Map<String, dynamic> params,
  String appKey,
  String appSec,
) {
  params = Map.from(params);
  params['appkey'] = appKey;
  final sortParams = SplayTreeMap<String, dynamic>.from(
    params,
    (key1, key2) => key1.compareTo(key2),
  );
  final query = Uri.encodeFull(
    sortParams.keys
        .map((String key) {
          return '$key=${sortParams[key]}';
        })
        .join('&'),
  );
  final sign = crypto.md5.convert(utf8.encode(query + appSec)).toString();
  params['sign'] = sign;
  return params;
}

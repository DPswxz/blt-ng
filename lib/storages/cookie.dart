import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _cookieKey = 'bilibili_cookie';

// debug: 是否从环境变量中读取cookie
var _loadFromEnv = true;

Future<void> saveCookie(String cookie) async {
  final prefs = await SharedPreferences.getInstance();
  await prefs.setString(_cookieKey, cookie);
}

Future<void> clearCookie() async {
  final prefs = await SharedPreferences.getInstance();
  await prefs.remove(_cookieKey);
  _loadFromEnv = false;
}

Future<String> loadCookie() async {
  Map<String, String> env = _loadFromEnv ? Platform.environment : {};
  final prefs = await SharedPreferences.getInstance();
  final cookie =
      prefs.getString(_cookieKey) ?? env[_cookieKey.toUpperCase()] ?? '';
  return cookie;
}

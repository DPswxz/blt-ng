import 'dart:io' show Platform;

String getCookie() {
  Map<String, String> envVars = Platform.environment;
  return envVars['BILIBILI_COOKIE'] ?? '';
}

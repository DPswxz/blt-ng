import 'auth.dart' show bilibiliHttpClient;

const noLoginError = AuthError(1, '未登录');

class AuthError implements Exception {
  final int code;
  final String message;
  const AuthError(this.code, this.message);
}

class MySelf {
  final String name;
  final String avatar;
  final int level;

  MySelf({required this.name, required this.avatar, required this.level});

  factory MySelf.fromJson(Map<String, dynamic> json) {
    return MySelf(
      name: json['uname'] ?? '',
      avatar: json['face'] ?? '',
      level: json['level_info']['current_level'] ?? 0,
    );
  }
}

Future<MySelf> getMySelfInfo() async {
  final response = await bilibiliHttpClient.get(
    'https://api.bilibili.com/x/web-interface/nav',
  );
  if (response.statusCode != 200) {
    throw Exception(
      'http error, code=${response.statusCode}, msg=${response.data}',
    );
  }
  final data = response.data as Map<String, dynamic>;
  if (data['code'] == -101) {
    throw noLoginError;
  } else if (data['code'] != 0) {
    throw Exception(
      'bilibili api error, code=${data['code']}, msg=${data['message']}',
    );
  }

  return MySelf.fromJson(data['data']);
}

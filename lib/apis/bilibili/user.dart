import 'client.dart';

class MySelf {
  final int mid;
  final String name;
  final String avatar;
  final int level;
  final int money;

  MySelf({
    required this.mid,
    required this.name,
    required this.avatar,
    required this.level,
    required this.money,
  });

  factory MySelf.fromJson(Map<String, dynamic> json) {
    return MySelf(
      mid: json['mid'] ?? 0,
      name: json['uname'] ?? '',
      avatar: json['face'] ?? '',
      level: json['level_info']['current_level'] ?? 0,
      money: json['money'] ?? 0,
    );
  }
}

Future<MySelf> getMySelfInfo() async {
  final data = await bilibiliRequest(
    'GET',
    'https://api.bilibili.com/x/web-interface/nav',
  );
  return MySelf.fromJson(data);
}

import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:blt/models/video.dart';

class RecommendationFilter {
  final String _key;
  final Set<int> videos, uploaders;
  RecommendationFilter._(this._key, this.videos, this.uploaders);
  static Future<RecommendationFilter> load(int? account) async {
    final key = 'recommendation_filter.${account ?? "guest"}';
    final prefs = await SharedPreferences.getInstance();
    Map<String, dynamic> data = {};
    try {
      data = Map<String, dynamic>.from(
        jsonDecode(prefs.getString(key) ?? '{}'),
      );
    } catch (_) {}
    Set<int> ids(Object? value) => value is List
        ? value.whereType<int>().where((id) => id > 0).toSet()
        : <int>{};
    return RecommendationFilter._(
      key,
      ids(data['videos']),
      ids(data['uploaders']),
    );
  }

  bool allows(MediaCardInfo video) =>
      !videos.contains(video.avid) && !uploaders.contains(video.userMid);
  Future<void> hide(MediaCardInfo video, {required bool uploader}) async {
    final nextVideos = {...videos};
    final nextUploaders = {...uploaders};
    if (uploader && video.userMid > 0) {
      nextUploaders.add(video.userMid);
    } else {
      nextVideos.add(video.avid);
    }
    final prefs = await SharedPreferences.getInstance();
    final ok = await prefs.setString(
      _key,
      jsonEncode({
        'videos': nextVideos.toList(),
        'uploaders': nextUploaders.toList(),
      }),
    );
    if (!ok) throw StateError('无法保存推荐偏好');
    videos
      ..clear()
      ..addAll(nextVideos);
    uploaders
      ..clear()
      ..addAll(nextUploaders);
  }
}

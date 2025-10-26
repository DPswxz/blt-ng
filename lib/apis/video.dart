import 'package:dio/dio.dart';

import '../models/video.dart';

final bilibiliHttpClient = Dio(
  BaseOptions(
    headers: {
      'Referer': 'https://www.bilibili.com/',
      'User-Agent':
          'Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/141.0.0.0 Safari/537.36 Edg/141.0.0.0',
    },
  ),
);

// 获取推荐视频
Future<List<VideoCardInfo>> fetchRecommendVideos() async {
  final response = await bilibiliHttpClient.get(
    'https://api.bilibili.com/x/web-interface/wbi/index/top/feed/rcmd',
  );
  if (response.statusCode != 200) {
    throw Exception(
      'http error, code=${response.statusCode}, msg=${response.data}',
    );
  }
  final data = response.data as Map<String, dynamic>;
  if (data['code'] != 0) {
    throw Exception(
      'bilibili api error, code=${data['code']}, msg=${data['message']}',
    );
  }

  final List<VideoCardInfo> videos = [];
  for (final item in data['data']['item']) {
    videos.add(VideoCardInfo.fromJson(item));
  }
  return videos;
}

// 获取视频播放地址
Future<List<VideoPlayInfo>> getVideoPlayURL({
  int? avid,
  String? bvid,
  required int cid,
}) async {
  var url = 'https://api.bilibili.com/x/player/wbi/playurl';
  if (avid != null) {
    url += '?avid=$avid';
  } else {
    url += '?bvid=$bvid';
  }
  url += '&cid=$cid';

  final response = await bilibiliHttpClient.get(url);
  if (response.statusCode != 200) {
    throw Exception(
      'http error, code=${response.statusCode}, msg=${response.data}',
    );
  }
  final data = response.data as Map<String, dynamic>;
  if (data['code'] != 0) {
    throw Exception(
      'bilibili api error, code=${data['code']}, msg=${data['message']}',
    );
  }

  final List<VideoPlayInfo> videos = [];
  for (final item in data['data']['durl']) {
    videos.add(VideoPlayInfo.fromJson(item));
  }
  return videos;
}

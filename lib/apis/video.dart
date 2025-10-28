import 'package:bilitv/apis/auth.dart';

import '../models/video.dart';

// 获取视频播放地址
Future<List<VideoPlayInfo>> getVideoPlayURL({
  int? avid,
  String? bvid,
  required int cid,
}) async {
  Map<String, dynamic> queryParams = {'cid': cid};
  if (avid != null) {
    queryParams['avid'] = avid;
  } else {
    queryParams['bvid'] = bvid;
  }
  final response = await bilibiliHttpClient.get(
    'https://api.bilibili.com/x/player/wbi/playurl',
    queryParameters: queryParams,
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

  final List<VideoPlayInfo> videos = [];
  for (final item in data['data']['durl']) {
    videos.add(VideoPlayInfo.fromJson(item));
  }
  return videos;
}

// 获取视频信息
Future<VideoInfo> getVideoInfo({int? avid, String? bvid}) async {
  Map<String, dynamic> queryParams = {};
  if (avid != null) {
    queryParams['aid'] = avid;
  } else {
    queryParams['bvid'] = bvid;
  }
  final response = await bilibiliHttpClient.get(
    'https://api.bilibili.com/x/web-interface/view',
    queryParameters: queryParams,
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

  return VideoInfo.fromJson(data['data']);
}

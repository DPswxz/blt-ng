import 'package:bilitv/models/video.dart' show VideoPlayInfo, VideoInfo;

import 'client.dart';

// 获取视频播放地址
Future<List<VideoPlayInfo>> getVideoPlayURL({
  int? avid,
  String? bvid,
  required int cid,
  int quality = 32,
}) async {
  Map<String, dynamic> queryParams = {'cid': cid, 'qn': quality};
  if (avid != null) {
    queryParams['avid'] = avid;
  } else {
    queryParams['bvid'] = bvid;
  }
  final data = await bilibiliGet(
    'https://api.bilibili.com/x/player/wbi/playurl',
    queryParameters: queryParams,
  );
  final List<VideoPlayInfo> videos = [];
  for (final item in data['durl']) {
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
  final data = await bilibiliGet(
    'https://api.bilibili.com/x/web-interface/view',
    queryParameters: queryParams,
  );
  return VideoInfo.fromJson(data);
}

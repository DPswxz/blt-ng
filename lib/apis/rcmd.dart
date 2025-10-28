import '../models/video.dart';
import 'auth.dart';

// 获取推荐视频
Future<List<MediaCardInfo>> fetchRecommendVideos({
  int freshType = 4,
  int count = 30,
  int page = 1,
  List<int> removeAvids = const [],
}) async {
  final response = await bilibiliHttpClient.get(
    'https://api.bilibili.com/x/web-interface/wbi/index/top/feed/rcmd',
    queryParameters: {
      'fresh_type': freshType,
      'ps': count,
      'fresh_idx': page,
      'last_show_list': removeAvids.map((v) => 'av_$v').join(','),
    },
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

  final List<MediaCardInfo> videos = [];
  for (final item in data['data']['item']) {
    // 过滤掉非视频媒体
    final media = MediaCardInfo.fromJson(item);
    if (media.type != MediaType.video) {
      continue;
    }
    videos.add(media);
  }
  return videos;
}

// 获取相关视频
Future<List<MediaCardInfo>> fetchRelatedVideos({
  int? avid,
  String? bvid,
}) async {
  Map<String, dynamic> queryParams = {};
  if (avid != null) {
    queryParams['aid'] = avid;
  } else {
    queryParams['bvid'] = bvid;
  }
  final response = await bilibiliHttpClient.get(
    'https://api.bilibili.com/x/web-interface/archive/related',
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

  final List<MediaCardInfo> videos = [];
  for (final item in data['data']) {
    videos.add(MediaCardInfo.fromJson(item));
  }
  return videos;
}

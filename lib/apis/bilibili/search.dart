import 'package:bilitv/apis/bilibili/client.dart';
import 'package:bilitv/models/video.dart';

// 搜索视频
Future<List<MediaCardInfo>> searchVideos(String keyword, {int page = 1}) async {
  final data = await bilibiliRequest(
    'GET',
    'https://api.bilibili.com/x/web-interface/wbi/search/type',
    queries: {'search_type': 'video', 'keyword': keyword, 'page': page},
  );
  return ((data['result'] ?? []) as List<dynamic>)
      .map((item) => MediaCardInfo.fromSearchJson(item))
      .toList();
}

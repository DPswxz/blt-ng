import 'package:blt/storages/auth.dart' show loadCookie;
import 'package:dio/dio.dart' show Headers;
import 'package:blt/apis/bilibili/client.dart';
import 'package:blt/apis/bilibili/error.dart';
import 'package:blt/models/video.dart';
import 'package:blt/utils/json.dart';

class LibraryEntry {
  final int id;
  final String title, cover, subtitle;
  final String badge;
  final MediaCardInfo? video;
  final int? aid, cid;
  const LibraryEntry({
    required this.id,
    required this.title,
    this.cover = '',
    this.subtitle = '',
    this.badge = '',
    this.video,
    this.aid,
    this.cid,
  });
}

class LibraryBatch {
  final List<LibraryEntry> items;
  final bool hasMore;
  const LibraryBatch(this.items, {this.hasMore = false});
}

String seasonAccessBadge(Map<String, dynamic> data) {
  final text = jsonString(
    jsonMap(data['badge_info'])?['text'],
    fallback: jsonString(data['badge']),
  );
  if (text.contains('限免') || text.contains('免费') || text.contains('付费')) {
    return text;
  }
  if (text.contains('会员') || jsonInt(data['season_status']) == 13) {
    return '大会员';
  }
  return text;
}

Future<LibraryBatch> listBangumiCatalog({int page = 1}) async {
  final data =
      jsonMap(
        await bilibiliRequest(
          'GET',
          'https://api.bilibili.com/pgc/season/index/result',
          queries: {
            'season_type': 1,
            'type': 1,
            'page': page,
            'pagesize': 20,
            'order': 3,
            'sort': 0,
          },
        ),
      ) ??
      {};
  return LibraryBatch([
    for (final raw in jsonList(data['list']) ?? [])
      if (jsonInt(jsonMap(raw)?['season_id']) > 0)
        LibraryEntry(
          id: jsonInt(jsonMap(raw)?['season_id']),
          title: jsonString(jsonMap(raw)?['title']),
          cover: jsonString(
            jsonMap(raw)?['horizontal_cover'],
            fallback: jsonString(
              jsonMap(jsonMap(raw)?['first_ep'])?['cover'],
              fallback: jsonString(jsonMap(raw)?['cover']),
            ),
          ),
          subtitle: jsonString(jsonMap(raw)?['index_show']),
          badge: seasonAccessBadge(jsonMap(raw) ?? {}),
        ),
  ], hasMore: jsonBool(data['has_next']));
}

Future<LibraryBatch> listFollowedSeasons(
  int mid, {
  int type = 1,
  int page = 1,
}) async {
  final raw = await bilibiliRequest(
    'GET',
    'https://api.bilibili.com/x/space/bangumi/follow/list',
    queries: {'vmid': mid, 'type': type, 'pn': page, 'ps': 20},
  );
  final data = jsonMap(raw) ?? {};
  final list = <LibraryEntry>[];
  for (final value in jsonList(data['list']) ?? []) {
    final d = jsonMap(value) ?? {};
    final id = jsonInt(d['season_id']);
    if (id <= 0) continue;
    list.add(
      LibraryEntry(
        id: id,
        title: jsonString(d['title']),
        badge: seasonAccessBadge(d),
        cover: jsonString(
          d['horizontal_cover'],
          fallback: jsonString(d['cover']),
        ),
        subtitle: jsonString(
          d['progress'],
          fallback: jsonString(jsonMap(d['new_ep'])?['index_show']),
        ),
      ),
    );
  }
  return LibraryBatch(list, hasMore: page * 20 < jsonInt(data['total']));
}

Future<LibraryBatch> listFavoriteFolders(int mid) async {
  final raw = await bilibiliRequest(
    'GET',
    'https://api.bilibili.com/x/v3/fav/folder/created/list-all',
    queries: {'up_mid': mid, 'type': 2},
  );
  final data = jsonMap(raw) ?? {};
  final items = <LibraryEntry>[];
  for (final v in jsonList(data['list']) ?? []) {
    final d = jsonMap(v) ?? {};
    final id = jsonInt(d['id']);
    if (id <= 0) continue;
    items.add(
      LibraryEntry(
        id: id,
        title: jsonString(d['title']),
        cover: jsonString(d['cover']),
        subtitle:
            '${jsonInt(d['media_count'])} 个视频${jsonInt(d['attr']) & 1 == 1 ? ' · 私密' : ''}',
      ),
    );
  }
  // Folder metadata often omits cover, including the default folder.
  // Read a small first page in parallel and use its first valid video cover.
  final withCovers = await Future.wait(
    items.map((item) async {
      if (item.cover.isNotEmpty) return item;
      try {
        final videos = await listFavoriteVideos(item.id);
        final cover =
            videos.items.where((v) => v.cover.isNotEmpty).firstOrNull?.cover ??
            '';
        return LibraryEntry(
          id: item.id,
          title: item.title,
          cover: cover,
          subtitle: item.subtitle,
        );
      } catch (_) {
        // Inaccessible/empty folders must remain browsable even without a cover.
        return item;
      }
    }),
  );
  return LibraryBatch(withCovers);
}

Future<LibraryBatch> listFavoriteVideos(int folder, {int page = 1}) async {
  final data =
      jsonMap(
        await bilibiliRequest(
          'GET',
          'https://api.bilibili.com/x/v3/fav/resource/list',
          queries: {
            'media_id': folder,
            'pn': page,
            'ps': 20,
            'order': 'mtime',
            'platform': 'web',
          },
        ),
      ) ??
      {};
  final items = <LibraryEntry>[];
  for (final v in jsonList(data['medias']) ?? []) {
    final d = jsonMap(v) ?? {};
    if (jsonInt(d['type'], fallback: 2) != 2 || jsonInt(d['attr']) != 0) {
      continue;
    }
    final owner = jsonMap(d['upper']) ?? {};
    final video = MediaCardInfo.fromToViewJson({
      'aid': d['id'],
      'bvid': d['bvid'] ?? d['bv_id'],
      'cid': d['cid'],
      'title': d['title'],
      'pic': d['cover'],
      'duration': d['duration'],
      'pubdate': d['pubtime'],
      'owner': {
        'mid': owner['mid'],
        'name': owner['name'],
        'face': owner['face'],
      },
      'stat': d['cnt_info'],
    });
    if (video != null) {
      items.add(
        LibraryEntry(
          id: video.avid,
          title: video.title,
          cover: video.cover,
          subtitle: video.userName,
          video: video,
        ),
      );
    }
  }
  return LibraryBatch(items, hasMore: jsonBool(data['has_more']));
}

Future<LibraryBatch> listSeasonEpisodes(int season) async {
  final data =
      jsonMap(
        await bilibiliRequest(
          'GET',
          'https://api.bilibili.com/pgc/view/web/season',
          queries: {'season_id': season},
        ),
      ) ??
      {};
  final items = <LibraryEntry>[];
  final seen = <int>{};
  final extra = (jsonList(data['section']) ?? []).expand(
    (v) => jsonList(jsonMap(v)?['episodes']) ?? [],
  );
  for (final v in [...?jsonList(data['episodes']), ...extra]) {
    final d = jsonMap(v) ?? {};
    final id = jsonInt(d['id'], fallback: jsonInt(d['ep_id']));
    if (id <= 0 || !seen.add(id)) continue;
    items.add(
      LibraryEntry(
        id: id,
        title: '${jsonString(d['title'])} ${jsonString(d['long_title'])}'
            .trim(),
        cover: jsonString(d['cover'], fallback: jsonString(data['cover'])),
        subtitle: jsonString(d['badge']),
        badge: seasonAccessBadge(d),
        aid: jsonInt(d['aid']),
        cid: jsonInt(d['cid']),
      ),
    );
  }
  if (items.isEmpty) throw const BilibiliError(-2, '该剧集暂无可播放分集');
  return LibraryBatch(items);
}

class VideoFavoriteFolder {
  final int id;
  final String title;
  final bool selected;
  const VideoFavoriteFolder(this.id, this.title, this.selected);
}

Future<List<VideoFavoriteFolder>> videoFavoriteFolders(
  int mid,
  int avid,
) async {
  final raw = await bilibiliRequest(
    'GET',
    'https://api.bilibili.com/x/v3/fav/folder/created/list-all',
    queries: {'up_mid': mid, 'type': 2, 'rid': avid},
  );
  return [
    for (final v in jsonList(jsonMap(raw)?['list']) ?? [])
      if (jsonInt(jsonMap(v)?['id']) > 0)
        VideoFavoriteFolder(
          jsonInt(jsonMap(v)?['id']),
          jsonString(jsonMap(v)?['title']),
          jsonInt(jsonMap(v)?['fav_state']) == 1,
        ),
  ];
}

Future<void> changeVideoFavorite(
  int avid,
  int folder, {
  required bool add,
}) async {
  final csrf = (await loadCookie())
      .firstWhere((c) => c.name == 'bili_jct')
      .value;
  await bilibiliRequest(
    'POST',
    'https://api.bilibili.com/x/v3/fav/resource/deal',
    contentType: Headers.formUrlEncodedContentType,
    body: {
      'rid': avid,
      'type': 2,
      'add_media_ids': add ? '$folder' : '',
      'del_media_ids': add ? '' : '$folder',
      'csrf': csrf,
    },
  );
}

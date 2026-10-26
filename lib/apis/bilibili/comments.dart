import 'package:blt/apis/bilibili/client.dart';
import 'package:blt/apis/bilibili/error.dart';
import 'package:blt/storages/auth.dart';
import 'package:blt/utils/json.dart';
import 'package:dio/dio.dart';

class VideoComment {
  final int id;
  final String author;
  final String message;
  final int replyCount;
  final int created;
  int likes;
  int action; // 0 neutral, 1 liked, 2 disliked
  VideoComment({
    required this.id,
    required this.author,
    required this.message,
    this.replyCount = 0,
    this.created = 0,
    this.likes = 0,
    this.action = 0,
  });
  factory VideoComment.fromJson(Map<String, dynamic> json) {
    final member = jsonMap(json['member']) ?? {};
    return VideoComment(
      id: jsonInt(json['rpid'], fallback: jsonInt(json['rpid_str'])),
      author: jsonString(member['uname'], fallback: '用户'),
      message: jsonString(jsonMap(json['content'])?['message']),
      replyCount: jsonInt(json['rcount']),
      created: jsonInt(json['ctime']),
      likes: jsonInt(json['like']),
      action: jsonInt(json['action']),
    );
  }
}

class CommentPage {
  final List<VideoComment> comments;
  final int total;
  const CommentPage(this.comments, this.total);
  factory CommentPage.fromJson(Map<String, dynamic> json) => CommentPage(
    (jsonList(json['replies']) ?? [])
        .map(jsonMap)
        .whereType<Map<String, dynamic>>()
        .map(VideoComment.fromJson)
        .where((c) => c.id > 0)
        .toList(),
    jsonInt(jsonMap(json['page'])?['count']),
  );
}

Future<CommentPage> getComments(
  int avid, {
  int page = 1,
  int sort = 1,
  int? root,
}) async {
  final data = await bilibiliRequest(
    'GET',
    root == null
        ? 'https://api.bilibili.com/x/v2/reply'
        : 'https://api.bilibili.com/x/v2/reply/reply',
    queries: {
      'type': 1,
      'oid': avid,
      'pn': page,
      'ps': 20,
      if (root != null) 'root': root,
      if (root == null) 'sort': sort,
    },
  );
  return CommentPage.fromJson(jsonMap(data) ?? {});
}

Future<void> voteComment(
  int avid,
  VideoComment comment, {
  required bool dislike,
}) async {
  if (!loginInfoNotifier.value.isLogin) {
    throw const BilibiliError(-101, '请先扫码登录');
  }
  final cookies = await loadCookie();
  final csrf = cookies.where((c) => c.name == 'bili_jct').firstOrNull?.value;
  if (csrf == null || csrf.isEmpty) {
    throw const BilibiliError(-111, '登录已失效，请重新登录');
  }
  final target = dislike ? 2 : 1;
  final cancel = comment.action == target;
  await bilibiliRequest(
    'POST',
    dislike
        ? 'https://api.bilibili.com/x/v2/reply/hate'
        : 'https://api.bilibili.com/x/v2/reply/action',
    contentType: Headers.formUrlEncodedContentType,
    body: {
      'type': 1,
      'oid': avid,
      'rpid': comment.id,
      'action': cancel ? 0 : 1,
      'csrf': csrf,
    },
  );
  final previous = comment.action;
  comment.action = cancel ? 0 : target;
  comment.likes =
      (comment.likes + (comment.action == 1 ? 1 : 0) - (previous == 1 ? 1 : 0))
          .clamp(0, 1 << 62);
}

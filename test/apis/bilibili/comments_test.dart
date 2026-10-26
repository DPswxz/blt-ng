import 'dart:io';
import 'package:blt/apis/bilibili/client.dart';
import 'package:blt/apis/bilibili/comments.dart';
import 'package:blt/apis/bilibili/error.dart';
import 'package:blt/storages/auth.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http_mock_adapter/http_mock_adapter.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    loginInfoNotifier.value = LoginInfo.notLogin;
  });
  test('缺失评论列表与字符串数字可解析', () {
    expect(CommentPage.fromJson({'replies': null}).comments, isEmpty);
    final c = VideoComment.fromJson({
      'rpid_str': '123',
      'like': '9',
      'action': 2,
      'member': {'uname': '用户'},
      'content': {'message': '正文'},
    });
    expect(c.id, 123);
    expect(c.likes, 9);
    expect(c.action, 2);
  });
  test('未登录禁止投票，不发送请求', () async {
    final c = VideoComment(id: 1, author: 'a', message: 'm');
    await expectLater(
      voteComment(1, c, dislike: false),
      throwsA(isA<BilibiliError>()),
    );
    expect(c.action, 0);
  });
  test('点赞、取消、点踩互斥且失败不改变状态', () async {
    loginInfoNotifier.value = LoginInfo.login(
      mid: 1,
      nickname: '测试',
      avatar: '',
    );
    await saveCookie([Cookie('bili_jct', 'test-csrf')]);
    final adapter = DioAdapter(dio: bilibiliHttpClient);
    const like = 'https://api.bilibili.com/x/v2/reply/action';
    const hate = 'https://api.bilibili.com/x/v2/reply/hate';
    adapter.onPost(like, (s) => s.reply(200, {'code': 0}), data: Matchers.any);
    adapter.onPost(hate, (s) => s.reply(200, {'code': 0}), data: Matchers.any);
    final c = VideoComment(id: 2, author: 'a', message: 'm', likes: 5);
    await voteComment(1, c, dislike: false);
    expect(c.action, 1);
    expect(c.likes, 6);
    await voteComment(1, c, dislike: false);
    expect(c.action, 0);
    expect(c.likes, 5);
    await voteComment(1, c, dislike: false);
    await voteComment(1, c, dislike: true);
    expect(c.action, 2);
    expect(c.likes, 5);
    adapter.onPost(
      like,
      (s) => s.reply(200, {'code': -509, 'message': '请求过于频繁'}),
      data: Matchers.any,
    );
    await expectLater(
      voteComment(1, c, dislike: false),
      throwsA(isA<BilibiliError>()),
    );
    expect(c.action, 2);
    expect(c.likes, 5);
  });
}

import 'package:blt/apis/bilibili/comments.dart';
import 'package:blt/widgets/video_comments.dart';
import 'package:blt/widgets/pink_style.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import '../helpers/page_test_env.dart';

void main() {
  setupPageTestEnv();
  Future<CommentPage> loader(int page, int sort, int? root) async =>
      CommentPage([
        VideoComment(
          id: root == null ? 1 : 2,
          author: root == null ? '一级用户' : '回复用户',
          message: root == null ? '这是第一条评论' : '回复 @一级用户：二级评论',
          replyCount: root == null ? 1 : 0,
          likes: 3,
        ),
      ], 1);
  testWidgets('评论区在720p/1080p/4K及窄面板不溢出', (tester) async {
    for (final size in [
      const Size(1280, 720),
      const Size(1920, 1080),
      const Size(3840, 2160),
    ]) {
      await pumpPage(
        tester,
        SizedBox(
          height: 210 * (size.height / 1080),
          child: VideoCommentsPanel(
            key: ValueKey(size),
            avid: 1,
            loader: loader,
          ),
        ),
        size: size,
      );
      await flush(tester);
      expect(find.text('这是第一条评论'), findsOneWidget);
      expect(tester.takeException(), isNull);
    }
  });
  testWidgets('回复打开二级评论，关闭后保留一级评论', (tester) async {
    await pumpPage(
      tester,
      SizedBox(height: 230, child: VideoCommentsPanel(avid: 1, loader: loader)),
    );
    await flush(tester);
    await tester.tap(find.text('全文 · 1 回复'));
    await tester.pumpAndSettle();
    expect(find.text('回复 @一级用户：二级评论'), findsOneWidget);
    await tester.tap(find.text('关闭'));
    await tester.pumpAndSettle();
    expect(find.text('回复 @一级用户：二级评论'), findsNothing);
    expect(find.text('这是第一条评论'), findsOneWidget);
  });
  testWidgets('评论加载失败可重试', (tester) async {
    int tries = 0;
    await pumpPage(
      tester,
      SizedBox(
        height: 230,
        child: VideoCommentsPanel(
          avid: 1,
          loader: (p, s, r) async {
            if (tries++ == 0) throw Exception('offline');
            return loader(p, s, r);
          },
        ),
      ),
    );
    await flush(tester);
    await tester.tap(find.text('评论加载失败 · 重试'));
    await flush(tester);
    expect(find.text('这是第一条评论'), findsOneWidget);
  });
  testWidgets('长评论全文不截断，二级回复缩进且字号小于主评论', (tester) async {
    final long = List.filled(20, '这是一条多行长评论，完整正文应该可查看。').join('\n');
    await pumpPage(tester, SizedBox(height: 230, child: VideoCommentsPanel(
      avid: 1, loader: (p,s,root) async => CommentPage([
        VideoComment(id: root == null ? 1 : 2, author: root == null ? '主评论' : '二级回复',
          message: root == null ? long : '这是一条回复', replyCount: 1, likes: 0),
      ], 1),
    )));
    await flush(tester);
    await tester.tap(find.text('全文 · 1 回复'));
    await tester.pumpAndSettle();
    final full = tester.widgetList<Text>(find.text(long)).last;
    expect(full.maxLines, isNull);
    expect(full.overflow, isNull);
    await tester.scrollUntilVisible(find.text('这是一条回复'), 400,
      scrollable: find.byType(Scrollable).last);
    final reply = tester.widget<Text>(find.text('这是一条回复'));
    expect(reply.style!.fontSize, lessThan(full.style!.fontSize!));
    expect(tester.getTopLeft(find.text('这是一条回复')).dx,
      greaterThan(tester.getTopLeft(find.text(long).last).dx));
    expect(tester.takeException(), isNull);
  });

  testWidgets('预览固定一行用户名两行正文，左侧按钮文字居中', (tester) async {
    const text='这是一条需要换行的评论正文，用足够多文字验证两行内容不会被底部按钮截断。第二行内容也应完整显示。';
    for(final size in [const Size(1280,720),const Size(1920,1080),const Size(3840,2160)]) {
      final ui=size.height/1080;
      await pumpPage(tester,SizedBox(height:200*ui,child:VideoCommentsPanel(key:ValueKey(size),avid:1,
        loader:(p,s,r)async=>CommentPage([VideoComment(id:1,author:'评论用户名',message:text,replyCount:1,likes:3)],1))),size:size);
      await flush(tester);
      final content=tester.widget<Text>(find.text(text));
      expect(content.maxLines,2);
      expect(tester.getSize(find.text(text)).height,greaterThanOrEqualTo(50*ui-0.1));
      expect(tester.widget<Text>(find.text('评论用户名')).maxLines,1);
      final button=find.widgetWithText(PinkButton,'热门');
      final box=tester.getRect(button), label=tester.getRect(find.text('热门'));
      expect(label.center.dx,closeTo(box.center.dx,0.5));
      expect(label.center.dy,closeTo(box.center.dy,0.5));
      expect(tester.takeException(),isNull);
    }
  });

}

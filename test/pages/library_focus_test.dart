import 'dart:async';
import 'package:blt/apis/bilibili/library.dart';
import 'package:blt/pages/my_library.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import '../helpers/page_test_env.dart';

bool focused(WidgetTester tester, String label) =>
    Focus.of(tester.element(find.text(label))).hasFocus;

void main() {
  setupPageTestEnv();
  testWidgets('收藏夹保留标题，隐藏返回刷新和提示，遥控返回直接退出', (t) async {
    var backs = 0;
    await pumpPage(
      t,
      LibraryCollectionPane(
        title: '测试收藏夹',
        folderView: true,
        loader: (_) async =>
            const LibraryBatch([LibraryEntry(id: 1, title: '收藏视频')]),
        onOpen: (_) {},
        onRemove: (_) async {},
        onBack: () => backs++,
      ),
    );
    await flush(t);
    expect(find.text('测试收藏夹'), findsOneWidget);
    expect(find.text('返回'), findsNothing);
    expect(find.text('刷新'), findsNothing);
    expect(find.text('菜单键 / 长按移除'), findsNothing);
    await t.sendKeyEvent(LogicalKeyboardKey.contextMenu);
    await flush(t);
    expect(find.text('移出此收藏夹？'), findsOneWidget);
    await t.tap(find.text('取消'));
    await t.pumpAndSettle();
    await t.binding.handlePopRoute();
    await t.pump();
    expect(backs, 1);
  });
  test('番剧播放列表保留每集独立aid、cid、epid，过滤不可播放项', () {
    final entries = libraryPlaybackEpisodes(const [
      LibraryEntry(id: 11, title: '第一集', aid: 101, cid: 201),
      LibraryEntry(id: 12, title: '第二集', aid: 102, cid: 202),
      LibraryEntry(id: 13, title: '未开播'),
    ]);
    expect(entries.map((e) => e.aid), [101, 102]);
    expect(entries.map((e) => e.cid), [201, 202]);
    expect(entries.map((e) => e.episodeId), [11, 12]);
  });
  testWidgets('取消订阅后移除入口并聚焦相邻项', (t) async {
    final controller = LibraryCollectionController();
    await pumpPage(
      t,
      LibraryCollectionPane(
        title: '订阅',
        controller: controller,
        loader: (_) async => const LibraryBatch([
          LibraryEntry(id: 1, title: '已取消'),
          LibraryEntry(id: 2, title: '下一项'),
        ]),
        onOpen: (entry) async => controller.remove(entry.id),
      ),
    );
    await flush(t);
    await t.tap(find.text('已取消'));
    await flush(t);
    expect(find.text('已取消'), findsNothing);
    expect(focused(t, '下一项'), isTrue);
    expect(t.takeException(), isNull);
  });
  testWidgets('进入子页面返回保留滚动位置并聚焦点击的入口', (t) async {
    await pumpPage(
      t,
      LibraryCollectionPane(
        title: '父列表',
        loader: (_) async => LibraryBatch(
          List.generate(32, (i) => LibraryEntry(id: i + 1, title: '入口$i')),
        ),
        onOpen: (_) async {
          final ctx = t.element(find.text('父列表'));
          await Navigator.of(ctx).push(
            MaterialPageRoute<void>(
              builder: (ctx) => Scaffold(
                body: TextButton(
                  onPressed: () => Navigator.of(ctx).pop(),
                  child: const Text('返回父列表'),
                ),
              ),
            ),
          );
        },
      ),
    );
    await flush(t);
    await t.scrollUntilVisible(
      find.text('入口16'),
      400,
      scrollable: find.byType(Scrollable).first,
    );
    final scroll = t.widget<GridView>(find.byType(GridView)).controller!;
    await Scrollable.ensureVisible(
      t.element(find.text('入口16')),
      alignment: 0.5,
    );
    await t.pump(const Duration(milliseconds: 500));
    final offset = scroll.offset;
    await t.tap(find.text('入口16'));
    await flush(t);
    await t.tap(find.text('返回父列表'));
    await flush(t);
    expect(scroll.offset, closeTo(offset, 1));
    expect(focused(t, '入口16'), isTrue);
    expect(t.takeException(), isNull);
  });
  testWidgets('列表异步加载后聚焦首项，返回键聚焦返回按钮，确认才返回', (t) async {
    final loaded = Completer<LibraryBatch>();
    var backs = 0;
    await pumpPage(
      t,
      LibraryCollectionPane(
        title: '具体收藏夹',
        loader: (_) => loaded.future,
        onOpen: (_) {},
        onBack: () => backs++,
      ),
    );
    loaded.complete(
      const LibraryBatch([
        LibraryEntry(id: 1, title: '第一项'),
        LibraryEntry(id: 2, title: '第二项'),
      ]),
    );
    await flush(t);
    expect(focused(t, '第一项'), isTrue);
    await t.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await t.pump();
    expect(focused(t, '第二项'), isTrue);
    await t.binding.handlePopRoute();
    await t.pump();
    expect(focused(t, '返回'), isTrue);
    expect(backs, 0);
    await t.binding.handlePopRoute();
    await t.pump();
    expect(backs, 0);
    await t.sendKeyEvent(LogicalKeyboardKey.enter);
    await t.pump();
    expect(backs, 1);
  });

  testWidgets('空番剧列表返回聚焦返回按钮，隐藏列表加载不抢焦点', (t) async {
    await pumpPage(
      t,
      LibraryCollectionPane(
        title: '番剧分集',
        loader: (_) async => const LibraryBatch([]),
        onOpen: (_) {},
        onBack: () {},
      ),
    );
    await flush(t);
    expect(focused(t, '返回'), isTrue);
    final loaded = Completer<LibraryBatch>();
    await pumpPage(
      t,
      Column(
        children: [
          const TextButton(onPressed: null, child: Text('当前页')),
          Expanded(
            child: TickerMode(
              enabled: false,
              child: LibraryCollectionPane(
                key: const ValueKey('hidden'),
                title: '后台列表',
                loader: (_) => loaded.future,
                onOpen: (_) {},
              ),
            ),
          ),
        ],
      ),
    );
    loaded.complete(const LibraryBatch([LibraryEntry(id: 1, title: '后台首项')]));
    await flush(t);
    expect(focused(t, '后台首项'), isFalse);
  });
}

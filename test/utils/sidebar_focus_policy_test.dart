import 'package:blt/utils/sidebar_focus_policy.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import '../helpers/page_test_env.dart';

void main() {
  setupPageTestEnv();
  testWidgets('只重定向内容向左跨入侧栏，忽略高度且保留内容内部左右导航', (t) async {
    for (final size in const [
      Size(1280, 720),
      Size(1920, 1080),
      Size(3840, 2160),
      Size(1600, 1200),
      Size(2560, 1080),
    ]) {
      final sidebar = FocusNode(canRequestFocus: false),
          content = FocusNode(canRequestFocus: false);
      final home = FocusNode(),
          settings = FocusNode(),
          first = FocusNode(),
          second = FocusNode(),
          bottom = FocusNode();
      var active = settings;
      final ui = size.height / 1080;
      Widget box(FocusNode node, String text) => Focus(
        focusNode: node,
        child: SizedBox(width: 100 * ui, height: 70 * ui, child: Text(text)),
      );
      await pumpPage(
        t,
        FocusTraversalGroup(
          policy: SidebarFocusPolicy(
            sidebar: sidebar,
            content: content,
            activeTarget: () => active,
          ),
          child: Row(
            children: [
              Focus(
                focusNode: sidebar,
                canRequestFocus: false,
                child: SizedBox(
                  width: 180 * ui,
                  child: Stack(
                    children: [
                      Positioned(
                        left: 20 * ui,
                        top: 100 * ui,
                        child: box(home, '首页'),
                      ),
                      Positioned(
                        left: 20 * ui,
                        top: 700 * ui,
                        child: box(settings, '设置'),
                      ),
                    ],
                  ),
                ),
              ),
              Expanded(
                child: Focus(
                  focusNode: content,
                  canRequestFocus: false,
                  child: Stack(
                    children: [
                      Positioned(
                        left: 100 * ui,
                        top: 100 * ui,
                        child: box(first, '第一列'),
                      ),
                      Positioned(
                        left: 400 * ui,
                        top: 100 * ui,
                        child: box(second, '第二列'),
                      ),
                      Positioned(
                        left: 100 * ui,
                        top: 700 * ui,
                        child: box(bottom, '下方第一列'),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
        size: size,
      );
      first.requestFocus();
      await t.pump();
      await t.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
      await t.pump();
      expect(settings.hasFocus, isTrue, reason: '上方内容也应回当前设置页 $size');
      second.requestFocus();
      await t.pump();
      await t.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
      await t.pump();
      expect(first.hasFocus, isTrue, reason: '内部列导航不能被截走');
      active = home;
      bottom.requestFocus();
      await t.pump();
      await t.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
      await t.pump();
      expect(home.hasFocus, isTrue, reason: '下方内容也应回当前首页 $size');
      expect(t.takeException(), isNull);
      await t.pumpWidget(const SizedBox());
      for (final n in [
        sidebar,
        content,
        home,
        settings,
        first,
        second,
        bottom,
      ]) {
        n.dispose();
      }
    }
  });
}

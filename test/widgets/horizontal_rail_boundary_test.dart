import 'package:blt/widgets/horizontal_rail_boundary.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import '../helpers/page_test_env.dart';

void main() {
  setupPageTestEnv();
  testWidgets('横排向右只到同一行，末项继续向右不跳到下方', (t) async {
    final first = FocusNode(), last = FocusNode(), outside = FocusNode();
    await pumpPage(
      t,
      Column(
        children: [
          HorizontalRailBoundary(
            child: Row(
              children: [
                SizedBox(
                  width: 200,
                  child: TextButton(
                    focusNode: first,
                    onPressed: () {},
                    child: const Text('第一项'),
                  ),
                ),
                SizedBox(
                  width: 200,
                  child: TextButton(
                    focusNode: last,
                    onPressed: () {},
                    child: const Text('末项'),
                  ),
                ),
              ],
            ),
          ),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton(
              focusNode: outside,
              onPressed: () {},
              child: const Text('其它行'),
            ),
          ),
        ],
      ),
    );
    first.requestFocus();
    await t.pump();
    await t.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await t.pump();
    expect(last.hasFocus, isTrue);
    for (var i = 0; i < 3; i++) {
      await t.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await t.pump();
    }
    expect(last.hasFocus, isTrue);
    expect(outside.hasFocus, isFalse);
    await t.pumpWidget(const SizedBox());
    first.dispose();
    last.dispose();
    outside.dispose();
  });
}

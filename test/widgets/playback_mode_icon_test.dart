import 'package:blt/consts/settings.dart';
import 'package:blt/widgets/player_controls.dart';
import 'package:blt/widgets/playback_mode_icon.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import '../helpers/page_test_env.dart';

void main() {
  setupPageTestEnv();
  for (final size in const [
    Size(1280, 720),
    Size(1920, 1080),
    Size(3840, 2160),
  ]) {
    testWidgets('播放完后三种模式显示不同图标并正确返回选择 $size', (tester) async {
      PlayerLoopMode mode = PlayerLoopMode.none;
      await pumpPage(
        tester,
        StatefulBuilder(
          builder: (context, setState) => TextButton.icon(
            icon: Icon(playbackModeIcon(mode)),
            label: const Text('播放完后'),
            onPressed: () async {
              final selected = await showPlayerPicker<PlayerLoopMode>(
                context: context,
                title: '选择行为',
                options: PlayerLoopMode.values,
                current: mode,
                labelOf: (value) => value.description,
                iconOf: playbackModeIcon,
              );
              if (selected != null) setState(() => mode = selected);
            },
          ),
        ),
        size: size,
      );
      for (final next in PlayerLoopMode.values) {
        await tester.tap(find.text('播放完后'));
        await tester.pumpAndSettle();
        for (final item in PlayerLoopMode.values) {
          final row = find
              .ancestor(
                of: find.text(item.description),
                matching: find.byType(Row),
              )
              .first;
          expect(
            find.descendant(
              of: row,
              matching: find.byIcon(playbackModeIcon(item)),
            ),
            findsOneWidget,
          );
        }
        await tester.tap(find.text(next.description));
        await tester.pumpAndSettle();
        expect(mode, next);
        expect(find.byIcon(playbackModeIcon(next)), findsOneWidget);
        expect(tester.takeException(), isNull);
      }
    });
  }
}

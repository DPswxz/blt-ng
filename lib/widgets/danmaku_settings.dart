import 'package:blt/storages/settings.dart';
import 'package:blt/widgets/bilibili_danmaku_wall.dart';
import 'package:blt/widgets/player_controls.dart';
import 'package:blt/widgets/tooltip.dart';
import 'package:flutter/material.dart';

Future<void> showDanmakuSettings(
  BuildContext context,
  BilibiliDanmakuWallController controller, {
  required VoidCallback onToggle,
}) async {
  final area = await Settings.getInt(Settings.pathDanmuArea) ?? 10;
  final transparency =
      await Settings.getInt(Settings.pathDanmuTransparency) ?? 0;
  if (!context.mounted) return;
  final action = await showPlayerPicker<int>(
    context: context,
    title: '弹幕设置',
    options: const [0, 1, 2, 3, 4],
    current: 0,
    labelOf: (v) => switch (v) {
      0 => '弹幕：${controller.enabled ? "开" : "关"} · 点击切换',
      1 => '弹幕字体大小',
      2 => '弹幕屏蔽权重',
      3 => '显示区域：${danmakuAreaLabels[area] ?? "顶部 10%"}',
      _ => '透明度：${danmakuTransparencyLabel(transparency.clamp(0, 90))}',
    },
  );
  if (!context.mounted || action == null) return;
  if (action == 0) {
    onToggle();
    return;
  }
  final key = switch (action) {
    1 => Settings.pathDanmuFontSize,
    2 => Settings.pathDanmuBlockWeightSwitch,
    3 => Settings.pathDanmuArea,
    _ => Settings.pathDanmuTransparency,
  };
  final value =
      await Settings.getInt(key) ??
      switch (action) {
        1 => 20,
        2 => 6,
        3 => 10,
        _ => 0,
      };
  if (!context.mounted) return;
  final title = switch (action) {
    1 => '弹幕字体大小',
    2 => '屏蔽权重 · 越大弹幕越少',
    3 => '弹幕显示区域',
    _ => '弹幕透明度 · 越高越透明',
  };
  final selected = await showPlayerPicker<int>(
    context: context,
    title: title,
    options: switch (action) {
      1 => const [16, 18, 20, 22, 25, 28, 30, 36],
      2 => List.generate(11, (i) => i),
      3 => danmakuAreaLabels.keys.toList(),
      _ => const [0, 20, 40, 60, 80, 90],
    },
    current: value,
    labelOf: (v) => action == 3
        ? danmakuAreaLabels[v]!
        : action == 4
        ? danmakuTransparencyLabel(v)
        : '$v',
  );
  if (!context.mounted || selected == null) return;
  await Settings.setInt(key, selected);
  await controller.reloadSettings();
  if (context.mounted) {
    pushTooltipInfo(
      context,
      action == 3
          ? '弹幕区域：${danmakuAreaLabels[selected]}'
          : action == 4
          ? '弹幕透明度：${danmakuTransparencyLabel(selected)}'
          : '弹幕设置已保存',
    );
  }
}

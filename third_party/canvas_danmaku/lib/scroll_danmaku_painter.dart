import 'package:flutter/material.dart';
import 'models/danmaku_item.dart';
import 'utils/utils.dart';

/// Repaint from vsync without rebuilding widgets. Position is calculated from
/// elapsed time, so skipped frames and repeated paints cannot accumulate drift.
class ScrollDanmakuPainter extends CustomPainter {
  final List<DanmakuItem> items;
  final int durationSeconds;
  final double fontSize;
  final int fontWeight;
  final bool showStroke;
  final double opacity;
  final int Function() tick;

  ScrollDanmakuPainter({
    required this.items,
    required this.durationSeconds,
    required this.fontSize,
    required this.fontWeight,
    required this.showStroke,
    required this.tick,
    this.opacity = 1,
    required Listenable repaint,
  }) : super(repaint: repaint);

  final Paint selfSendPaint = Paint()
    ..style = PaintingStyle.stroke
    ..strokeWidth = 1.5
    ..color = Colors.green;

  @override
  void paint(Canvas canvas, Size size) {
    selfSendPaint.color = Colors.green.withValues(alpha: opacity);
    final now = tick();
    for (final item in items) {
      final elapsed = (now - item.creationTime).clamp(
        0,
        durationSeconds * 1000,
      );
      item.xPosition = size.width -
          elapsed / (durationSeconds * 1000) * (size.width + item.width);
      if (item.xPosition <= -item.width) continue;
      item.paragraph ??= Utils.generateParagraph(
        item.content,
        item.width,
        fontSize,
        fontWeight,
        opacity: opacity,
      );
      if (showStroke) {
        item.strokeParagraph ??= Utils.generateStrokeParagraph(
          item.content,
          item.width,
          fontSize,
          fontWeight,
          opacity: opacity,
        );
        canvas.drawParagraph(
          item.strokeParagraph!,
          Offset(item.xPosition, item.yPosition),
        );
      }
      if (item.content.selfSend) {
        canvas.drawRect(
          Offset(item.xPosition - 2, item.yPosition + 2) &
              Size(item.width + 4, item.height),
          selfSendPaint,
        );
      }
      canvas.drawParagraph(
        item.paragraph!,
        Offset(item.xPosition, item.yPosition),
      );
    }
  }

  @override
  bool shouldRepaint(covariant ScrollDanmakuPainter old) => true;
}

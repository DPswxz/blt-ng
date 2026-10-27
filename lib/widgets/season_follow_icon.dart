import 'package:blt/consts/color.dart';
import 'package:flutter/material.dart';

/// Heart-plus / checked-heart matching the subscription states.
class SeasonFollowIcon extends StatelessWidget {
  final bool followed;
  final double ui;
  const SeasonFollowIcon({super.key, required this.followed, required this.ui});
  @override
  Widget build(BuildContext context) => SizedBox(
    width: 30 * ui,
    height: 30 * ui,
    child: CustomPaint(painter: _HeartPainter(followed)),
  );
}

class _HeartPainter extends CustomPainter {
  final bool followed;
  const _HeartPainter(this.followed);
  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.scale(size.width / 32, size.height / 32);
    final heart = Path()
      ..moveTo(16, 28)
      ..cubicTo(12, 25, 3, 19, 3, 12)
      ..cubicTo(3, 4, 12, 2, 16, 9)
      ..cubicTo(20, 2, 29, 4, 29, 12)
      ..cubicTo(29, 19, 20, 25, 16, 28)
      ..close();
    final paint = Paint()
      ..color = biliPink
      ..strokeWidth = 2
      ..strokeJoin = StrokeJoin.round
      ..strokeCap = StrokeCap.round;
    if (followed) {
      canvas.drawPath(heart, paint);
      canvas.drawPath(
        Path()
          ..moveTo(10, 15)
          ..lineTo(14, 19)
          ..lineTo(22, 11),
        Paint()
          ..color = Colors.white
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.4
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round,
      );
    } else {
      paint.style = PaintingStyle.stroke;
      // Leave room for the small plus at the upper right of the outline.
      canvas.save();
      canvas.clipPath(
        Path.combine(
          PathOperation.difference,
          Path()..addRect(const Rect.fromLTWH(0, 0, 32, 32)),
          Path()..addRect(const Rect.fromLTWH(22, 3, 10, 15)),
        ),
      );
      canvas.drawPath(heart, paint);
      canvas.restore();
      canvas.drawLine(const Offset(27, 6), const Offset(27, 14), paint);
      canvas.drawLine(const Offset(23, 10), const Offset(31, 10), paint);
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(_HeartPainter oldDelegate) =>
      oldDelegate.followed != followed;
}

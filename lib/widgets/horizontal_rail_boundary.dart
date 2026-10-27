import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:blt/utils/ui_scale.dart';

/// Right stays in the current horizontal band, including at its final item.
/// Up/down and left remain available to leave the rail normally.
class HorizontalRailBoundary extends StatelessWidget {
  final Widget child;
  const HorizontalRailBoundary({super.key, required this.child});
  @override
  Widget build(BuildContext context) => Focus(
    canRequestFocus: false,
    onKeyEvent: (rail, event) {
      if (event.logicalKey != LogicalKeyboardKey.arrowRight) {
        return KeyEventResult.ignored;
      }
      if (event is KeyDownEvent || event is KeyRepeatEvent) {
        final current = FocusManager.instance.primaryFocus;
        if (current != null && current.context != null) {
          final from = current.rect;
          final candidates =
              rail.traversalDescendants.where((node) {
                  if (node == current ||
                      !node.canRequestFocus ||
                      node.skipTraversal ||
                      node.context == null) {
                    return false;
                  }
                  final to = node.rect;
                  final tolerance =
                      (from.height < to.height ? from.height : to.height) / 2 +
                      2 * context.ui;
                  return to.center.dx > from.center.dx + 1 &&
                      (to.center.dy - from.center.dy).abs() <= tolerance;
                }).toList()
                ..sort((a, b) => a.rect.center.dx.compareTo(b.rect.center.dx));
          if (candidates.isNotEmpty) candidates.first.requestFocus();
        }
      }
      return KeyEventResult.handled;
    },
    child: child,
  );
}

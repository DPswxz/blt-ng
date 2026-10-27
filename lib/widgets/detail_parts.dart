import 'package:flutter/material.dart';
import 'package:dpad/dpad.dart';
import 'package:blt/consts/color.dart';
import 'package:blt/widgets/pink_style.dart';
import 'package:blt/widgets/text.dart';

class DetailAction extends StatelessWidget {
  final double ui;
  final IconData? icon;
  final IconData? iconFont;
  final Widget? leading;
  final double iconScale;
  final String? label;
  final bool active; // 语义上的已选（已点赞/投币/收藏）
  final VoidCallback? onPressed;

  const DetailAction({
    super.key,
    required this.ui,
    this.icon,
    this.iconFont,
    this.leading,
    this.iconScale = 1,
    this.label,
    this.active = false,
    this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    final color = active ? biliPink : Colors.grey.shade600;
    Widget iconWidget = Icon(
      iconFont ?? icon,
      size: 30 * ui * iconScale,
      color: color,
    );

    final content = Padding(
      padding: EdgeInsets.symmetric(horizontal: 12 * ui),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          if (leading != null)
            leading!
          else if (icon != null || iconFont != null)
            iconWidget,
          if (label != null) ...[
            if (leading != null || icon != null || iconFont != null)
              SizedBox(width: 8 * ui),
            Flexible(
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  label!,
                  maxLines: 1,
                  style: TextStyle(
                    fontSize: 22 * ui,
                    fontWeight: FontWeight.w600,
                    color: active ? biliPink : Colors.grey.shade800,
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
    if (onPressed == null) {
      return DecoratedBox(
        decoration: BoxDecoration(
          color: focusableSurfaceColor,
          borderRadius: BorderRadius.circular(16 * ui),
        ),
        child: content,
      );
    }
    return GestureDetector(
      onTap: onPressed,
      child: DpadFocusable(
        onSelect: onPressed,
        builder: pinkFocusEffect(
          ui: ui,
          radius: 16 * ui,
          borderWidth: 2.5 * ui,
          backgroundColor: active
              ? biliPink.withValues(alpha: 0.16)
              : focusableSurfaceColor,
          focusedBackgroundColor: Colors.white,
          scale: 1.05,
        ),
        child: content,
      ),
    );
  }
}

class DetailDescription extends StatelessWidget {
  final double ui;
  final String desc;
  final VoidCallback onOpen;
  final bool fillAvailableHeight;
  const DetailDescription({
    super.key,
    required this.ui,
    required this.desc,
    required this.onOpen,
    this.fillAvailableHeight = false,
  });
  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onOpen,
      child: DpadFocusable(
        onSelect: onOpen,
        builder: pinkFocusEffect(
          ui: ui,
          radius: 16 * ui,
          borderWidth: 2.5 * ui,
          backgroundColor: focusableSurfaceColor,
          focusedBackgroundColor: Colors.white,
          scale: 1.02,
        ),
        child: Padding(
          padding: EdgeInsets.fromLTRB(16 * ui, 6 * ui, 14 * ui, 6 * ui),
          child: Row(
            children: [
              Expanded(
                child: fillAvailableHeight
                    ? LayoutBuilder(
                        builder: (context, constraints) => Align(
                          alignment: Alignment.topLeft,
                          child: Text(
                            desc.isEmpty ? '暂无简介' : desc,
                            maxLines: (constraints.maxHeight / (24 * ui * 1.35))
                                .floor()
                                .clamp(1, 100),
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 24 * ui,
                              height: 1.35,
                              fontWeight: FontWeight.w500,
                              color: Colors.grey.shade700,
                            ),
                          ),
                        ),
                      )
                    : FixedLineAdaptiveText(
                        desc.isEmpty ? '暂无简介' : desc,
                        line: 2,
                        lineHeight: 1.35,
                        maxFontSize: 24 * ui,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontWeight: FontWeight.w500,
                          color: desc.isEmpty
                              ? Colors.grey.shade500
                              : Colors.grey.shade700,
                        ),
                      ),
              ),
              SizedBox(width: 10 * ui),
              Icon(
                Icons.unfold_more_rounded,
                size: 26 * ui,
                color: Colors.grey.shade500,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class DetailUpBadge extends StatelessWidget {
  final double ui;

  const DetailUpBadge({super.key, required this.ui});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 10 * ui, vertical: 4 * ui),
      decoration: BoxDecoration(
        color: biliPink.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(8 * ui),
      ),
      child: Text(
        'UP主',
        style: TextStyle(
          fontSize: 18 * ui,
          fontWeight: FontWeight.w600,
          color: biliPink,
        ),
      ),
    );
  }
}

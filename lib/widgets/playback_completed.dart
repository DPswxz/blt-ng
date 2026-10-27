import 'package:blt/consts/color.dart';
import 'package:blt/utils/ui_scale.dart';
import 'package:blt/widgets/pink_style.dart';
import 'package:flutter/material.dart';

class PlaybackCompletedOverlay extends StatelessWidget {
  final String title;
  final VoidCallback onRestart, onBack;
  final VoidCallback? onNext;
  const PlaybackCompletedOverlay({
    super.key,
    required this.title,
    required this.onRestart,
    required this.onBack,
    this.onNext,
  });

  @override
  Widget build(BuildContext context) {
    final ui = context.ui;
    return Positioned.fill(
      child: ColoredBox(
        color: Colors.black.withValues(alpha: 0.76),
        child: Center(
          child: TweenAnimationBuilder<double>(
            tween: Tween(begin: 0, end: 1),
            duration: const Duration(milliseconds: 450),
            curve: Curves.easeOutCubic,
            builder: (_, progress, child) => Opacity(
              opacity: progress,
              child: Transform.scale(
                scale: 0.94 + 0.06 * progress,
                child: child,
              ),
            ),
            child: Semantics(
              liveRegion: true,
              label: '播放完成',
              child: Container(
                width: 900 * ui,
                padding: EdgeInsets.all(40 * ui),
                decoration: BoxDecoration(
                  gradient: pageBackgroundGradient,
                  borderRadius: BorderRadius.circular(28 * ui),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.check_circle_rounded,
                      color: navigationAccentColor,
                      size: 96 * ui,
                    ),
                    SizedBox(height: 18 * ui),
                    Text(
                      '播放完成',
                      style: TextStyle(
                        fontSize: 42 * ui,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    SizedBox(height: 16 * ui),
                    Text(
                      title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 25 * ui,
                        color: Colors.black54,
                      ),
                    ),
                    SizedBox(height: 32 * ui),
                    Row(
                      children: [
                        Expanded(
                          child: PinkButton(
                            ui: ui,
                            autofocus: true,
                            label: '从头播放',
                            icon: Icons.replay_rounded,
                            onPressed: onRestart,
                          ),
                        ),
                        SizedBox(width: 18 * ui),
                        Expanded(
                          child: PinkButton(
                            ui: ui,
                            label: '返回详情',
                            onPressed: onBack,
                          ),
                        ),
                      ],
                    ),
                    if (onNext != null) ...[
                      SizedBox(height: 18 * ui),
                      PinkButton(
                        ui: ui,
                        label: '下一集',
                        icon: Icons.skip_next_rounded,
                        onPressed: onNext!,
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

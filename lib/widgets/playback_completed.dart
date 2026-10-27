import 'dart:ui' show ImageFilter;
import 'package:blt/utils/ui_scale.dart';
import 'package:blt/widgets/pink_style.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class PlaybackCompletedOverlay extends StatefulWidget {
  final String title;
  final VoidCallback onRestart;
  final VoidCallback? onNext;
  const PlaybackCompletedOverlay({
    super.key,
    required this.title,
    required this.onRestart,
    this.onNext,
  });
  @override
  State<PlaybackCompletedOverlay> createState() =>
      _PlaybackCompletedOverlayState();
}

class _PlaybackCompletedOverlayState extends State<PlaybackCompletedOverlay> {
  final _scope = FocusScopeNode(debugLabel: 'playback-completed');
  final _restart = FocusNode(debugLabel: 'completed-restart');
  final _next = FocusNode(debugLabel: 'completed-next');
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _restart.requestFocus();
    });
  }

  @override
  void dispose() {
    _restart.dispose();
    _next.dispose();
    _scope.dispose();
    super.dispose();
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    final key = event.logicalKey;
    if (key == LogicalKeyboardKey.arrowLeft ||
        key == LogicalKeyboardKey.arrowUp) {
      if (event is KeyDownEvent || event is KeyRepeatEvent) {
        _restart.requestFocus();
      }
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowRight ||
        key == LogicalKeyboardKey.arrowDown) {
      if (event is KeyDownEvent || event is KeyRepeatEvent) {
        (widget.onNext == null ? _restart : _next).requestFocus();
      }
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.enter ||
        key == LogicalKeyboardKey.select ||
        key == LogicalKeyboardKey.space) {
      if (event is KeyDownEvent) {
        if (_next.hasFocus && widget.onNext != null) {
          widget.onNext!();
        } else {
          widget.onRestart();
        }
      }
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    final ui = context.ui;
    return Positioned.fill(
      child: FocusScope(
        node: _scope,
        autofocus: true,
        onKeyEvent: _onKey,
        child: Center(
          child: TweenAnimationBuilder<double>(
            tween: Tween(begin: 0, end: 1),
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeOutCubic,
            builder: (_, progress, child) => Opacity(
              opacity: progress,
              child: Transform.scale(scale: .97 + .03 * progress, child: child),
            ),
            child: Semantics(
              liveRegion: true,
              label: '播放完成：${widget.title}',
              child: Row(
                mainAxisSize: MainAxisSize.min,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  _button(
                    ui,
                    _restart,
                    Icons.replay_rounded,
                    '重播',
                    widget.onRestart,
                  ),
                  if (widget.onNext != null) ...[
                    SizedBox(width: 32 * ui),
                    _button(
                      ui,
                      _next,
                      Icons.skip_next_rounded,
                      '下一集',
                      widget.onNext!,
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _button(
    double ui,
    FocusNode node,
    IconData icon,
    String label,
    VoidCallback action,
  ) => Focus(
    focusNode: node,
    child: ListenableBuilder(
      listenable: node,
      builder: (context, _) => Semantics(
        button: true,
        focused: node.hasFocus,
        label: label,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () {
            node.requestFocus();
            action();
          },
          child: SizedBox(
            key: ValueKey('completed-$label'),
            width: 280 * ui,
            height: 220 * ui,
            child: buildPinkFocusEffect(
              ui: ui,
              radius: 20 * ui,
              isFocused: node.hasFocus,
              unfocusedColor: Colors.white.withValues(alpha: .35),
              backgroundColor: Colors.black.withValues(alpha: .52),
              focusedBackgroundColor: Colors.black.withValues(alpha: .72),
              scale: 1.03,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(18 * ui),
                child: BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 10 * ui, sigmaY: 10 * ui),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(icon, size: 80 * ui, color: Colors.white),
                      SizedBox(height: 12 * ui),
                      Text(
                        label,
                        style: TextStyle(
                          fontSize: 30 * ui,
                          height: 1.2,
                          color: Colors.white,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );
}

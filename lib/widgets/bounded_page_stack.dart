import 'package:flutter/material.dart';
import 'package:blt/utils/image_memory.dart';

/// Keep a small LRU of tab states. Transient tabs (search) never survive leaving.
class BoundedPageStack extends StatefulWidget {
  final int index, capacity;
  final List<Widget> children;
  final Set<int> discardWhenInactive;
  const BoundedPageStack({
    super.key,
    required this.index,
    required this.children,
    this.capacity = 2,
    this.discardWhenInactive = const {},
  }) : assert(capacity > 0);
  @override
  State<BoundedPageStack> createState() => _BoundedPageStackState();
}

class _BoundedPageStackState extends State<BoundedPageStack>
    with WidgetsBindingObserver {
  final _recent = <int>[];
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _activate();
  }

  @override
  void didUpdateWidget(covariant BoundedPageStack oldWidget) {
    super.didUpdateWidget(oldWidget);
    _activate();
  }

  void _activate() {
    final retainedBefore = _recent.toSet();
    _recent.removeWhere(
      (i) =>
          i >= widget.children.length ||
          (i != widget.index && widget.discardWhenInactive.contains(i)),
    );
    _recent.remove(widget.index);
    _recent.add(widget.index);
    while (_recent.length > widget.capacity) {
      _recent.removeAt(0);
    }
    if (retainedBefore.any((i) => !_recent.contains(i))) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        ImageMemoryBudget.instance.releaseUnusedImages();
      });
    }
  }

  @override
  void didHaveMemoryPressure() {
    if (mounted) {
      setState(
        () => _recent
          ..clear()
          ..add(widget.index),
      );
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => IndexedStack(
    index: widget.index,
    children: [
      for (var i = 0; i < widget.children.length; i++)
        _recent.contains(i)
            ? TickerMode(
                enabled: i == widget.index,
                child: ExcludeFocus(
                  excluding: i != widget.index,
                  child: widget.children[i],
                ),
              )
            : const SizedBox.shrink(),
    ],
  );
}

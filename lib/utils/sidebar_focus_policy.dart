import 'package:flutter/material.dart';

/// Preserve normal navigation inside a page; redirect only the crossing into
/// the main sidebar when moving left from the content region.
class SidebarFocusPolicy extends ReadingOrderTraversalPolicy {
  final _SidebarFocusState _state;
  factory SidebarFocusPolicy({
    required FocusNode sidebar,
    required FocusNode content,
    required FocusNode? Function() activeTarget,
  }) =>
      SidebarFocusPolicy._(_SidebarFocusState(sidebar, content, activeTarget));
  SidebarFocusPolicy._(this._state)
    : super(requestFocusCallback: _state.requestFocus);
  @override
  bool inDirection(FocusNode currentNode, TraversalDirection direction) {
    _state.source = currentNode;
    _state.direction = direction;
    try {
      return super.inDirection(currentNode, direction);
    } finally {
      _state.source = null;
      _state.direction = null;
    }
  }
}

class _SidebarFocusState {
  final FocusNode sidebar, content;
  final FocusNode? Function() activeTarget;
  FocusNode? source;
  TraversalDirection? direction;
  _SidebarFocusState(this.sidebar, this.content, this.activeTarget);
  void requestFocus(
    FocusNode node, {
    ScrollPositionAlignmentPolicy? alignmentPolicy,
    double? alignment,
    Duration? duration,
    Curve? curve,
  }) {
    var target = node;
    if (direction == TraversalDirection.left &&
        (source?.ancestors.contains(content) ?? false) &&
        node.ancestors.contains(sidebar)) {
      target = activeTarget() ?? node;
    }
    FocusTraversalPolicy.defaultTraversalRequestFocusCallback(
      target,
      alignmentPolicy: alignmentPolicy,
      alignment: alignment,
      duration: duration,
      curve: curve,
    );
  }
}

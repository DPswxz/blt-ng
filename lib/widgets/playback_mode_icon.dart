import 'package:blt/consts/settings.dart';
import 'package:flutter/material.dart';

IconData playbackModeIcon(PlayerLoopMode mode) => switch (mode) {
  PlayerLoopMode.none => Icons.help_outline_rounded,
  PlayerLoopMode.next => Icons.skip_next_rounded,
  PlayerLoopMode.single => Icons.repeat_one_rounded,
};

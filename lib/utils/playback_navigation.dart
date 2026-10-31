import 'package:flutter/material.dart';
import 'package:get/get.dart';

/// Platform video surfaces are created on a separate Android layer. Keep an
/// opaque black route under them and avoid sliding the old sidebar underneath.
Future<T?>? openPlaybackPage<T>(
  Widget Function() page, {
  bool replace = false,
}) {
  Widget buildPage() => ColoredBox(color: Colors.black, child: page());
  if (replace) {
    return Get.off<T>(
      buildPage,
      opaque: true,
      transition: Transition.noTransition,
      duration: Duration.zero,
      preventDuplicates: false,
    );
  }
  return Get.to<T>(
    buildPage,
    // Native detail routes can leave GetX tracking the same generic /Widget
    // name. The caller already guards repeated activation while playing.
    preventDuplicates: false,
    opaque: true,
    transition: Transition.noTransition,
    duration: Duration.zero,
  );
}

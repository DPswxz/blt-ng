import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class ImageMemoryBudget with WidgetsBindingObserver {
  static final instance = ImageMemoryBudget._();
  ImageMemoryBudget._();
  void install() {
    PaintingBinding.instance.imageCache
      ..maximumSize = 120
      ..maximumSizeBytes = 48 * 1024 * 1024;
    WidgetsBinding.instance.removeObserver(this);
    WidgetsBinding.instance.addObserver(this);
    _configureGraphicsCache();
  }

  Future<void> _configureGraphicsCache() async {
    try {
      // The TV uses Skia; its GPU cache is separate from Flutter's image cache.
      await SystemChannels.skia.invokeMethod<void>(
        'Skia.setResourceCacheMaxBytes',
        48 * 1024 * 1024,
      );
    } on MissingPluginException {
      // Other renderers may not expose a Skia resource cache.
    } on PlatformException {
      // Keep the image budget even if this renderer cannot change its GPU budget.
    }
  }

  @override
  void didHaveMemoryPressure() => releaseUnusedImages();

  // Active Image widgets keep their own listeners. Clearing the shared cache
  // releases images/codecs belonging to evicted pages without blanking the UI.
  void releaseUnusedImages() {
    PaintingBinding.instance.imageCache
      ..clear()
      ..clearLiveImages();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached) {
      PaintingBinding.instance.imageCache.clear();
    }
  }
}

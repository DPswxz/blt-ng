import 'package:blt/widgets/bilibili_image.dart';
import 'package:blt/utils/image_memory.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('缩略图解码限制适配显示尺寸，保留外部和已签名URL', () {
    expect(imageDecodeWidth(393, 1), 448);
    expect(imageDecodeWidth(4000, 2), 960);
    expect(imageDecodeWidth(64, 1), 128);
    expect(
      thumbnailUrl('https://i0.hdslb.com/bfs/a.jpg', 448),
      'https://i0.hdslb.com/bfs/a.jpg@448w.webp',
    );
    expect(
      thumbnailUrl('https://external.example/a.jpg', 448),
      'https://external.example/a.jpg',
    );
    expect(
      thumbnailUrl('https://i0.hdslb.com/a.jpg?token=test', 448),
      'https://i0.hdslb.com/a.jpg?token=test',
    );
  });
  test('内存图片和图形缓存有明确预算', () async {
    MethodCall? graphicsCall;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.skia, (call) async {
          graphicsCall = call;
          return true;
        });
    final cache = PaintingBinding.instance.imageCache;
    final count = cache.maximumSize, bytes = cache.maximumSizeBytes;
    ImageMemoryBudget.instance.install();
    expect(cache.maximumSize, 120);
    expect(cache.maximumSizeBytes, 48 * 1024 * 1024);
    await Future<void>.delayed(Duration.zero);
    expect(graphicsCall?.method, 'Skia.setResourceCacheMaxBytes');
    expect(graphicsCall?.arguments, 48 * 1024 * 1024);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.skia, null);
    WidgetsBinding.instance.removeObserver(ImageMemoryBudget.instance);
    cache
      ..maximumSize = count
      ..maximumSizeBytes = bytes;
  });
}

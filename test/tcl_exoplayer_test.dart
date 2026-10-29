import 'dart:async';
import 'package:blt/utils/tcl_video_controller.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:media_kit/media_kit.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('native decoder releases before event cancellation completes', () async {
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    const channel = MethodChannel('blt/media3/99');
    const events = MethodChannel('blt/media3/99/events');
    final cancelPending = Completer<void>();
    var released = false;
    messenger.setMockMethodCallHandler(channel, (call) async {
      if (call.method == 'release') released = true;
      return null;
    });
    messenger.setMockMethodCallHandler(events, (call) async {
      if (call.method == 'cancel') await cancelPending.future;
      return null;
    });
    final player = TclExoPlayer()..attach(99);
    await Future<void>.delayed(Duration.zero);
    final disposing = player.dispose();
    await Future<void>.delayed(Duration.zero);
    expect(released, isTrue);
    await player.play();
    cancelPending.complete();
    await disposing;
    await player.dispose();
    messenger.setMockMethodCallHandler(channel, null);
    messenger.setMockMethodCallHandler(events, null);
  });
  test(
    'ExoPlayer merges video/audio atomically and preserves seek/rate/loop commands',
    () async {
      final calls = <MethodCall>[];
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(const MethodChannel('blt/media3/42'), (
        call,
      ) async {
        calls.add(call);
        return null;
      });
      messenger.setMockMethodCallHandler(
        const MethodChannel('blt/media3/42/events'),
        (call) async => null,
      );
      final player = TclExoPlayer();
      player.attach(42);
      await player.openDash(
        'https://example.invalid/video.m4s',
        'https://example.invalid/audio.m4s',
        {'Referer': 'https://www.bilibili.com/'},
        const Duration(seconds: 13),
      );
      await player.seek(const Duration(seconds: 20));
      await player.setRate(1.25);
      await player.setPlaylistMode(PlaylistMode.single);
      final open = calls.firstWhere((c) => c.method == 'open');
      expect(open.arguments['audio'], 'https://example.invalid/audio.m4s');
      expect(open.arguments['start'], 13000);
      expect(open.arguments['headers']['Referer'], 'https://www.bilibili.com/');
      expect(calls.where((c) => c.method == 'open').length, 1);
      expect(
        calls.firstWhere((c) => c.method == 'seek').arguments['position'],
        20000,
      );
      expect(
        calls.firstWhere((c) => c.method == 'rate').arguments['value'],
        1.25,
      );
      expect(
        calls.firstWhere((c) => c.method == 'loop').arguments['value'],
        isTrue,
      );
      await player.dispose();
      expect(calls.last.method, 'release');
      messenger.setMockMethodCallHandler(
        const MethodChannel('blt/media3/42'),
        null,
      );
      messenger.setMockMethodCallHandler(
        const MethodChannel('blt/media3/42/events'),
        null,
      );
    },
  );
}

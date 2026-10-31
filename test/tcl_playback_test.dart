import 'package:blt/apis/bilibili/media.dart';
import 'package:blt/utils/playback_policy.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('优先音轨缺失时回退最高码率，不修改原始列表', () {
    const tracks = [
      DashMediaData(
        quality: 30216,
        codecId: 0,
        bandwidth: 64000,
        baseUrl: 'low',
        backupUrls: [],
      ),
      DashMediaData(
        quality: 30280,
        codecId: 0,
        bandwidth: 192000,
        baseUrl: 'high',
        backupUrls: [],
      ),
    ];
    expect(preferredAudioTrack(tracks, 30216)?.baseUrl, 'low');
    expect(preferredAudioTrack(tracks, 30232)?.baseUrl, 'high');
    expect(preferredAudioTrack(tracks, 0)?.baseUrl, 'high');
    expect(preferredAudioTrack([], 0), isNull);
    expect(tracks.first.baseUrl, 'low');
  });
  test('4K is requested without enabling HDR, Dolby or AV1', () {
    expect(webPlayParameters['fourk'], 1);
    expect(webPlayParameters['fnval'], 144);
  });
  test(
    'web quality order and names are preserved even without entitlement',
    () {
      final response = GetVideoPlayURLResponse.fromJson({
        'support_formats': [
          {'quality': 120, 'new_description': '4K 超清'},
          {'quality': 80, 'new_description': '1080P 高清'},
        ],
        'dash': {
          'video': [
            {
              'id': 80,
              'base_url': 'https://example.invalid/avc',
              'codecid': 7,
              'width': 1920,
              'height': 1080,
              'frame_rate': '60000/1001',
            },
          ],
        },
      });
      expect(response.supportFormats.map((q) => q.id), [120, 80]);
      expect(response.supportFormats.first.description, '4K 超清');
      expect(response.dashData.video.single.fps, closeTo(59.94, 0.01));
    },
  );
  test(
    'only hardware-supported streams are selected; AVC before HEVC',
    () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
            const MethodChannel('blt/playback'),
            (call) async => (call.arguments as Map)['codec'] != 13,
          );
      const streams = [
        DashMediaData(
          quality: 120,
          codecId: 13,
          baseUrl: 'av1',
          backupUrls: [],
        ),
        DashMediaData(
          quality: 120,
          codecId: 12,
          baseUrl: 'hevc',
          backupUrls: [],
        ),
        DashMediaData(quality: 120, codecId: 7, baseUrl: 'avc', backupUrls: []),
      ];
      expect((await compatibleStreams(streams)).map((s) => s.baseUrl), [
        'avc',
        'hevc',
      ]);
    },
  );
  test('codec errors are distinct from network failures', () {
    expect(isCodecError('Could not open codec'), isTrue);
    expect(isCodecError('Failed to initialize codec'), isTrue);
    expect(isCodecError('HTTP error 403'), isFalse);
  });
  test(
    'smooth default picks standard 1080p then lower; never 4K or high-bitrate',
    () {
      final qualities = [
        120,
        116,
        112,
        80,
        64,
        32,
      ].map((id) => Quality(id: id, description: '$id')).toList();
      expect(smoothQualityOrder(qualities).map((q) => q.id), [80, 64, 32]);
      expect(
        smoothQualityOrder(
          qualities.where((q) => q.id != 80).toList(),
        ).first.id,
        64,
      );
    },
  );
  test(
    'default quality selection respects chosen maximum and falls back lower',
    () {
      final all = [
        120,
        112,
        80,
        64,
        32,
        16,
      ].map((id) => Quality(id: id, description: '$id')).toList();
      expect(defaultQualityOrder(all, 64).map((q) => q.id), [64, 32, 16]);
      expect(
        defaultQualityOrder(all.where((q) => q.id != 80).toList(), 80).first.id,
        64,
      );
      expect(defaultQualityOrder(all, 16).single.id, 16);
    },
  );

  test('4K默认画质优先选择真实4K，缺少4K时回退普通1080P', () {
    final available = [
      120,
      112,
      80,
      64,
      32,
    ].map((id) => Quality(id: id, description: '$id')).toList();
    expect(defaultQualityOrder(available, 120).map((q) => q.id), [
      120,
      80,
      64,
      32,
    ]);
    expect(
      defaultQualityOrder(
        available.where((q) => q.id != 120).toList(),
        120,
      ).first.id,
      80,
    );
    expect(defaultQualityOrder(available, 80).first.id, 80);
  });
}

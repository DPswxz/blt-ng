import 'package:flutter/services.dart';
import 'package:blt/apis/bilibili/media.dart';

const _channel = MethodChannel('blt/playback');
bool isCodecError(String error) => RegExp(
  r'(could.?n.?t|cannot|can not|failed to).*(open|init).*codec|decoder.*(failed|error)',
  caseSensitive: false,
).hasMatch(error);

Future<List<DashMediaData>> compatibleStreams(
  List<DashMediaData> streams,
) async {
  final supported = <DashMediaData>[];
  for (final stream in streams) {
    try {
      final ok = await _channel.invokeMethod<bool>('supports', {
        'codec': stream.codecId,
        'width': stream.width,
        'height': stream.height,
        'fps': stream.fps,
      });
      if (ok == true) supported.add(stream);
    } on MissingPluginException {
      if (stream.codecId == 7 || stream.codecId == 12) supported.add(stream);
    } on PlatformException {
      if (stream.codecId == 7) supported.add(stream);
    }
  }
  // Preserve quality, prefer AVC then HEVC. Never choose software-only AV1 for 4K.
  supported.sort((a, b) {
    int rank(int codec) => codec == 7
        ? 0
        : codec == 12
        ? 1
        : 2;
    final frameRate = (a.fps > 30 ? 1 : 0).compareTo(b.fps > 30 ? 1 : 0);
    if (frameRate != 0) return frameRate;
    final codec = rank(a.codecId).compareTo(rank(b.codecId));
    return codec != 0 ? codec : a.bandwidth.compareTo(b.bandwidth);
  });
  return supported;
}

// Standard 1080p first. Higher frame-rate/high-bitrate tiers are manual choices.
List<Quality> smoothQualityOrder(List<Quality> qualities) {
  const order = [80, 64, 74, 32, 16, 6];
  return [for (final id in order) ...qualities.where((q) => q.id == id)];
}

const decoderLabels = {
  'auto': '自动（ExoPlayer）',
  'exo': 'ExoPlayer 硬解',
  'native': 'MPV 原生硬解',
  'gpu': 'MPV 兼容硬解',
  'copy': 'MPV 复制硬解',
  'software': 'MPV 软件解码',
};
const defaultQualityLabels = {
  120: '4K 超高清 · 大会员',
  112: '1080P 高码率 · 大会员',
  80: '1080P 高清',
  64: '720P 准高清',
  32: '480P 标清',
  16: '360P 流畅',
};
const preferredCodecLabels = {0: '自动（AVC 优先）', 7: 'AVC 优先', 12: 'HEVC 优先'};
List<Quality> defaultQualityOrder(List<Quality> qualities, int maximum) {
  final order = smoothQualityOrder(qualities);
  if (maximum == 120 || maximum == 112) {
    return [...qualities.where((q) => q.id == maximum), ...order];
  }
  const levels = [80, 64, 74, 32, 16, 6];
  final cap = levels.indexOf(maximum);
  return order
      .where((q) => levels.indexOf(q.id) >= (cap < 0 ? 0 : cap))
      .toList();
}
